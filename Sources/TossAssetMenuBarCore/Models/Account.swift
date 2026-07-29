import Foundation

/// `GET /api/v1/accounts` 의 항목.
/// `accountSeq` 를 계좌·자산·주문 계열 API 의 `X-Tossinvest-Account` 헤더에 넣는다.
public struct Account: Decodable, Sendable, Identifiable, Hashable {
    public let accountNo: String
    public let accountSeq: Int64
    public let accountType: AccountType

    public var id: Int64 { accountSeq }

    public init(accountNo: String, accountSeq: Int64, accountType: AccountType) {
        self.accountNo = accountNo
        self.accountSeq = accountSeq
        self.accountType = accountType
    }

    /// 계좌번호 전체를 화면에 노출할 이유가 없으므로 뒤 4자리만 보여준다.
    public var maskedAccountNo: String {
        guard accountNo.count > 4 else { return accountNo }
        return "•••• " + String(accountNo.suffix(4))
    }
}
