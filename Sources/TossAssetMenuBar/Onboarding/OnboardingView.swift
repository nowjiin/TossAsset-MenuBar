import SwiftUI
import TossAssetMenuBarCore

/// 키가 등록되지 않았을 때 보여주는 화면.
///
/// 배포용이라 키를 앱에 넣어둘 수 없으므로, 사용자가 직접 발급해서 입력해야 한다.
/// 허용 IP 등록까지 안내하지 않으면 대부분 403 에서 막히므로 두 단계를 함께 보여준다.
@MainActor
struct OnboardingView: View {
    let state: AppState

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isVerifying = false
    @State private var error: TossAPIError?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("토스증권 Open API 연결")
                    .font(.headline)

                stepGuide

                VStack(alignment: .leading, spacing: 6) {
                    Text("client_id")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $clientID)
                        .textFieldStyle(.roundedBorder)

                    Text("client_secret")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                }

                Text("입력한 키는 이 Mac 의 Keychain 에만 저장됩니다. 외부로 전송되는 곳은 토스증권 API 뿐입니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error {
                    NoticeBanner(
                        message: error.userMessage,
                        tint: .red,
                        action: ipAction(for: error)
                    )
                }

                Button {
                    verify()
                } label: {
                    if isVerifying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("연결 확인 후 저장")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isVerifying || clientID.isEmpty || clientSecret.isEmpty)
            }
            .padding(14)
        }
    }

    private var stepGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            step(
                1,
                "토스증권 PC 웹에 로그인한 뒤 아래 경로로 이동합니다.",
                path: ["설정", "Open API"],
                detail: "client_id 와 client_secret 을 발급받습니다."
            )
            step(
                2,
                "같은 화면에서 허용 IP 를 등록합니다.",
                path: ["설정", "Open API", "허용 IP 관리"],
                detail: "등록하지 않으면 모든 호출이 403 으로 막힙니다."
            )
            // 등록할 IP 를 여기서 바로 확인하게 한다.
            // 아래쪽에 두면 2단계를 읽는 시점에 "내 IP가 뭔지" 알 방법이 없어서,
            // 키를 넣고 403 을 맞은 뒤에야 알게 된다 — 실패해야 알려주는 구조가 된다.
            ipRow
            step(3, "아래에 키를 입력하고 연결을 확인합니다.", path: nil, detail: nil)

            HStack(spacing: 10) {
                Link("토스증권 열기", destination: Self.wtsURL)
                Link("Open API 안내", destination: Self.openAPIHomeURL)
                Link("API 문서", destination: Self.docsURL)
            }
            .font(.caption)
            .padding(.top, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 메뉴 경로를 `설정 › Open API` 처럼 눈에 띄게 보여준다.
    /// 줄글에 섞어두면 어디를 눌러야 하는지 찾기 어렵다.
    private func step(_ number: Int, _ title: String, path: [String]?, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "\(number).circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let path {
                    HStack(spacing: 3) {
                        ForEach(Array(path.enumerated()), id: \.offset) { index, component in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.tertiary)
                            }
                            Text(component)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
    }

    /// 2단계 바로 아래 놓이는 IP 줄. 단계 텍스트와 들여쓰기를 맞춘다.
    ///
    /// 모를 때는 `확인` 버튼, 알면 값과 `복사` 버튼을 보여준다.
    private var ipRow: some View {
        HStack(spacing: 6) {
            // 단계 아이콘 폭만큼 비워 2단계 본문과 좌측을 맞춘다.
            Image(systemName: "1.circle")
                .font(.caption)
                .opacity(0)

            if let ip = state.publicIP {
                Text(ip)
                    .font(.callout.monospaced())
                Button("복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ip, forType: .string)
                }
                .controlSize(.small)
            } else {
                Text("현재 공용 IP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(state.isLookingUpIP ? "확인 중" : "확인") {
                    Task { await state.lookUpPublicIP() }
                }
                .controlSize(.small)
                .disabled(state.isLookingUpIP)
            }
            Spacer()
        }
    }

    private static let wtsURL = URL(string: "https://www.tossinvest.com")!
    private static let openAPIHomeURL = URL(string: "https://home.tossinvest.com/ko/open-api")!
    private static let docsURL = URL(string: "https://developers.tossinvest.com/docs")!

    private func ipAction(for error: TossAPIError) -> (title: String, run: () -> Void)? {
        guard case .ipNotAllowed = error else { return nil }
        return ("현재 IP 확인하기", { Task { await state.lookUpPublicIP() } })
    }

    private func verify() {
        isVerifying = true
        error = nil
        Task {
            error = await state.saveCredentials(clientID: clientID, clientSecret: clientSecret)
            if error == nil {
                // 저장에 성공하면 메모리에서도 즉시 지운다.
                clientID = ""
                clientSecret = ""
            }
            isVerifying = false
        }
    }
}
