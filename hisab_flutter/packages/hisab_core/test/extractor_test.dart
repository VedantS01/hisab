// Parity with the Python reference extractor (ml/src/hisab_ml). The fixtures
// are written by ml/src/hisab_ml/fixtures.py into HisabCore's test fixtures
// and copied here by tool/sync_assets.sh; the Swift port pins the same files.
import 'dart:convert';
import 'dart:io';

import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

String _asset(String name) =>
    File('../../assets/extractor/$name').readAsStringSync();

/// Fails with the mismatch count and the first few mismatches.
void _expectNone(List<String> mismatches, int total) {
  expect(mismatches.length, 0,
      reason: '${mismatches.length}/$total mismatched; first:\n'
          '${mismatches.take(5).join('\n')}');
}

String _short(String text) =>
    text.length > 70 ? '${text.substring(0, 70)}...' : text;

/// The reference's `_fields` shape: is_txn plus every non-null field.
Map<String, Object?> _fields(ExtractedAlert a) => {
      'is_txn': a.isTransaction,
      if (a.direction != null) 'direction': a.direction!.name,
      if (a.amountPaise != null) 'amount_paise': a.amountPaise,
      if (a.ref != null) 'ref': a.ref,
      if (a.payee != null) 'payee': a.payee,
      if (a.vpa != null) 'vpa': a.vpa,
      if (a.ownAccountTail != null) 'own_acct_tail': a.ownAccountTail,
      if (a.counterpartyAccountTail != null)
        'cpty_acct_tail': a.counterpartyAccountTail,
      if (a.dateIso != null) 'date_iso': a.dateIso,
      if (a.balancePaise != null) 'balance_paise': a.balancePaise,
    };

bool _sameFields(Map<String, Object?> a, Map<String, dynamic> b) =>
    a.length == b.length &&
    a.keys.every((k) => b.containsKey(k) && a[k] == b[k]);

List<(int, int)> _offsets(List offsets) => [
      for (final o in offsets) ((o as List)[0] as int, o[1] as int),
    ];

bool _same<T>(List<T> a, List<T> b) =>
    a.length == b.length &&
    Iterable.generate(a.length).every((i) => a[i] == b[i]);

List<double> _doubles(List row) => [for (final v in row) (v as num).toDouble()];

class _FixedModel implements ExtractorModel {
  final ExtractorLogits out;
  List<int>? ids, mask;
  _FixedModel(this.out);

  @override
  Future<ExtractorLogits> logits(
      List<int> inputIds, List<int> attentionMask) async {
    ids = inputIds;
    mask = attentionMask;
    return out;
  }
}

