/// The transaction detection agent: money movements in any text the user
/// has — a bank SMS or email, a pasted history, a statement no parser reads.
///
/// The model only transcribes; Dart decides. Every value it returns must be
/// in the text (an amount, a reference, a name it made up is dropped), and
/// a find without a bank reference is a Detection for the user to complete,
/// never a ledger row on the model's word.
library;

import 'package:hisab_core/hisab_core.dart';

import '../runtime.dart';

class Detection {
  final DateTime date;
  final int amountPaise;
  final Direction direction;

  /// Who was paid, or who paid; empty when the text doesn't say.
  final String counterparty;
  final String? vpa;

  /// The bank's or UPI's reference, exactly as printed — what makes a
  /// detection a transaction.
  final String? reference;

  /// Last digits of the user's own account or card.
  final String? accountTail;

  /// Whether [date] was written in the text, rather than the day it arrived.
  final bool dated;

  const Detection({
    required this.date,
    required this.amountPaise,
    required this.direction,
    required this.counterparty,
    this.vpa,
    this.reference,
    this.accountTail,
    this.dated = true,
  });

  bool get complete => reference != null;

  @override
  String toString() =>
      'Detection(${istDayString(date)} $amountPaise ${direction.name} '
      '"$counterparty" vpa=$vpa ref=$reference tail=$accountTail)';
}

class DetectionAgent {
  final ModelRuntime runtime;
  const DetectionAgent(this.runtime);

  static const instructions = 'You find money movements in text a person in India received or '
      'saved: bank and UPI SMS, emails, notes, statement pages. List every completed payment, '
      'debit, credit, refund or transfer once, and give every other mention of money — a balance, '
      'an OTP, an offer, a payment request, a bill that is only due, a failed or declined '
      'transaction, a mandate or AutoPay set up but not yet charged — the status that says what '
      'it is. Copy amounts, '
      'names, UPI IDs and reference numbers exactly as written and never invent one: leave a '
      'field empty when the text does not say it.';

  /// Characters per request: the on-device model reads 4K tokens with the
  /// instructions, schema and reply; the cloud model 32K.
  static const onDeviceChunk = 2400;
  static const cloudChunk = 20000;

  /// What a mention of money can be; only [_completed] ones are kept. Naming
  /// the others gives the model somewhere to put a balance or an OTP other
  /// than the transaction list.
  static const statuses = [
    'completed', 'failed', 'pending', 'requested', 'due', 'otp', 'balanceOnly', 'offer', 'mandate',
  ];
  static const _completed = 'completed';

  static final schema = Schema.object('Detections', {
    'transactions': Schema.array(Schema.ref('Txn'), max: 40),
  }, defs: {
    'Txn': Schema.object('Txn', {
      'status': Schema.string(
          description: 'completed when money actually moved; otherwise what the mention is',
          oneOf: statuses),
      'date': Schema.string(
          description: 'The date exactly as written, like 22-09-26 or 1 Nov 2026; empty if none'),
      'amount': Schema.string(description: 'Amount in rupees as written, like 1,23,456.78'),
      'direction': Schema.string(
          description: 'debit when money left the account, credit when it came in',
          oneOf: ['debit', 'credit']),
      'counterparty': Schema.string(
          description: 'Who was paid or who paid, as written; empty if not named'),
      'vpa': Schema.string(description: 'UPI ID like name@bank, empty if none'),
      'reference': Schema.string(
          description: 'Reference, UTR or transaction number as written, empty if none'),
      'accountTail': Schema.string(
          description: "Last digits of the person's own account or card, empty if none"),
    }),
  });

  /// Detections in [text], which arrived at [receivedAt]. Throws ModelFailure.
  Future<List<Detection>> detect(String text, {required DateTime receivedAt}) async {
    final status = await runtime.status();
    final pieces = status.cloudReady ? chunks(text, cloudChunk) : blocks(text, onDeviceChunk);
    final found = <Detection>[];
    for (final chunk in pieces) {
      for (final row in await _rows(chunk, receivedAt)) {
        if (row['status'] != _completed) continue;
        final detection = validate(row, chunk, receivedAt);
        if (detection != null && !found.any((d) => _same(d, detection))) found.add(detection);
      }
    }
    return found;
  }

  /// The model's rows for one chunk. Guided generation keeps the default
  /// guardrails, which refuse some alerts' names and handles; plain text
  /// gets the permissive ones, so a refusal is asked again as text lines.
  Future<List<Map<String, Object?>>> _rows(String chunk, DateTime receivedAt) async {
    // No arrival date here: given one, the small model copies it in place of
    // the date written in the text. Dart falls back to it instead.
    final prompt = chunk;
    try {
      final reply = await runtime.respond(ModelRequest(
        instructions: instructions,
        prompt: prompt,
        schema: schema,
        greedy: true,
        transform: true,
      ));
      return [
        for (final raw in reply.json['transactions'] as List? ?? const [])
          Map<String, Object?>.from(raw as Map)
      ];
    } on ModelFailure catch (e) {
      if (e.code != 'refused') rethrow;
    }
    final reply = await runtime.respond(ModelRequest(
      instructions: instructions,
      prompt: '$prompt\n\n$textFormat',
      greedy: true,
      transform: true,
    ));
    return parseLines(reply.content);
  }

