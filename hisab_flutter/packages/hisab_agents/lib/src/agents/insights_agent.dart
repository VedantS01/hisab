/// The insights agent: a month of the ledger, read through [LedgerTools],
/// told as at most three cards.
///
/// The model narrates; Dart decides. A card must quote a number, and every
/// rupee amount and percentage in it must be one a tool said about the thing
/// the card names ([LedgerTools.grounded]) — a card that works out its own
/// sum, or pins the month's total on its rent, is dropped. Categories and
/// merchants it names are kept only when the ledger has them.
library;

import 'package:hisab_core/hisab_core.dart';

import '../runtime.dart';
import 'ledger_tools.dart';

class AgentInsight {
  final String title;
  final String body;

  /// One of [InsightsAgent.kinds].
  final String kind;
  final String? category;
  final String? merchant;

  const AgentInsight({
    required this.title,
    required this.body,
    required this.kind,
    this.category,
    this.merchant,
  });

  Map<String, Object?> toJson() => {
        'title': title,
        'body': body,
        'kind': kind,
        if (category != null) 'category': category,
        if (merchant != null) 'merchant': merchant,
      };

  factory AgentInsight.fromJson(Map<String, Object?> json) => AgentInsight(
        title: json['title'] as String,
        body: json['body'] as String,
        kind: json['kind'] as String,
        category: json['category'] as String?,
        merchant: json['merchant'] as String?,
      );

  @override
  String toString() => 'AgentInsight($kind "$title" — $body)';
}

class InsightsAgent {
  final ModelRuntime runtime;
  const InsightsAgent(this.runtime);

  static const kinds = ['spending', 'change', 'recurring', 'merchant', 'saving'];

  static const instructions = 'You help a person in India understand their spending. Look at '
      'their ledger with the tools, then write at most three insights they would act on: a '
      'category that grew or shrank, a lot of money going to one merchant, a subscription or '
      'EMI, money saved. Every insight quotes an amount or a percentage exactly as a tool gave '
      'it; never add, subtract or round numbers yourself. Leave out what stayed the same. A '
      'title is at most six words. A body is one sentence. Rent, EMIs and salary are expected: '
      'mention them only when they changed.';

  static final schema = Schema.object('Insights', {
    'insights': Schema.array(Schema.ref('Insight'), max: 3),
  }, defs: {
    'Insight': Schema.object('Insight', {
      'title': Schema.string(description: 'At most six words'),
      'body': Schema.string(description: 'One sentence quoting the numbers the tools gave'),
      'kind': Schema.string(oneOf: kinds),
      'category': Schema.string(description: 'The category it is about, empty if none'),
      'merchant': Schema.string(description: 'The merchant it is about, empty if none'),
    }),
  });

  /// Insights about [month] from the ledger behind [tools]. Throws
  /// ModelFailure.
  Future<List<AgentInsight>> run({required LedgerTools tools, required YearMonth month}) async {
    final reply = await runtime.respond(ModelRequest(
      instructions: instructions,
      prompt: 'Write insights about ${month.displayName}. Ask the tools about month $month '
          'first: compareMonths, spendingByCategory and recurring.',
      schema: schema,
      tools: tools.tools,
      reasoning: Reasoning.moderate,
    ));
    final kept = <AgentInsight>[];
    for (final raw in reply.json['insights'] as List? ?? const []) {
      final insight = validate(Map<String, Object?>.from(raw as Map), tools);
      if (insight != null && !kept.any((k) => k.title == insight.title)) kept.add(insight);
    }
    return kept;
  }

  /// The model's card held to what the tools said, or null.
  static AgentInsight? validate(Map<String, Object?> row, LedgerTools tools) {
    String field(String key) => (row[key] as String? ?? '').trim();
    final title = field('title'), body = field('body');
    if (title.isEmpty || body.isEmpty) return null;
    final text = '$title $body';
    final quotes = LedgerTools.rupeesIn(text).length + LedgerTools.percentsIn(text).length;
    if (quotes == 0 || !tools.grounded(text)) return null;

    String? known(String value, Iterable<String> names) {
      if (value.isEmpty) return null;
      for (final name in names) {
        if (name.toLowerCase() == value.toLowerCase()) return name;
      }
      return null;
    }

    return AgentInsight(
      title: title,
      body: body,
      kind: kinds.contains(field('kind')) ? field('kind') : 'spending',
      category: known(field('category'), {for (final r in tools.records) r.category}),
      merchant: known(field('merchant'), {for (final r in tools.records) r.merchant}),
    );
  }
}
