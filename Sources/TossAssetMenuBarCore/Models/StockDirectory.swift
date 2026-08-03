import Foundation

/// 한글 이름으로 심볼을 찾기 위한 항목.
public struct StockDirectoryEntry: Sendable, Hashable, Identifiable {
    public let symbol: String
    public let name: String
    /// 줄여 부르는 말. `삼전`, `하이닉스`, `엘지엔솔` 처럼 실제로 치는 표현을 담는다.
    public let aliases: [String]

    public var id: String { symbol }

    public init(symbol: String, name: String, aliases: [String] = []) {
        self.symbol = symbol
        self.name = name
        self.aliases = aliases
    }
}

/// 한글 이름 ↔ 심볼 사전.
///
/// 토스 Open API 에는 **이름 검색이 없다.** `/stocks` 는 심볼만 받는다. 외부 검색도 알아봤지만
/// Yahoo Finance 는 한글 질의를 `400 Invalid Search Query` 로 거절한다 (`samsung` 은 되고
/// `삼성` 은 안 된다). 그래서 목록을 직접 들고 있는다.
///
/// 두 갈래로 채운다.
///   1. `builtIn` — 자주 찾는 종목을 미리 담아 둔다.
///   2. 사용자가 이미 담은 종목 — 보유·관심종목의 이름은 토스가 준다. 목록에 없던 종목도
///      한 번 담고 나면 다음부터 이름으로 찾힌다.
///
/// **여기 적힌 이름은 후보를 고르기 위한 것일 뿐이다.** 추가한 뒤 화면에 남는 이름은 토스
/// `/stocks` 가 준 값이라, 사전의 매핑이 틀렸다면 다른 이름이 나타나 바로 눈에 띈다.
public enum StockDirectory {
    /// 검색어를 비교하기 좋게 다듬는다. 공백을 지우는 이유는 `엘지 에너지솔루션` 처럼
    /// 띄어쓰기를 다르게 치는 경우가 흔하기 때문이다.
    public static func fold(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    /// 이름·별칭·심볼에서 찾는다. 정확히 일치 → 앞부분 일치 → 포함 순으로 앞에 둔다.
    ///
    /// 부분 일치를 허용하는 이유는 `하이닉스` 로 `SK하이닉스` 를 찾기 위해서다.
    /// 순위를 나누는 이유는, 포함만으로 정렬하면 `삼성` 을 쳤을 때 `삼성전자` 가
    /// `삼성에스디에스` 뒤로 밀릴 수 있기 때문이다.
    public static func search(
        _ query: String,
        in entries: [StockDirectoryEntry],
        limit: Int = 8
    ) -> [StockDirectoryEntry] {
        let needle = fold(query)
        guard !needle.isEmpty else { return [] }

        var scored: [(entry: StockDirectoryEntry, rank: Int, order: Int)] = []
        for (index, entry) in entries.enumerated() {
            let haystacks = ([entry.name, entry.symbol] + entry.aliases).map(fold)
            guard let rank = haystacks.compactMap({ candidate -> Int? in
                if candidate == needle { return 0 }
                if candidate.hasPrefix(needle) { return 1 }
                if candidate.contains(needle) { return 2 }
                return nil
            }).min() else { continue }
            scored.append((entry, rank, index))
        }

        var seen = Set<String>()
        return scored
            .sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
            .filter { seen.insert($0.entry.symbol).inserted }
            .prefix(max(1, limit))
            .map(\.entry)
    }

    /// 미리 담아 둔 종목.
    ///
    /// 전 종목을 담지는 않는다. 상장·개명이 있을 때마다 손봐야 하므로, 자주 찾는 것만 둔다.
    /// 목록에 없어도 심볼을 직접 입력하면 담을 수 있고, 한 번 담으면 그다음부터는 찾힌다.
    public static let builtIn: [StockDirectoryEntry] = [
        // 국내 — 시가총액 상위·자주 거래되는 종목
        .init(symbol: "005930", name: "삼성전자", aliases: ["삼전", "삼성"]),
        .init(symbol: "005935", name: "삼성전자우", aliases: ["삼전우", "삼성전자 우선주"]),
        .init(symbol: "000660", name: "SK하이닉스", aliases: ["하이닉스", "에스케이하이닉스"]),
        .init(symbol: "373220", name: "LG에너지솔루션", aliases: ["엘지에너지솔루션", "엘지엔솔", "lg엔솔"]),
        .init(symbol: "207940", name: "삼성바이오로직스", aliases: ["삼바", "삼성바이오"]),
        .init(symbol: "005380", name: "현대차", aliases: ["현대자동차"]),
        .init(symbol: "000270", name: "기아", aliases: ["기아차"]),
        .init(symbol: "068270", name: "셀트리온", aliases: []),
        .init(symbol: "035420", name: "NAVER", aliases: ["네이버"]),
        .init(symbol: "035720", name: "카카오", aliases: []),
        .init(symbol: "051910", name: "LG화학", aliases: ["엘지화학"]),
        .init(symbol: "006400", name: "삼성SDI", aliases: ["삼성에스디아이", "sdi"]),
        .init(symbol: "005490", name: "POSCO홀딩스", aliases: ["포스코", "포스코홀딩스"]),
        .init(symbol: "003670", name: "포스코퓨처엠", aliases: ["퓨처엠", "포스코케미칼"]),
        .init(symbol: "012330", name: "현대모비스", aliases: ["모비스"]),
        .init(symbol: "066570", name: "LG전자", aliases: ["엘지전자"]),
        .init(symbol: "009150", name: "삼성전기", aliases: []),
        .init(symbol: "011070", name: "LG이노텍", aliases: ["엘지이노텍"]),
        .init(symbol: "034220", name: "LG디스플레이", aliases: ["엘지디스플레이", "엘지디플"]),
        .init(symbol: "018260", name: "삼성에스디에스", aliases: ["삼성sds", "sds"]),
        .init(symbol: "028260", name: "삼성물산", aliases: []),
        .init(symbol: "032830", name: "삼성생명", aliases: []),
        .init(symbol: "000810", name: "삼성화재", aliases: []),
        .init(symbol: "105560", name: "KB금융", aliases: ["케이비금융", "국민은행"]),
        .init(symbol: "055550", name: "신한지주", aliases: ["신한금융", "신한은행"]),
        .init(symbol: "086790", name: "하나금융지주", aliases: ["하나금융", "하나은행"]),
        .init(symbol: "316140", name: "우리금융지주", aliases: ["우리금융", "우리은행"]),
        .init(symbol: "015760", name: "한국전력", aliases: ["한전"]),
        .init(symbol: "017670", name: "SK텔레콤", aliases: ["에스케이텔레콤", "skt"]),
        .init(symbol: "030200", name: "KT", aliases: ["케이티"]),
        .init(symbol: "032640", name: "LG유플러스", aliases: ["엘지유플러스", "유플러스"]),
        .init(symbol: "034730", name: "SK", aliases: ["에스케이"]),
        .init(symbol: "003550", name: "LG", aliases: ["엘지"]),
        .init(symbol: "033780", name: "KT&G", aliases: ["케이티앤지"]),
        .init(symbol: "096770", name: "SK이노베이션", aliases: ["에스케이이노베이션", "sk이노"]),
        .init(symbol: "010950", name: "S-Oil", aliases: ["에스오일"]),
        .init(symbol: "010130", name: "고려아연", aliases: []),
        .init(symbol: "004020", name: "현대제철", aliases: []),
        .init(symbol: "011200", name: "HMM", aliases: ["에이치엠엠", "현대상선"]),
        .init(symbol: "009540", name: "HD한국조선해양", aliases: ["한국조선해양", "현대중공업지주"]),
        .init(symbol: "010140", name: "삼성중공업", aliases: ["삼중"]),
        .init(symbol: "042660", name: "한화오션", aliases: ["대우조선해양"]),
        .init(symbol: "012450", name: "한화에어로스페이스", aliases: ["한화에어로", "한화테크윈"]),
        .init(symbol: "047810", name: "한국항공우주", aliases: ["kai"]),
        .init(symbol: "064350", name: "현대로템", aliases: ["로템"]),
        .init(symbol: "000720", name: "현대건설", aliases: []),
        .init(symbol: "042700", name: "한미반도체", aliases: ["한미"]),
        .init(symbol: "000990", name: "DB하이텍", aliases: ["디비하이텍"]),
        .init(symbol: "051900", name: "LG생활건강", aliases: ["엘지생활건강", "엘지생건"]),
        .init(symbol: "090430", name: "아모레퍼시픽", aliases: ["아모레"]),
        .init(symbol: "097950", name: "CJ제일제당", aliases: ["씨제이제일제당", "제일제당"]),
        .init(symbol: "271560", name: "오리온", aliases: []),
        .init(symbol: "004370", name: "농심", aliases: []),
        .init(symbol: "139480", name: "이마트", aliases: []),
        .init(symbol: "000100", name: "유한양행", aliases: []),
        .init(symbol: "128940", name: "한미약품", aliases: []),
        .init(symbol: "326030", name: "SK바이오팜", aliases: ["에스케이바이오팜"]),
        .init(symbol: "302440", name: "SK바이오사이언스", aliases: ["에스케이바이오사이언스"]),
        .init(symbol: "196170", name: "알테오젠", aliases: []),
        .init(symbol: "086520", name: "에코프로", aliases: []),
        .init(symbol: "247540", name: "에코프로비엠", aliases: ["에코프로bm"]),
        .init(symbol: "066970", name: "엘앤에프", aliases: ["l&f"]),
        .init(symbol: "036570", name: "엔씨소프트", aliases: ["엔씨", "ncsoft"]),
        .init(symbol: "259960", name: "크래프톤", aliases: ["배틀그라운드"]),
        .init(symbol: "251270", name: "넷마블", aliases: []),
        .init(symbol: "293490", name: "카카오게임즈", aliases: []),
        .init(symbol: "352820", name: "하이브", aliases: ["hybe", "빅히트"]),
        .init(symbol: "041510", name: "에스엠", aliases: ["sm엔터", "sm"]),
        .init(symbol: "035900", name: "JYP Ent.", aliases: ["jyp"]),
        .init(symbol: "122870", name: "와이지엔터테인먼트", aliases: ["yg", "와이지"]),
        .init(symbol: "161390", name: "한국타이어앤테크놀로지", aliases: ["한국타이어"]),
        .init(symbol: "204320", name: "HL만도", aliases: ["만도"]),
        .init(symbol: "018880", name: "한온시스템", aliases: []),
        .init(symbol: "006260", name: "LS", aliases: ["엘에스"]),
        .init(symbol: "010120", name: "LS ELECTRIC", aliases: ["엘에스일렉트릭", "ls일렉트릭"]),
        .init(symbol: "267260", name: "HD현대일렉트릭", aliases: ["현대일렉트릭"]),
        .init(symbol: "103140", name: "풍산", aliases: []),
        .init(symbol: "001040", name: "CJ", aliases: ["씨제이"]),

        // 국내 ETF
        .init(symbol: "069500", name: "KODEX 200", aliases: ["코덱스200", "코스피200"]),
        .init(symbol: "102110", name: "TIGER 200", aliases: ["타이거200"]),
        .init(symbol: "122630", name: "KODEX 레버리지", aliases: ["코덱스레버리지", "레버리지"]),
        .init(symbol: "252670", name: "KODEX 200선물인버스2X", aliases: ["곱버스", "인버스2x", "코덱스인버스"]),
        .init(symbol: "233740", name: "KODEX 코스닥150레버리지", aliases: ["코스닥레버리지"]),
        .init(symbol: "360750", name: "TIGER 미국S&P500", aliases: ["타이거sp500", "미국sp500"]),
        .init(symbol: "133690", name: "TIGER 미국나스닥100", aliases: ["타이거나스닥", "나스닥100"]),

        // 해외 — 한글 표기로 찾는 경우가 많다
        .init(symbol: "AAPL", name: "애플", aliases: ["apple", "아이폰"]),
        .init(symbol: "MSFT", name: "마이크로소프트", aliases: ["microsoft", "마소"]),
        .init(symbol: "NVDA", name: "엔비디아", aliases: ["nvidia", "엔비"]),
        .init(symbol: "GOOGL", name: "알파벳", aliases: ["구글", "google", "alphabet"]),
        .init(symbol: "AMZN", name: "아마존", aliases: ["amazon"]),
        .init(symbol: "META", name: "메타", aliases: ["페이스북", "facebook"]),
        .init(symbol: "TSLA", name: "테슬라", aliases: ["tesla"]),
        .init(symbol: "NFLX", name: "넷플릭스", aliases: ["netflix"]),
        .init(symbol: "AVGO", name: "브로드컴", aliases: ["broadcom"]),
        .init(symbol: "AMD", name: "AMD", aliases: ["에이엠디"]),
        .init(symbol: "INTC", name: "인텔", aliases: ["intel"]),
        .init(symbol: "QCOM", name: "퀄컴", aliases: ["qualcomm"]),
        .init(symbol: "MU", name: "마이크론", aliases: ["micron"]),
        .init(symbol: "TSM", name: "TSMC", aliases: ["타이완반도체", "대만반도체"]),
        .init(symbol: "ASML", name: "ASML", aliases: ["에이에스엠엘"]),
        .init(symbol: "ARM", name: "ARM", aliases: ["암홀딩스"]),
        .init(symbol: "MRVL", name: "마벨", aliases: ["marvell"]),
        .init(symbol: "ORCL", name: "오라클", aliases: ["oracle"]),
        .init(symbol: "CRM", name: "세일즈포스", aliases: ["salesforce"]),
        .init(symbol: "ADBE", name: "어도비", aliases: ["adobe"]),
        .init(symbol: "PLTR", name: "팔란티어", aliases: ["palantir"]),
        .init(symbol: "CRWD", name: "크라우드스트라이크", aliases: ["crowdstrike"]),
        .init(symbol: "SMCI", name: "슈퍼마이크로컴퓨터", aliases: ["슈마컴", "supermicro"]),
        .init(symbol: "COIN", name: "코인베이스", aliases: ["coinbase"]),
        .init(symbol: "UBER", name: "우버", aliases: []),
        .init(symbol: "DIS", name: "디즈니", aliases: ["disney"]),
        .init(symbol: "KO", name: "코카콜라", aliases: ["coca cola"]),
        .init(symbol: "MCD", name: "맥도날드", aliases: []),
        .init(symbol: "NKE", name: "나이키", aliases: ["nike"]),
        .init(symbol: "SBUX", name: "스타벅스", aliases: ["starbucks"]),
        .init(symbol: "V", name: "비자", aliases: ["visa"]),
        .init(symbol: "MA", name: "마스터카드", aliases: ["mastercard"]),
        .init(symbol: "JPM", name: "JP모건", aliases: ["제이피모건"]),
        .init(symbol: "BRK-B", name: "버크셔해서웨이", aliases: ["버크셔", "berkshire"]),
        .init(symbol: "LLY", name: "일라이릴리", aliases: ["릴리"]),
        .init(symbol: "UNH", name: "유나이티드헬스", aliases: []),
        .init(symbol: "XOM", name: "엑슨모빌", aliases: ["exxon"]),
        .init(symbol: "BA", name: "보잉", aliases: ["boeing"]),
        .init(symbol: "GE", name: "GE", aliases: ["제너럴일렉트릭"]),
        .init(symbol: "IBM", name: "IBM", aliases: ["아이비엠"]),
        .init(symbol: "CSCO", name: "시스코", aliases: ["cisco"]),

        // 해외 ETF
        .init(symbol: "SPY", name: "S&P500 ETF", aliases: ["에스피500", "스파이"]),
        .init(symbol: "QQQ", name: "나스닥100 ETF", aliases: ["큐큐큐", "나스닥"]),
        .init(symbol: "VOO", name: "뱅가드 S&P500", aliases: ["뱅가드"]),
        .init(symbol: "SCHD", name: "슈드", aliases: ["배당"]),
        .init(symbol: "SOXL", name: "반도체 3배 ETF", aliases: ["속슬", "소슬"]),
        .init(symbol: "TQQQ", name: "나스닥 3배 ETF", aliases: ["티큐큐큐"]),
    ]
}
