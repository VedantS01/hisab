import Foundation

/// On-device transaction-alert extractor: tokenizer -> model -> decode, a port
/// of `ml/src/hisab_ml` (`features.prepare`, `wordpiece.encode`,
/// `predict.decode`). Pure and synchronous, so an App Intent can run it in the
/// background.
public struct AlertExtractor {
    /// vocab.txt + chartable.json + extractor.json, read once per process.
    struct Resources: Sendable {
        let tokenizer: ExtractorTokenizer
        let maxLen: Int
        let tags: [String]
        let seqClasses: [String]

        private struct Meta: Decodable {
            var maxLen: Int
            var tags: [String]
            var seqClasses: [String]
            var charMap: [String: String]

            enum CodingKeys: String, CodingKey {
                case maxLen = "max_len", tags, seqClasses = "seq_classes", charMap = "char_map"
            }
        }

        static func load() throws -> Resources {
            func data(_ name: String, _ ext: String) throws -> Data {
                guard let url = Bundle.module.url(forResource: name, withExtension: ext,
                                                  subdirectory: "Resources/extractor") else {
                    throw ExtractorError.missingResource("\(name).\(ext)")
                }
                return try Data(contentsOf: url)
            }
            let meta = try JSONDecoder().decode(Meta.self, from: data("extractor", "json"))
            let tokenizer = ExtractorTokenizer(vocabTxt: try data("vocab", "txt"),
                                               table: try ExtractorTokenizer.Table(json: data("chartable", "json")),
                                               charMap: meta.charMap)
            return Resources(tokenizer: tokenizer, maxLen: meta.maxLen, tags: meta.tags,
                             seqClasses: meta.seqClasses)
        }

        static let bundled = Result { try load() }
    }

    let model: any ExtractorModel
    let resources: Resources

    public init(model: any ExtractorModel) throws {
        self.model = model
        self.resources = try Resources.bundled.get()
    }

    #if canImport(CoreML)
    /// The bundled Core ML model.
    public static func live() throws -> AlertExtractor {
        try AlertExtractor(model: CoreMLExtractorModel())
    }
    #endif

    public func extract(_ text: String) throws -> ExtractedAlert {
        let scalars = Array(text.unicodeScalars)
        let tokenizer = resources.tokenizer
        let encoding = tokenizer.encode(tokenizer.prepare(scalars), maxLen: resources.maxLen)
        let logits = try model.logits(inputIDs: encoding.ids,
                                      attentionMask: [Int32](repeating: 1, count: encoding.ids.count))
        return ExtractorDecode.decode(text: scalars, offsets: encoding.offsets,
                                      tagLogits: logits.tags.map { $0.map(Double.init) },
                                      seqLogits: logits.seq.map(Double.init),
                                      tags: resources.tags, seqClasses: resources.seqClasses)
    }
}
