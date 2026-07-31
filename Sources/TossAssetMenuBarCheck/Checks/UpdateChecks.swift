import Foundation
import TossAssetMenuBarCore

/// 버전 비교와 GitHub Release 조회.
func runUpdateChecks(_ check: CheckHarness) async throws {
    await check.group("AppVersion — semver 파싱과 비교")

    await check.expectEqual(AppVersion("0.1.0")?.description, "0.1.0", "기본 형식")
    await check.expectEqual(AppVersion("v0.2.3")?.description, "0.2.3", "릴리스 태그의 v 접두사를 떼어낸다")
    await check.expectEqual(AppVersion("1.2")?.description, "1.2.0", "patch 가 없으면 0 으로 채운다")
    await check.expectEqual(AppVersion("2")?.description, "2.0.0", "major 만 있어도 받는다")
    await check.expectEqual(AppVersion("0.3.0-beta.1")?.description, "0.3.0", "pre-release 표기는 앞부분만 본다")

    await check.expect(AppVersion("") == nil, "빈 문자열은 거부한다")
    await check.expect(AppVersion("latest") == nil, "숫자가 아니면 거부한다")
    await check.expect(AppVersion("1.2.3.4") == nil, "네 자리는 거부한다")
    await check.expect(AppVersion("1..3") == nil, "빈 구성요소는 거부한다")

    // 문자열 비교로는 "0.10.0" < "0.9.0" 이 되어버린다. 숫자 비교인지 확인한다.
    await check.expect(AppVersion("0.9.0")! < AppVersion("0.10.0")!, "0.9.0 < 0.10.0 (문자열 비교면 반대가 된다)")
    await check.expect(AppVersion("0.1.0")! < AppVersion("0.1.1")!, "patch 증가")
    await check.expect(AppVersion("0.1.9")! < AppVersion("0.2.0")!, "minor 가 patch 보다 우선")
    await check.expect(AppVersion("0.9.9")! < AppVersion("1.0.0")!, "major 가 가장 우선")
    await check.expectEqual(AppVersion("v1.0.0"), AppVersion("1.0.0"), "v 접두사만 다르면 같은 버전")

    await check.group("BuildLabel — 로컬 빌드 표식")

    await check.expectEqual(
        BuildLabel.display(shortVersion: "0.3.0", bundleVersion: "0.3.0"),
        "0.3.0",
        "릴리스 빌드는 두 값이 같아 표식이 없다"
    )
    await check.expectEqual(
        BuildLabel.display(shortVersion: "0.3.0", bundleVersion: "0.3.0+3"),
        "0.3.0 +3",
        "태그 이후 3커밋이면 +3 을 붙인다"
    )
    await check.expectEqual(
        BuildLabel.display(shortVersion: "0.3.0", bundleVersion: "0.3.0+3.dirty"),
        "0.3.0 +3.dirty",
        "작업 트리가 더러우면 .dirty 까지 보여준다"
    )
    await check.expectEqual(
        BuildLabel.display(shortVersion: "0.3.0", bundleVersion: "0.3.0.dirty"),
        "0.3.0 .dirty",
        "커밋은 없고 수정만 있어도 로컬 빌드로 표시한다"
    )
    await check.expect(
        BuildLabel.localSuffix(shortVersion: "0.3.0", bundleVersion: "0.3.0") == nil,
        "릴리스 빌드에는 표식이 없다"
    )
    await check.expect(
        BuildLabel.localSuffix(shortVersion: "0.3.0", bundleVersion: nil) == nil,
        "CFBundleVersion 이 없으면 표식을 만들지 않는다"
    )
    await check.expectEqual(
        BuildLabel.display(shortVersion: nil, bundleVersion: nil),
        "0.0.0",
        "둘 다 없으면 0.0.0 으로 떨어진다"
    )

    do {
        // 핵심 회귀: short 쪽에 `+` 가 들어가면 AppVersion 이 파싱하지 못해 버전이 통째로
        // 깨지고, 업데이트 비교가 0.0.0 기준이 되어 항상 "새 버전 있음" 이 뜬다.
        await check.expect(
            AppVersion("0.3.0+3") == nil,
            "AppVersion 은 + 를 파싱하지 못한다 — 그래서 빌드 정보는 CFBundleVersion 에만 둔다"
        )
        await check.expectEqual(
            AppVersion("0.3.0"), AppVersion("0.3.0"),
            "로컬 빌드도 태그 버전으로 비교하므로 최신 릴리스와 같다고 판단한다"
        )
    }

    await check.group("UpdateSchedule — 하루에 한 번 자동 확인")

    do {
        let now = kst("2026-07-29T12:00:00+09:00")

        await check.expect(
            UpdateSchedule.isDue(lastCheckedAt: nil, now: now),
            "한 번도 확인하지 않았으면 바로 확인한다"
        )
        await check.expect(
            !UpdateSchedule.isDue(lastCheckedAt: now.addingTimeInterval(-3600), now: now),
            "1시간 전에 확인했으면 건너뛴다"
        )
        await check.expect(
            !UpdateSchedule.isDue(lastCheckedAt: now.addingTimeInterval(-23 * 3600), now: now),
            "23시간 전이면 아직 이르다"
        )
        await check.expect(
            UpdateSchedule.isDue(lastCheckedAt: now.addingTimeInterval(-24 * 3600), now: now),
            "정확히 24시간이 지나면 확인한다"
        )
        await check.expect(
            UpdateSchedule.isDue(lastCheckedAt: now.addingTimeInterval(-72 * 3600), now: now),
            "며칠 지났으면 당연히 확인한다"
        )
        // 시계를 되돌리면 lastCheckedAt 이 미래가 된다. 그대로 두면 영구히 확인하지 않는다.
        await check.expect(
            UpdateSchedule.isDue(lastCheckedAt: now.addingTimeInterval(3600), now: now),
            "마지막 확인이 미래로 기록돼 있으면 확인한다 (시계 되돌림 대비)"
        )
        await check.expectEqual(UpdateSchedule.interval, 24 * 60 * 60, "주기는 하루다")
    }

    await check.group("UpdateChecker — GitHub Release 조회")

    let releasePath = "/repos/nowjiin/TossAsset-MenuBar/releases/latest"

    func checker(_ stub: StubTransport.Stub) -> (UpdateChecker, StubTransport) {
        let transport = StubTransport(stubs: [releasePath: [stub]])
        return (UpdateChecker(repository: "nowjiin/TossAsset-MenuBar", transport: transport), transport)
    }

    do {
        let body = #"{"tag_name":"v0.2.0","html_url":"https://github.com/nowjiin/TossAsset-MenuBar/releases/tag/v0.2.0"}"#
        let (updater, transport) = checker(.init(body: body))
        let status = await updater.check(current: AppVersion("0.1.0")!)

        if case .available(let release) = status {
            await check.expectEqual(release.version.description, "0.2.0", "새 버전을 찾아낸다")
            await check.expectEqual(release.tag, "v0.2.0", "태그를 그대로 보존한다")
            await check.expect(release.pageURL.absoluteString.hasSuffix("v0.2.0"), "릴리스 페이지 주소를 읽는다")
        } else {
            await check.expect(false, "새 버전이 있으면 .available 이어야 한다 (실제 \(status))")
        }

        // GitHub API 는 User-Agent 가 없으면 403 을 준다.
        await check.expectEqual(
            transport.header("User-Agent", forPath: releasePath),
            "TossAsset-MenuBar",
            "User-Agent 를 반드시 보낸다"
        )
        await check.expectEqual(
            transport.header("Accept", forPath: releasePath),
            "application/vnd.github+json",
            "GitHub API 버전을 Accept 로 지정한다"
        )
    }

    do {
        // 같은 버전이면 업데이트가 아니다.
        let body = #"{"tag_name":"v0.1.0","html_url":"https://example.com"}"#
        let (updater, _) = checker(.init(body: body))
        let status = await updater.check(current: AppVersion("0.1.0")!)
        if case .upToDate = status {
            await check.expect(true, "같은 버전이면 최신으로 판단한다")
        } else {
            await check.expect(false, "같은 버전은 .upToDate 여야 한다 (실제 \(status))")
        }
    }

    do {
        // 로컬이 릴리스보다 높은 개발 빌드. 다운그레이드를 권하면 안 된다.
        let body = #"{"tag_name":"v0.1.0","html_url":"https://example.com"}"#
        let (updater, _) = checker(.init(body: body))
        let status = await updater.check(current: AppVersion("0.9.0")!)
        if case .upToDate = status {
            await check.expect(true, "로컬이 더 높으면 업데이트를 권하지 않는다")
        } else {
            await check.expect(false, "다운그레이드를 제안해선 안 된다 (실제 \(status))")
        }
    }

    do {
        // 릴리스를 아직 만들지 않은 상태. 받을 새 버전이 없으니 최신으로 본다.
        // (저장소 오타·비공개도 404 라서 사용자에게는 최신으로 보인다 — 로그로만 추적한다.)
        let (updater, _) = checker(.init(status: 404, body: #"{"message":"Not Found"}"#))
        let status = await updater.check(current: AppVersion("0.1.0")!)
        if case .upToDate(let current) = status {
            await check.expectEqual(current.description, "0.1.0", "404 는 최신 버전으로 처리한다")
        } else {
            await check.expect(false, "404 는 .upToDate 여야 한다 (실제 \(status))")
        }
    }

    do {
        // 인증 없는 GitHub API 는 IP 당 시간당 60회 제한이 있다.
        // 공용 회선에서는 사용자가 아무것도 안 했는데 걸릴 수 있어 대기 시간을 알려준다.
        let reset = Date().addingTimeInterval(23 * 60).timeIntervalSince1970
        let (updater, _) = checker(.init(
            status: 403,
            body: #"{"message":"API rate limit exceeded"}"#,
            headers: [
                "X-RateLimit-Remaining": "0",
                "X-RateLimit-Reset": String(Int(reset)),
            ]
        ))
        let status = await updater.check(current: AppVersion("0.1.0")!)
        if case .failed(let message) = status {
            await check.expect(message.contains("한도"), "403 은 조회 한도로 안내한다")
            await check.expect(message.contains("23분"), "언제 풀리는지 알려준다 (실제: \(message))")
        } else {
            await check.expect(false, "403 은 .failed 여야 한다 (실제 \(status))")
        }
    }

    do {
        // 403 이지만 한도 문제가 아닌 경우. 한도 문구를 잘못 붙이면 사용자가 헛되게 기다린다.
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: ["X-RateLimit-Remaining": "42"]
        )!
        await check.expect(
            UpdateChecker.rateLimitMessage(response) == nil,
            "남은 한도가 있으면 한도 문제로 안내하지 않는다"
        )
    }

    do {
        // reset 시각이 이미 지났으면 "약 -3분 후" 같은 값이 나가면 안 된다.
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: [
                "X-RateLimit-Remaining": "0",
                "X-RateLimit-Reset": String(Int(Date().addingTimeInterval(-300).timeIntervalSince1970)),
            ]
        )!
        let message = UpdateChecker.rateLimitMessage(response)
        await check.expect(message != nil, "한도 초과는 여전히 안내한다")
        await check.expect(
            !(message?.contains("-") ?? false),
            "지난 시각이면 음수를 표시하지 않는다 (실제: \(message ?? "nil"))"
        )
    }

    do {
        // 태그가 semver 가 아니면 비교할 수 없다. 조용히 넘기지 말고 알려야 한다.
        let body = #"{"tag_name":"nightly","html_url":"https://example.com"}"#
        let (updater, _) = checker(.init(body: body))
        let status = await updater.check(current: AppVersion("0.1.0")!)
        if case .failed(let message) = status {
            await check.expect(message.contains("태그"), "해석할 수 없는 태그를 알린다")
        } else {
            await check.expect(false, "잘못된 태그는 .failed 여야 한다 (실제 \(status))")
        }
    }

    do {
        let (updater, _) = checker(.init(body: "엉뚱한 응답"))
        let status = await updater.check(current: AppVersion("0.1.0")!)
        if case .failed = status {
            await check.expect(true, "JSON 이 아니면 실패로 처리한다")
        } else {
            await check.expect(false, "잘못된 JSON 은 .failed 여야 한다 (실제 \(status))")
        }
    }

    do {
        // 설치 명령이 install.sh 의 실제 위치를 가리켜야 한다.
        let updater = UpdateChecker(
            repository: "nowjiin/TossAsset-MenuBar",
            transport: StubTransport(stubs: [:])
        )
        await check.expect(
            updater.installCommand.contains("/main/Scripts/install.sh"),
            "설치 명령이 Scripts/install.sh 를 가리킨다"
        )
        await check.expect(
            updater.installCommand.hasPrefix("curl -fsSL"),
            "README 와 같은 curl 명령 형태"
        )
    }
}
