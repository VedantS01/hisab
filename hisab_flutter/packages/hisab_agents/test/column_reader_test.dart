import 'dart:convert';

import 'package:hisab_agents/hisab_agents.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

import 'fake_runtime.dart';

void main() {
  const header = ['Date', 'Narration', 'Withdrawal', 'Deposit', 'Balance'];
  const rows = [
    ['01/04/25', 'UPI-SHOP', '450.00', '', '9550.00'],
    ['02/04/25', 'SALARY', '', '1000.00', '10550.00'],
  ];

  test('the schema names each column and defines Kind with the title Apple resolves by', () {
    final schema = AppleColumnReader.schema(header, rows, 5);
    expect((schema['x-order'] as List), ['column0', 'column1', 'column2', 'column3', 'column4']);
    final defs = schema[r'$defs'] as Map;
    expect(defs['Kind'], containsPair('title', 'Kind'));
    expect((defs['Kind'] as Map)['enum'], ColumnRoles.labels);
    final column2 = (schema['properties'] as Map)['column2'] as Map;
    expect(column2[r'$ref'], r'#/$defs/Kind');
    expect(column2['description'], "Column 2, headed 'Withdrawal', values like '450.00'");
  });

  test('a guided reply becomes column roles', () async {
    final runtime = FakeRuntime([
      jsonEncode({
        'column0': 'date', 'column1': 'narration', 'column2': 'debit',
        'column3': 'credit', 'column4': 'balance',
      })
    ]);
    final roles = await AppleColumnReader(runtime).propose(header, rows);
    expect(roles, const ColumnRoles(date: 0, narration: 1, debit: 2, credit: 3, balance: 4));
    final request = runtime.requests.single;
    expect([request.model, request.greedy, request.transform], [ModelChoice.onDevice, true, true]);
  });

  test('a guardrail refusal is retried as text, which the permissive guardrails allow', () async {
    final runtime = FakeRuntime([
      const ModelFailure('refused', 'May contain sensitive content'),
      '0: date\n1: narration\n2: debit\n3: credit\n4: balance',
    ]);
    final roles = await AppleColumnReader(runtime).propose(header, rows);
    expect(roles, const ColumnRoles(date: 0, narration: 1, debit: 2, credit: 3, balance: 4));
    expect(runtime.requests.last.schema, isNull);
    expect(runtime.requests.last.prompt, contains('never the column'));
  });

  test('any other failure is the caller\'s to handle', () {
    final runtime = FakeRuntime([const ModelFailure('unavailable')]);
    expect(AppleColumnReader(runtime).propose(header, rows),
        throwsA(isA<ModelFailure>().having((e) => e.code, 'code', 'unavailable')));
  });

  test('a request serialises the way the Swift runtime decodes it', () {
    final tool = AgentTool(
      name: 'lookup',
      description: 'Looks up a payee.',
      parameters: Schema.object('Args', {'payee': Schema.string()}),
      run: (_) async => '',
    );
    final json = ModelRequest(
      instructions: 'i', prompt: 'p', tools: [tool], reasoning: Reasoning.light,
    ).toJson();
    expect(json, {
      'instructions': 'i',
      'prompt': 'p',
      'tools': [
        {
          'name': 'lookup',
          'description': 'Looks up a payee.',
          'parameters': {
            'type': 'object', 'title': 'Args', 'additionalProperties': false,
            'properties': {'payee': {'type': 'string'}},
            'required': ['payee'], 'x-order': ['payee'],
          },
        }
      ],
      'reasoning': 'light',
      'model': 'auto',
    });
  });
}
