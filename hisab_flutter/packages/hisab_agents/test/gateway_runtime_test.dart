import 'dart:convert';

import 'package:hisab_agents/hisab_agents.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A gateway from a script of handlers, one per request in order.
class Script {
  final calls = <http.Request>[];
  final List<http.Response Function(http.Request)> handlers;
  Script(this.handlers);

  http.Client get client => MockClient((request) async {
        calls.add(request);
        if (handlers.isEmpty) throw StateError('unexpected ${request.method} ${request.url}');
        return handlers.removeAt(0)(request);
      });

  Map<String, Object?> body(int i) => jsonDecode(calls[i].body) as Map<String, Object?>;
}

http.Response ok(Object body, {Map<String, String> headers = const {}}) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json', ...headers});

http.Response registered() => http.Response(
    jsonEncode({'token': 'tok-1', 'credits': 300, 'dailyCap': 60, 'model': 'deepseek-chat'}), 201);

http.Response error(int status, String code, String message) =>
    http.Response(jsonEncode({'error': {'code': code, 'message': message}}), status);

Map<String, Object?> reply(String content, {List<Map<String, Object?>>? toolCalls, String finish = 'stop'}) => {
      'choices': [
        {
          'finish_reason': finish,
          'message': {'role': 'assistant', 'content': content, if (toolCalls != null) 'tool_calls': toolCalls},
        }
      ]
    };

GatewayRuntime runtime(Script script, {GatewayTokenStore? tokens}) => GatewayRuntime(
      base: Uri.parse('https://gw.test/v1/hisab'),
      appKey: 'app-key',
      tokens: tokens ?? MemoryTokenStore(),
      client: script.client,
    );

