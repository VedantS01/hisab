/// What the on-device extractor read out of one alert, and the model seam it
/// reads through. Port of the Python reference in ml/src/hisab_ml/predict.py.
library;

import '../domain.dart';

/// The decoded fields of one alert. A non-transaction carries only
/// [classConfidence]; every other field is null.
class ExtractedAlert {
  final bool isTransaction;
  final Direction? direction;
  final int? amountPaise;
  final String? ref;
  final String? payee;
  final String? vpa;
  final String? ownAccountTail;
  final String? counterpartyAccountTail;

  /// `yyyy-MM-dd`, or `--MM-dd` when the alert names no year.
  final String? dateIso;
  final int? balancePaise;

  /// Softmax probability of the winning sequence class, rounded to 4 places.
  final double classConfidence;

  const ExtractedAlert({
    required this.isTransaction,
    this.direction,
    this.amountPaise,
    this.ref,
    this.payee,
    this.vpa,
    this.ownAccountTail,
    this.counterpartyAccountTail,
    this.dateIso,
    this.balancePaise,
    required this.classConfidence,
  });

  const ExtractedAlert.notTransaction(this.classConfidence)
      : isTransaction = false,
        direction = null,
        amountPaise = null,
        ref = null,
        payee = null,
        vpa = null,
        ownAccountTail = null,
        counterpartyAccountTail = null,
        dateIso = null,
        balancePaise = null;

  @override
  bool operator ==(Object other) =>
      other is ExtractedAlert &&
      other.isTransaction == isTransaction &&
      other.direction == direction &&
      other.amountPaise == amountPaise &&
      other.ref == ref &&
      other.payee == payee &&
      other.vpa == vpa &&
      other.ownAccountTail == ownAccountTail &&
      other.counterpartyAccountTail == counterpartyAccountTail &&
      other.dateIso == dateIso &&
      other.balancePaise == balancePaise &&
      other.classConfidence == classConfidence;

  @override
  int get hashCode => Object.hash(
      isTransaction,
      direction,
      amountPaise,
      ref,
      payee,
      vpa,
      ownAccountTail,
      counterpartyAccountTail,
      dateIso,
      balancePaise,
      classConfidence);

  @override
  String toString() => 'ExtractedAlert(isTransaction: $isTransaction, '
      'direction: ${direction?.name}, amountPaise: $amountPaise, ref: $ref, '
      'payee: $payee, vpa: $vpa, ownAccountTail: $ownAccountTail, '
      'counterpartyAccountTail: $counterpartyAccountTail, dateIso: $dateIso, '
      'balancePaise: $balancePaise, classConfidence: $classConfidence)';
}

/// Raw model outputs for one sequence: [tags] is `[tokens][tag classes]`,
/// [seq] is `[sequence classes]`.
class ExtractorLogits {
  final List<List<double>> tags;
  final List<double> seq;
  const ExtractorLogits(this.tags, this.seq);
}

/// The model runtime: ONNX Runtime on Android. One sequence, batch of 1.
abstract class ExtractorModel {
  Future<ExtractorLogits> logits(List<int> inputIds, List<int> attentionMask);
}
