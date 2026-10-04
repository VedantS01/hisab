/// Model outputs -> [ExtractedAlert]: BIO tags to character spans, the best
/// span per label, then the strict normalizers. Port of
/// ml/src/hisab_ml/predict.py (`decode` and its helpers).
///
/// Floating point follows numpy (float64, pairwise summation) so that ties
/// and near-ties break exactly as they do in the reference.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../domain.dart';
import 'extracted_alert.dart';
import 'extractor_normalize.dart';

/// A labelled span: `[start, end)` scalar indices and its mean token
/// probability.
typedef ExtractorSpan = (String label, int start, int end, double confidence);

class ExtractorDecode {
  /// BIO tag names by tag-logit index ("O", "B-AMOUNT", ...).
  final List<String> tags;

  /// Sequence classes by seq-logit index ("none", "debit", "credit").
  final List<String> seqClasses;

  const ExtractorDecode({required this.tags, required this.seqClasses});

  /// From extractor.json.
  factory ExtractorDecode.fromJsonString(String config) {
    final map = jsonDecode(config) as Map<String, dynamic>;
    return ExtractorDecode(
      tags: (map['tags'] as List).cast<String>(),
      seqClasses: (map['seq_classes'] as List).cast<String>(),
    );
  }

  /// One alert's fields. [text] is the alert as received (offsets index it
  /// in scalars; the tokenizer's character map preserves length).
  ExtractedAlert decode(String text, List<(int, int)> offsets,
      List<List<double>> tagLogits, List<double> seqLogits) {
    final seq = softmax(seqLogits);
    final k = _argmax(seq);
    final cls = seqClasses[k];
    final confidence = _round4(seq[k]);
    if (cls == 'none') return ExtractedAlert.notTransaction(confidence);

    final scalars = text.runes.toList();
    final best = <String, (int, int, double)>{};
    final probs = [for (final row in tagLogits) softmax(row)];
    for (final (label, s, e, p) in spansFromTags(offsets, probs)) {
      if (!_cleanEdges(scalars, s, e)) continue;
      final held = best[label];
      if (held == null || p > held.$3) best[label] = (s, e, p);
    }

    int? amount, balance;
    String? ref, payee, vpa, own, cpty, date;
    for (final MapEntry(key: label, value: (s, e, _)) in best.entries) {
      final span = String.fromCharCodes(scalars, s, e);
      switch (label) {
        case 'AMOUNT':
          amount = ExtractorNormalize.amountPaise(span);
        case 'BALANCE':
          balance = ExtractorNormalize.amountPaise(span);
        case 'REF':
          ref = ExtractorNormalize.ref(span);
        case 'OWN_ACCT':
          own = ExtractorNormalize.acctTail(span);
        case 'CPTY_ACCT':
          cpty = ExtractorNormalize.acctTail(span);
        case 'DATE':
          date = ExtractorNormalize.dateIso(span);
        case 'PAYEE':
          payee = _nonEmpty(ExtractorNormalize.trim(span));
        case 'VPA':
          vpa = _nonEmpty(
              ExtractorNormalize.lower(ExtractorNormalize.trim(span)));
      }
    }
    // Admission rule: a movement with no readable amount cannot be booked, so
    // it is not a transaction, whatever the class head says.
    if (amount == null || amount == 0) {
      return ExtractedAlert.notTransaction(confidence);
    }
    return ExtractedAlert(
      isTransaction: true,
      direction: Direction.values.byName(cls),
      amountPaise: amount,
      ref: ref,
      payee: payee,
      vpa: vpa,
      ownAccountTail: own,
      counterpartyAccountTail: cpty,
      dateIso: date,
      balancePaise: balance,
      classConfidence: confidence,
    );
  }

  /// Spans in order. An I- tag that does not continue a span of its own label
  /// opens a new one; special tokens (empty offsets) and O close the current.
  List<ExtractorSpan> spansFromTags(
      List<(int, int)> offsets, List<List<double>> tagProbs) {
    final out = <ExtractorSpan>[];
    String? label;
    var start = 0, end = 0;
    var ps = <double>[];

    void close() {
      if (label != null) out.add((label!, start, end, _mean(ps)));
      label = null;
    }

    for (var t = 0; t < math.min(offsets.length, tagProbs.length); t++) {
      final (s, e) = offsets[t];
      if (e <= s) {
        close();
        continue;
      }
      final probs = tagProbs[t];
      final k = _argmax(probs);
      final tag = tags[k];
      if (tag == 'O') {
        close();
        continue;
      }
      final dash = tag.indexOf('-');
      final prefix = tag.substring(0, dash), name = tag.substring(dash + 1);
      if (prefix == 'I' && label == name) {
        end = e;
        ps.add(probs[k]);
      } else {
        close();
        (label, start, end, ps) = (name, s, e, [probs[k]]);
      }
    }
    close();
    return out;
  }