  static const _fields = [
    'status', 'date', 'amount', 'direction', 'counterparty', 'vpa', 'reference', 'accountTail',
  ];

  /// The same rows as text, for [parseLines].
  static final textFormat = 'Answer with one line per mention of money, fields separated by " | " '
      'in this order: ${_fields.join(' | ')}. status is one of ${statuses.join(', ')}; date as '
      'written; direction is debit or credit; write - for an empty field. Write only the lines, '
      'or the word none.';

  /// Rows from [textFormat] lines; a line with the wrong number of fields is
  /// skipped.
  static List<Map<String, Object?>> parseLines(String reply) => [
        for (final line in reply.split('\n'))
          if (line.split('|').length == _fields.length)
            {
              for (final (i, value) in line.split('|').indexed)
                _fields[i]: value.trim() == '-' ? '' : value.trim(),
            }
      ];

  /// For the on-device model: a pasted history — blocks separated by blank
  /// lines, each naming an amount — one block per request, since the small
  /// model loses items and dates across several; anything else as [chunks].
  static List<String> blocks(String text, int size) {
    final paragraphs = [
      for (final p in text.split(RegExp(r'\n\s*\n')))
        if (p.trim().isNotEmpty) p.trim()
    ];
    final withAmounts = paragraphs.where((p) => RegExp(r'\d').hasMatch(p)).length;
    if (paragraphs.length < 2 || withAmounts < 2) return chunks(text, size);
    return [for (final p in paragraphs) ...chunks(p, size)];
  }

  /// Text cut at line breaks into pieces of at most [size] characters (a
  /// longer line is cut where it must).
  static List<String> chunks(String text, int size) {
    final pieces = <String>[];
    final current = StringBuffer();
    for (var line in text.split('\n')) {
      while (line.length > size) {
        if (current.isNotEmpty) pieces.add(current.toString());
        current.clear();
        pieces.add(line.substring(0, size));
        line = line.substring(size);
      }
      if (current.length + line.length + 1 > size && current.isNotEmpty) {
        pieces.add(current.toString());
        current.clear();
      }
      if (current.isNotEmpty) current.write('\n');
      current.write(line);
    }
    if (current.toString().trim().isNotEmpty) pieces.add(current.toString());
    return pieces;
  }

  /// The model's row held to the text: null unless the amount is in it; a
  /// reference, UPI ID or name not in it is dropped.
  static Detection? validate(Map<String, Object?> row, String text, DateTime receivedAt) {
    String field(String key) => (row[key] as String? ?? '').trim();
    final haystack = text.toLowerCase();
    bool inText(String value) => value.isNotEmpty && haystack.contains(value.toLowerCase());
    String? kept(String value) => inText(value) ? value : null;

    final amountText = field('amount').replaceAll(RegExp(r'^(rs\.?|inr|₹)\s*', caseSensitive: false), '');
    final amount = Money.signedPaise(amountText);
    if (amount == null || amount <= 0 || !_amountInText(amount, text)) return null;
    final direction = switch (field('direction')) {
      'debit' => Direction.debit,
      'credit' => Direction.credit,
      _ => null,
    };
    if (direction == null) return null;

    // A date not in the text is made up; one the model left out but the text
    // plainly gives ("20Sep26") is read here.
    final written = writtenDate(kept(field('date')) ?? '') ?? AlertParser.dateIn(text);
    // A date more than a day after the message arrived is a misreading.
    final dated = written != null && !written.isAfter(receivedAt.add(const Duration(days: 1)));
    // The number itself, without a label the model copied along with it
    // ("UPI transaction ID: 630512398765").
    final reference = RegExp(r'[A-Za-z0-9]*\d{6,}[A-Za-z0-9]*')
        .firstMatch(kept(field('reference')) ?? '')
        ?.group(0);
    final tail = field('accountTail').replaceAll(RegExp(r'\D'), '');
    return Detection(
      date: dated ? written : receivedAt,
      dated: dated,
      amountPaise: amount,
      direction: direction,
      counterparty: kept(field('counterparty')) ?? '',
      vpa: field('vpa').contains('@') ? kept(field('vpa')) : null,
      reference: reference,
      accountTail: tail.length >= 3 && tail.length <= 6 && text.contains(tail) ? tail : null,
    );
  }

  /// A date as the text writes it — "22-09-26", "1 Nov 2026, 8:14 pm",
  /// "29/10/2026", "20Sep26" — or null.
  static DateTime? writtenDate(String written) {
    final text = written.split(',').first.trim();
    if (text.isEmpty) return null;
    for (final format in ColumnInference.candidateDateFormats) {
      final date = StatementDate.tryParse(text, format);
      if (date != null) return date;
    }
    return AlertParser.dateIn(text);
  }

  /// Whether some amount written in [text] is [paise] — "1,23,456.78",
  /// "123456.78", "₹2,000", "Rs 99".
  static bool _amountInText(int paise, String text) {
    for (final m in RegExp(r'\d[\d,]*(?:\.\d{1,2})?').allMatches(text)) {
      if (Money.signedPaise(m.group(0)!) == paise) return true;
    }
    return false;
  }

  static bool _same(Detection a, Detection b) =>
      a.amountPaise == b.amountPaise &&
      a.direction == b.direction &&
      istDayString(a.date) == istDayString(b.date) &&
      a.reference == b.reference;
}