void main() {
  test('registers once with the app key, then reads the balance', () async {
    final tokens = MemoryTokenStore();
    final script = Script([
      (_) => registered(),
      (_) => ok({'credits': 299, 'granted': 300, 'spent': 1, 'dailyCap': 60, 'dailyUsed': 1, 'model': 'deepseek-chat'}),
    ]);
    final gateway = runtime(script, tokens: tokens);
    final account = await gateway.account(refresh: true);
    expect(script.calls[0].url.path, '/v1/hisab/register');
    expect(script.calls[0].headers['X-App-Key'], 'app-key');
    expect(script.calls[1].headers['Authorization'], 'Bearer tok-1');
    expect(tokens.token, 'tok-1');
    expect(account.credits, 299);
    expect(account.dailyRemaining, 59);
    expect((await gateway.status()).cloudReady, isTrue);
  });

  test('status is quota when the balance is spent, unavailable offline', () async {
    final spent = runtime(Script([
      (_) => ok({'credits': 0, 'granted': 300, 'spent': 300, 'dailyCap': 60, 'dailyUsed': 3, 'model': 'm'}),
    ]), tokens: MemoryTokenStore('tok'));
    final status = await spent.status();
    expect(status.cloud, 'quota');
    expect(status.quota, 'reached');

    final offline = GatewayRuntime(
      base: Uri.parse('https://gw.test/v1/hisab'),
      appKey: 'k',
      tokens: MemoryTokenStore('tok'),
      client: MockClient((_) async => throw http.ClientException('no route to host')),
    );
    expect((await offline.status()).cloud, 'unavailable');
  });

  test('a schema becomes JSON mode and the schema in the system prompt; the object is extracted',
      () async {
    final script = Script([
      (_) => ok(reply('Sure! ```json\n{"insights": []}\n```'), headers: {'x-credits-remaining': '298', 'x-daily-remaining': '58'}),
    ]);
    final gateway = runtime(script, tokens: MemoryTokenStore('tok'));
    final schema = Schema.object('Insights', {'insights': Schema.array(Schema.string())});
    final reply0 = await gateway.respond(ModelRequest(
      instructions: 'Be brief.',
      prompt: 'Go.',
      schema: schema,
      greedy: true,
    ));
    expect(reply0.content, '{"insights": []}');
    expect(reply0.json, {'insights': []});
    expect(reply0.model, 'cloud');
    final body = script.body(0);
    expect(body['response_format'], {'type': 'json_object'});
    expect(body['temperature'], 0);
    expect(body['tools'], isNull);
    final messages = body['messages'] as List;
    expect((messages[0] as Map)['content'], contains(jsonEncode(schema)));
    expect((messages[1] as Map)['content'], 'Go.');
  });

  test('tools run here and their results go back until the model answers', () async {
    final seen = <Map<String, Object?>>[];
    final tool = AgentTool(
      name: 'spendingByCategory',
      description: 'totals',
      parameters: Schema.object('Args', {'month': Schema.string()}),
      run: (args) async {
        seen.add(args);
        return 'Food 1200';
      },
    );
    final script = Script([
      (_) => ok(reply('', toolCalls: [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'spendingByCategory', 'arguments': '{"month":"2026-10"}'}
            },
            {
              'id': 'call_2',
              'type': 'function',
              'function': {'name': 'nothing', 'arguments': ''}
            },
          ])),
      (_) => ok(reply('{"insights":[{"title":"Food 1200"}]}')),
    ]);
    final gateway = runtime(script, tokens: MemoryTokenStore('tok'));
    final reply0 = await gateway.respond(ModelRequest(
      instructions: 'i',
      prompt: 'p',
      schema: Schema.object('Insights', {'insights': Schema.array(Schema.string())}),
      tools: [tool],
    ));
    expect(seen, [{'month': '2026-10'}]);
    expect(reply0.json['insights'], hasLength(1));
    final first = script.body(0);
    expect((first['tools'] as List).length, 1);
    expect(first['response_format'], isNull, reason: 'JSON mode and tools do not mix');
    final second = script.body(1)['messages'] as List;
    expect(second.length, 5);
    expect((second[2] as Map)['role'], 'assistant');
    expect((second[3] as Map), {'role': 'tool', 'tool_call_id': 'call_1', 'content': 'Food 1200'});
    expect((second[4] as Map)['content'], 'No tool named nothing.');
  });

  test('gateway errors map to quota, context and unavailable; a lost token re-registers', () async {
    Future<String> code(http.Response response) async {
      final gateway = runtime(Script([(_) => response]), tokens: MemoryTokenStore('tok'));
      try {
        await gateway.respond(const ModelRequest(instructions: 'i', prompt: 'p'));
        return 'ok';
      } on ModelFailure catch (e) {
        return e.code;
      }
    }

    expect(await code(error(402, 'credits', 'no credits left')), 'quota');
    expect(await code(error(429, 'daily', 'daily limit reached')), 'quota');
    expect(await code(error(503, 'upstream', 'no model answered')), 'unavailable');
    expect(await code(error(413, '', 'request too large')), 'context');
    expect(await code(ok(reply('half', finish: 'length'))), 'context');

    final tokens = MemoryTokenStore('stale');
    final script = Script([
      (_) => error(401, 'auth', 'unknown device'),
      (_) => registered(),
      (_) => ok(reply('hello')),
    ]);
    final reply0 = await runtime(script, tokens: tokens).respond(const ModelRequest(instructions: 'i', prompt: 'p'));
    expect(reply0.content, 'hello');
    expect(tokens.token, 'tok-1');
    expect(script.calls[2].headers['Authorization'], 'Bearer tok-1');
  });

  test('an on-device-only request is refused without a call', () async {
    final script = Script([]);
    expect(
      () => runtime(script, tokens: MemoryTokenStore('tok'))
          .respond(const ModelRequest(instructions: 'i', prompt: 'p', model: ModelChoice.onDevice)),
      throwsA(isA<ModelFailure>().having((e) => e.code, 'code', 'unavailable')),
    );
    expect(script.calls, isEmpty);
  });
}
