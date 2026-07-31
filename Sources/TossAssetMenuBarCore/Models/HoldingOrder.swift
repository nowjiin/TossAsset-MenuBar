import Foundation

/// 보유 종목의 사용자 지정 순서.
///
/// 저장하는 것은 **심볼 배열**이다. 종목 자체를 저장하면 수량·가격이 바뀔 때마다 낡은 값이
/// 남고, API 가 종목을 빼면 지울 시점을 알 수 없다. 심볼만 두면 순서는 순서대로만 남는다.
public enum HoldingOrder {
    /// 저장된 순서를 적용한다.
    ///
    /// 순서에 없는 종목 — 새로 산 종목이 여기 해당한다 — 은 **뒤에, 원래 순서 그대로** 붙인다.
    /// 앞에 붙이면 새 종목이 사용자가 맨 위에 둔 종목을 밀어낸다.
    public static func apply(_ items: [HoldingsItem], order: [String]) -> [HoldingsItem] {
        guard !order.isEmpty else { return items }

        var rank: [String: Int] = [:]
        for (index, symbol) in order.enumerated() where rank[symbol] == nil {
            rank[symbol] = index
        }

        // 원래 위치를 함께 들고 정렬해 안정성을 보장한다. 순서에 없는 종목끼리는
        // API 가 준 순서를 유지해야 목록이 새로고침마다 흔들리지 않는다.
        return items.enumerated()
            .sorted { left, right in
                let leftRank = rank[left.element.symbol] ?? Int.max
                let rightRank = rank[right.element.symbol] ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    /// 배열 안에서 항목을 옮긴다. SwiftUI 의 `onMove(perform:)` 와 같은 의미다.
    ///
    /// SwiftUI 가 제공하는 `move(fromOffsets:toOffset:)` 를 쓰지 않는 이유는 그것이 SwiftUI
    /// 프레임워크에 들어 있기 때문이다. `Core` 는 UI 에 의존하지 않아야 검증 러너가 호출할 수 있다.
    public static func moving(
        _ symbols: [String],
        from source: IndexSet,
        to destination: Int
    ) -> [String] {
        let picked = source.sorted().compactMap { symbols.indices.contains($0) ? symbols[$0] : nil }
        guard !picked.isEmpty else { return symbols }

        var rest = symbols
        for index in source.sorted(by: >) where rest.indices.contains(index) {
            rest.remove(at: index)
        }

        // 앞쪽에서 빠진 개수만큼 목적지가 당겨진다.
        let removedBefore = source.filter { $0 < destination }.count
        let insertion = min(max(0, destination - removedBefore), rest.count)
        rest.insert(contentsOf: picked, at: insertion)
        return rest
    }

    /// 화면에 보이는 일부만 옮겼을 때, 그 결과를 전체 순서에 반영한다.
    ///
    /// 세그먼트(`국내`/`해외`)나 관심종목 필터가 걸려 있으면 사용자는 **부분 집합**을 옮긴다.
    /// 그 부분의 새 상대 순서를, 원래 그 종목들이 차지하던 자리에 그대로 끼워 넣는다.
    /// 그래야 화면에 없던 종목의 위치가 멋대로 바뀌지 않는다.
    public static func applyingMove(
        to stored: [String],
        visible: [String],
        from source: IndexSet,
        to destination: Int
    ) -> [String] {
        let reordered = moving(visible, from: source, to: destination)

        // 저장된 순서에 아직 없는 종목(새로 산 것)을 뒤에 채워 기준 배열을 만든다.
        var base = stored
        for symbol in visible where !base.contains(symbol) {
            base.append(symbol)
        }

        let visibleSet = Set(visible)
        var queue = reordered[...]
        var result: [String] = []
        result.reserveCapacity(base.count)

        for symbol in base {
            if visibleSet.contains(symbol) {
                // 보이던 자리마다 새 순서를 앞에서부터 채워 넣는다.
                if let next = queue.first {
                    result.append(next)
                    queue = queue.dropFirst()
                }
            } else {
                result.append(symbol)
            }
        }
        return result
    }

    /// 지금 보유하지 않는 종목을 순서에서 덜어낸다.
    ///
    /// 전량 매도한 종목이 계속 남으면 순서 배열이 끝없이 길어지고, 나중에 다시 사면
    /// 예전 자리로 튀어 올라간다. 사용자는 그 자리를 기억하지 못한다.
    public static func pruned(_ order: [String], keeping symbols: some Sequence<String>) -> [String] {
        let alive = Set(symbols)
        return order.filter { alive.contains($0) }
    }
}
