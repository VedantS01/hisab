/// Alert text -> [ExtractedAlert] through the on-device model: prepare,
/// tokenize, run, decode. Platform-free; the app supplies the model runtime.
library;

import 'extracted_alert.dart';
import 'extractor_decode.dart';
import 'extractor_tokenizer.dart';

class AlertExtractor {
  final ExtractorTokenizer tokenizer;
  final ExtractorDecode decoder;
  final ExtractorModel model;

  const AlertExtractor(this.tokenizer, this.decoder, this.model);

  /// From the bundled asset strings (assets/extractor/vocab.txt,
  /// chartable.json, extractor.json) and a model runtime.
  factory AlertExtractor.fromStrings({
    required String vocab,
    required String chartable,
    required String config,
    required ExtractorModel model,
  }) =>
      AlertExtractor(
        ExtractorTokenizer.fromStrings(
            vocab: vocab, chartable: chartable, config: config),
        ExtractorDecode.fromJsonString(config),
        model,
      );

  Future<ExtractedAlert> extract(String text) async {
    final encoding = tokenizer.encode(tokenizer.prepare(text));
    final out =
        await model.logits(encoding.ids, List.filled(encoding.ids.length, 1));
    // A runtime fault can come back as NaN rather than a crash (iOS 27's
    // float16 Core ML path did), and NaN decodes to class 0, "none": the
    // alert would be dropped as not a transaction. Throwing sends it to the
    // caller's parser fallback instead. Mirrors `AlertExtractor.swift`.
    if (out.seq.any((v) => !v.isFinite) ||
        out.tags.any((row) => row.any((v) => !v.isFinite))) {
      throw StateError('extractor returned non-finite logits');
    }
    return decoder.decode(text, encoding.offsets, out.tags, out.seq);
  }
}
