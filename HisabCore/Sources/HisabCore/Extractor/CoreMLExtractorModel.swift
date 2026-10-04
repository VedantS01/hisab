#if canImport(CoreML)
import CoreML
import Foundation

/// The bundled `Extractor.mlmodelc`: int8 weights, float16 compute, flexible
/// sequence length 2...192.
public final class CoreMLExtractorModel: ExtractorModel {
    private let model: MLModel

    /// CPU and Neural Engine only: an App Intent runs in the background, where
    /// GPU work is not allowed.
    public init() throws {
        guard let url = Bundle.module.url(forResource: "Extractor", withExtension: "mlmodelc",
                                          subdirectory: "Resources/extractor") else {
            throw ExtractorError.missingResource("Extractor.mlmodelc")
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        model = try MLModel(contentsOf: url, configuration: configuration)
    }

    public func logits(inputIDs: [Int32], attentionMask: [Int32]) throws -> (tags: [[Float]], seq: [Float]) {
        let n = inputIDs.count
        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLMultiArray(MLShapedArray(scalars: inputIDs, shape: [1, n])),
            "attention_mask": MLMultiArray(MLShapedArray(scalars: attentionMask, shape: [1, n])),
        ])
        let outputs = try model.prediction(from: inputs)
        guard let tagArray = outputs.featureValue(for: "tag_logits")?.multiArrayValue,
              let seqArray = outputs.featureValue(for: "seq_logits")?.multiArrayValue else {
            throw ExtractorError.badOutput("missing tag_logits / seq_logits")
        }
        // Float16 outputs, possibly with padded strides: converting through
        // MLShapedArray honours both and yields dense row-major Float.
        let tagLogits = MLShapedArray<Float>(converting: tagArray)
        let seqLogits = MLShapedArray<Float>(converting: seqArray)
        guard tagLogits.shape.count == 3, tagLogits.shape[0] == 1, tagLogits.shape[1] == n,
              seqLogits.scalarCount == seqLogits.shape.last else {
            throw ExtractorError.badOutput("tag_logits \(tagLogits.shape), seq_logits \(seqLogits.shape)")
        }
        let width = tagLogits.shape[2]
        let flat = tagLogits.scalars
        let tags = (0..<n).map { Array(flat[$0 * width..<($0 + 1) * width]) }
        return (tags, seqLogits.scalars)
    }
}
#endif