  /// A value is a whole run of digits or letters, never a slice of one.
  /// Character classes are ASCII, as in the reference.
  static bool cleanEdges(String text, int start, int end) =>
      _cleanEdges(text.runes.toList(), start, end);

  static bool _cleanEdges(List<int> t, int start, int end) {
    final n = t.length;
    bool digit(int c) => c >= 0x30 && c <= 0x39;
    bool letter(int c) => (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);
    bool alnum(int c) => digit(c) || letter(c);
    bool separator(int c) => c == 0x2C || c == 0x2E; // , .

    bool splitsRun(int i) {
      if (i <= 0 || i >= n) return false;
      final a = t[i - 1], b = t[i];
      return (digit(a) && digit(b)) || (letter(a) && letter(b));
    }

    // 3,13,938.00 is one number: no edge next to a separator between digits.
    bool splitsNumber(int i) {
      if (2 <= i &&
          i < n &&
          separator(t[i - 1]) &&
          digit(t[i - 2]) &&
          digit(t[i])) {
        return true;
      }
      return 1 <= i &&
          i < n - 1 &&
          separator(t[i]) &&
          digit(t[i - 1]) &&
          digit(t[i + 1]);
    }

    // A value may START at a letter->digit edge (INR450) but may not END
    // inside a word: the 984 of a masked PAN "XXXXXX984D" is not an account.
    final endsInsideWord =
        0 < end && end < n && alnum(t[end - 1]) && alnum(t[end]);
    return !(splitsRun(start) ||
        splitsNumber(start) ||
        splitsNumber(end) ||
        endsInsideWord);
  }

  static List<double> softmax(List<double> x) {
    final m = x.reduce(math.max);
    final e = [for (final v in x) math.exp(v - m)];
    final sum = _pairwiseSum(e, 0, e.length);
    return [for (final v in e) v / sum];
  }

  /// numpy's argmax: the first maximum.
  static int _argmax(List<double> x) {
    var best = 0;
    for (var i = 1; i < x.length; i++) {
      if (x[i] > x[best]) best = i;
    }
    return best;
  }

  static double _mean(List<double> x) =>
      _pairwiseSum(x, 0, x.length) / x.length;

  /// numpy's float64 pairwise summation (`pairwise_sum_DOUBLE`), so sums and
  /// means are bit-identical to the reference's.
  static double _pairwiseSum(List<double> a, int lo, int n) {
    if (n < 8) {
      var res = 0.0;
      for (var i = 0; i < n; i++) {
        res += a[lo + i];
      }
      return res;
    }
    if (n <= 128) {
      final r = List<double>.generate(8, (j) => a[lo + j]);
      var i = 8;
      for (; i < n - n % 8; i += 8) {
        for (var j = 0; j < 8; j++) {
          r[j] += a[lo + i + j];
        }
      }
      var res =
          ((r[0] + r[1]) + (r[2] + r[3])) + ((r[4] + r[5]) + (r[6] + r[7]));
      for (; i < n; i++) {
        res += a[lo + i];
      }
      return res;
    }
    var n2 = n ~/ 2;
    n2 -= n2 % 8;
    return _pairwiseSum(a, lo, n2) + _pairwiseSum(a, lo + n2, n - n2);
  }

  /// Python's `round(x, 4)`. toStringAsFixed breaks an exact binary tie (an
  /// odd multiple of 1/32) away from zero; Python breaks it to even.
  static double _round4(double x) {
    final k = x * 32;
    if (k == k.truncateToDouble() && k.toInt().isOdd) {
      final n = (x * 10000).floor();
      return (n.isEven ? n : n + 1) / 10000;
    }
    return double.parse(x.toStringAsFixed(4));
  }

  static String? _nonEmpty(String s) => s.isEmpty ? null : s;
}
