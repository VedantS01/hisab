import Foundation

/// What the on-device extractor read from one transaction alert. Mirrors the
/// `fields` dict of `ml/src/hisab_ml/predict.py` `decode`: a field is `nil`
/// when the model tagged nothing for it or its span did not normalize.
public struct ExtractedAlert: Equatable, Sendable {
    /// False for anything that is not a booked money movement, including a
    /// "movement" with no readable amount (the admission rule).
    public var isTransaction: Bool
    public var direction: Direction?
    public var amountPaise: Int64?
    public var ref: String?
    public var payee: String?
    /// Lowercased.
    public var vpa: String?
    /// Last 3-4 digits.
    public var ownAccountTail: String?
    public var counterpartyAccountTail: String?
    /// `yyyy-MM-dd`, or `--MM-dd` when the alert names no year.
    public var dateISO: String?
    public var balancePaise: Int64?
    /// Probability of the predicted sequence class, rounded to 4 places.
    public var classConfidence: Float

    public init(isTransaction: Bool, direction: Direction? = nil, amountPaise: Int64? = nil,
                ref: String? = nil, payee: String? = nil, vpa: String? = nil,
                ownAccountTail: String? = nil, counterpartyAccountTail: String? = nil,
                dateISO: String? = nil, balancePaise: Int64? = nil, classConfidence: Float) {
        self.isTransaction = isTransaction
        self.direction = direction
        self.amountPaise = amountPaise
        self.ref = ref
        self.payee = payee
        self.vpa = vpa
        self.ownAccountTail = ownAccountTail
        self.counterpartyAccountTail = counterpartyAccountTail
        self.dateISO = dateISO
        self.balancePaise = balancePaise
        self.classConfidence = classConfidence
    }
}

/// The network: token ids in, raw logits out. `tags` is one row of tag
/// logits per input token; `seq` is the sequence-class logits.
public protocol ExtractorModel {
    func logits(inputIDs: [Int32], attentionMask: [Int32]) throws -> (tags: [[Float]], seq: [Float])
}

enum ExtractorError: Error {
    case missingResource(String)
    case badOutput(String)
}
