/// The Android runtime for the on-device alert extractor: ONNX Runtime, CPU
/// only, over the bundled assets/extractor/extractor.int8.onnx. The model,
/// its inputs and its outputs never leave the process — zero network.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:hisab_core/hisab_core.dart';

class OnnxExtractorModel implements ExtractorModel {
  static const modelAsset = 'assets/extractor/extractor.int8.onnx';

  final OrtSession _session;
  OnnxExtractorModel._(this._session);

  static Future<OnnxExtractorModel> load() async {
    final session = await OnnxRuntime().createSessionFromAsset(
      modelAsset,
      options:
          OrtSessionOptions(intraOpNumThreads: 2, providers: [OrtProvider.CPU]),
    );
    return OnnxExtractorModel._(session);
  }

  /// One sequence, batch of 1: int64 `input_ids` / `attention_mask` [1, n]
  /// in; float32 `tag_logits` [1, n, tags] and `seq_logits` [1, classes] out.
  @override
  Future<ExtractorLogits> logits(
      List<int> inputIds, List<int> attentionMask) async {
    final n = inputIds.length;
    final ids = await OrtValue.fromList(Int64List.fromList(inputIds), [1, n]);
    final mask =
        await OrtValue.fromList(Int64List.fromList(attentionMask), [1, n]);
    try {
      final outputs =
          await _session.run({'input_ids': ids, 'attention_mask': mask});
      try {
        final tags = await outputs['tag_logits']!.asFlattenedList();
        final seq = await outputs['seq_logits']!.asFlattenedList();
        final width = tags.length ~/ n;
        return ExtractorLogits(
          [
            for (var t = 0; t < n; t++)
              [
                for (var k = 0; k < width; k++)
                  (tags[t * width + k] as num).toDouble()
              ]
          ],
          [for (final v in seq) (v as num).toDouble()],
        );
      } finally {
        for (final value in outputs.values) {
          await value.dispose();
        }
      }
    } finally {
      await ids.dispose();
      await mask.dispose();
    }
  }

  Future<void> close() => _session.close();
}

/// The extractor over the bundled assets. Not cached by the bundle: the
/// parsed vocabulary lives in the extractor, the strings are not needed again.
Future<AlertExtractor> loadAlertExtractor() async {
  Future<String> asset(String name) =>
      rootBundle.loadString('assets/extractor/$name', cache: false);
  return AlertExtractor.fromStrings(
    vocab: await asset('vocab.txt'),
    chartable: await asset('chartable.json'),
    config: await asset('extractor.json'),
    model: await OnnxExtractorModel.load(),
  );
}