void main() {
  final tokenizer = ExtractorTokenizer.fromStrings(
    vocab: _asset('vocab.txt'),
    chartable: _asset('chartable.json'),
    config: _asset('extractor.json'),
  );

  group('ExtractorTokenizer', () {
    final fixture = _fixture('extractor-tokenizer.json');
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

    test('max_len matches the shipped extractor.json', () {
      expect(tokenizer.maxLen, fixture['max_len']);
    });

    test('ids and offsets equal the reference on all ${cases.length} cases',
        () {
      final bad = <String>[];
      for (final c in cases) {
        final text = c['text'] as String;
        final enc = tokenizer.encode(tokenizer.prepare(text));
        final ids = (c['ids'] as List).cast<int>();
        final offsets = _offsets(c['offsets'] as List);
        var i = 0;
        while (i < ids.length &&
            i < enc.ids.length &&
            ids[i] == enc.ids[i] &&
            offsets[i] == enc.offsets[i]) {
          i++;
        }
        if (i < ids.length || i < enc.ids.length) {
          bad.add('${jsonEncode(_short(text))}: token $i — expected '
              '${i < ids.length ? '${ids[i]} ${offsets[i]}' : 'end'}, got '
              '${i < enc.ids.length ? '${enc.ids[i]} ${enc.offsets[i]}' : 'end'}');
        }
      }
      _expectNone(bad, cases.length);
    });

    test('prepare keeps length: rupee and bullet map to in-vocabulary marks',
        () {
      expect(tokenizer.prepare('₹450 •• 1234'), r'$450 ** 1234');
    });
  });

  group('ExtractorNormalize', () {
    final fixture = _fixture('extractor-normalize.json');

    void table(String key, Object? Function(String) fn) {
      final rows = (fixture[key] as List).cast<List>();
      test('$key matches the reference on all ${rows.length} inputs', () {
        final bad = <String>[
          for (final r in rows)
            if (fn(r[0] as String) != r[1])
              '${jsonEncode(r[0])}: expected ${jsonEncode(r[1])}, '
                  'got ${jsonEncode(fn(r[0] as String))}',
        ];
        _expectNone(bad, rows.length);
      });
    }

    table('amount_paise', ExtractorNormalize.amountPaise);
    table('ref', ExtractorNormalize.ref);
    table('acct_tail', ExtractorNormalize.acctTail);
    table('date_iso', ExtractorNormalize.dateIso);
    table('name', ExtractorNormalize.name);

    final edges = (fixture['clean_edges'] as List).cast<List>();
    test('clean_edges matches the reference on all ${edges.length} spans', () {
      final bad = <String>[
        for (final r in edges)
          if (ExtractorDecode.cleanEdges(
                  r[0] as String, r[1] as int, r[2] as int) !=
              r[3])
            '${jsonEncode(r[0])} [${r[1]}, ${r[2]}): expected ${r[3]}',
      ];
      _expectNone(bad, edges.length);
    });

    test('Python quirks are kept: a final newline before /- and 0 rupees', () {
      // `$` lets "450.5\n" through and int() then reads the slice "5\n" as 5.
      expect(ExtractorNormalize.amountPaise('450.5\n/-'), 45005);
      expect(ExtractorNormalize.amountPaise('99999999999999999999'), isNull);
      expect(ExtractorNormalize.amountPaise('0.00'), 0);
    });
  });

  group('ExtractorDecode', () {
    final fixture = _fixture('extractor-decode.json');
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
    final decoder = ExtractorDecode(
      tags: (fixture['tags'] as List).cast<String>(),
      seqClasses: (fixture['seq_classes'] as List).cast<String>(),
    );

    test('tags and classes match the shipped extractor.json', () {
      final shipped = ExtractorDecode.fromJsonString(_asset('extractor.json'));
      expect(shipped.tags, decoder.tags);
      expect(shipped.seqClasses, decoder.seqClasses);
    });

    test('fields equal the reference on all ${cases.length} cases', () {
      final bad = <String>[];
      for (final c in cases) {
        final got = decoder.decode(
          c['text'] as String,
          _offsets(c['offsets'] as List),
          [for (final row in c['tag_logits'] as List) _doubles(row as List)],
          _doubles(c['seq_logits'] as List),
        );
        final expected = c['expected'] as Map<String, dynamic>;
        if (!_sameFields(_fields(got), expected)) {
          bad.add('${jsonEncode(_short(c['text'] as String))}:\n'
              '  expected ${jsonEncode(expected)}\n'
              '  got      ${jsonEncode(_fields(got))}');
        }
      }
      _expectNone(bad, cases.length);
    });

    test('argmax keeps the first of equal probabilities', () {
      expect(
          decoder.spansFromTags([
            (0, 2)
          ], [
            [0.4, 0.4, 0.2, ...List.filled(14, 0.0)]
          ]).isEmpty,
          isTrue,
          reason: 'O (index 0) wins the tie with B-AMOUNT');
    });
  });

  group('AlertExtractor', () {
    // The reference's own tokenizer offsets for its real-model cases; the
    // hand-built cases at the end carry hand-written offsets and are skipped.
    final cases = (_fixture('extractor-decode.json')['cases'] as List)
        .cast<Map<String, dynamic>>()
        .where((c) => _same(
            tokenizer.encode(tokenizer.prepare(c['text'] as String)).offsets,
            _offsets(c['offsets'] as List)))
        .toList();

    test('runs prepare -> tokenize -> model -> decode end to end', () async {
      expect(cases.length, greaterThanOrEqualTo(40));
      final bad = <String>[];
      for (final c in cases) {
        final text = c['text'] as String;
        final model = _FixedModel(ExtractorLogits(
          [for (final row in c['tag_logits'] as List) _doubles(row as List)],
          _doubles(c['seq_logits'] as List),
        ));
        final extractor = AlertExtractor(tokenizer,
            ExtractorDecode.fromJsonString(_asset('extractor.json')), model);
        final got = await extractor.extract(text);
        expect(model.mask, everyElement(1));
        expect(model.ids!.length, (c['offsets'] as List).length);
        if (!_sameFields(_fields(got), c['expected'] as Map<String, dynamic>)) {
          bad.add(
              '${jsonEncode(_short(text))}: got ${jsonEncode(_fields(got))}');
        }
      }
      _expectNone(bad, cases.length);
    });

    test('fromStrings wires the asset strings', () async {
      final extractor = AlertExtractor.fromStrings(
        vocab: _asset('vocab.txt'),
        chartable: _asset('chartable.json'),
        config: _asset('extractor.json'),
        model: _FixedModel(const ExtractorLogits([], [4.0, -4.0, -4.0])),
      );
      final got = await extractor.extract('Your OTP is 123456');
      expect(got.isTransaction, isFalse);
      expect(got, ExtractedAlert.notTransaction(got.classConfidence));
    });
  });
}
