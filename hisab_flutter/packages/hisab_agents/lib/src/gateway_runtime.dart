/// Cloud models through ai-gateway (github.com/VedantS01/ai-gateway), the
/// Worker that holds the provider keys and keeps each install's credits.
/// The gateway speaks OpenAI `chat.completions`; this runtime turns a
/// [ModelRequest] into that shape, runs the tool loop here (tools are Dart),
/// and holds the reply to the request's schema. One credit per call, so an
/// agent with tools spends a few per run.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'runtime.dart';

/// Where the app keeps the device's gateway token (secure storage on a
/// phone, memory in tests).
abstract interface class GatewayTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class MemoryTokenStore implements GatewayTokenStore {
  String? token;
  MemoryTokenStore([this.token]);

  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String token) async => this.token = token;
  @override
  Future<void> clear() async => token = null;
}

/// The device's balance as the gateway last reported it.
class GatewayAccount {
  final int credits;
  final int granted;
  final int spent;
  final int dailyCap;
  final int dailyUsed;
  final String model;

  const GatewayAccount({
    required this.credits,
    required this.granted,
    required this.spent,
    required this.dailyCap,
    required this.dailyUsed,
    required this.model,
  });

  factory GatewayAccount.fromJson(Map<String, Object?> json) => GatewayAccount(
        credits: json['credits'] as int? ?? 0,
        granted: json['granted'] as int? ?? 0,
        spent: json['spent'] as int? ?? 0,
        dailyCap: json['dailyCap'] as int? ?? 0,
        dailyUsed: json['dailyUsed'] as int? ?? 0,
        model: json['model'] as String? ?? '',
      );

  int get dailyRemaining => (dailyCap - dailyUsed).clamp(0, dailyCap);
  bool get canSpend => credits > 0 && dailyRemaining > 0;

  /// approaching | reached | null, in the words [ModelStatus.quota] uses.
  String? get quota => !canSpend
      ? 'reached'
      : credits <= 20 || dailyRemaining <= 5
          ? 'approaching'
          : null;

  GatewayAccount spent1({required int credits, required int dailyRemaining}) => GatewayAccount(
        credits: credits,
        granted: granted,
        spent: spent + 1,
        dailyCap: dailyCap,
        dailyUsed: dailyCap - dailyRemaining,
        model: model,
      );
}

class GatewayRuntime implements ModelRuntime {
  /// The project's base, like `https://ai-gateway.example.workers.dev/v1/hisab`.
  final Uri base;
  final String appKey;
  final GatewayTokenStore tokens;
  final http.Client client;
  final Duration timeout;
  final DateTime Function() clock;

  GatewayRuntime({
    required this.base,
    required this.appKey,
    required this.tokens,
    http.Client? client,
    this.timeout = const Duration(seconds: 90),
    DateTime Function()? clock,
  })  : client = client ?? http.Client(),
        clock = clock ?? DateTime.now;

  /// Rounds of tool calls before an agent is cut off.
  static const maxRounds = 8;

  /// How long a balance is believed before `/me` is asked again.
  static const accountTtl = Duration(seconds: 60);

  GatewayAccount? _account;
  DateTime? _accountAt;

  /// The last balance seen, without a request; null before the first call.
  GatewayAccount? get lastAccount => _account;

  Uri _url(String action) => base.replace(path: '${base.path}/$action');

  Future<http.Response> _send(http.Request request) async {
    try {
      return await http.Response.fromStream(await client.send(request).timeout(timeout));
    } on TimeoutException {
      throw const ModelFailure('timeout', 'the gateway did not answer in time');
    } on SocketException catch (e) {
      throw ModelFailure('unavailable', 'offline: ${e.message}');
    } on http.ClientException catch (e) {
      throw ModelFailure('unavailable', e.message);
    }
  }

  Future<String> _register() async {
    final request = http.Request('POST', _url('register'))..headers['X-App-Key'] = appKey;
    final response = await _send(request);
    if (response.statusCode != 201) throw _failure(response);
    final json = jsonDecode(response.body) as Map<String, Object?>;
    final token = json['token'] as String;
    await tokens.write(token);
    _remember(GatewayAccount(
      credits: json['credits'] as int? ?? 0,
      granted: json['credits'] as int? ?? 0,
      spent: 0,
      dailyCap: json['dailyCap'] as int? ?? 0,
      dailyUsed: 0,
      model: json['model'] as String? ?? '',
    ));
    return token;
  }

  Future<String> _token() async => await tokens.read() ?? await _register();

  void _remember(GatewayAccount account) {
    _account = account;
    _accountAt = clock();
  }

  /// The device's balance, registering the device first if it never has.
  /// Throws [ModelFailure].
  Future<GatewayAccount> account({bool refresh = false}) async {
    final cached = _account;
    if (!refresh && cached != null && clock().difference(_accountAt!) < accountTtl) return cached;
    var token = await _token();
    var response = await _send(http.Request('GET', _url('me'))..headers['Authorization'] = 'Bearer $token');
    if (response.statusCode == 401) {
      // The ledger forgot this device: start over once.
      await tokens.clear();
      token = await _register();
      response = await _send(http.Request('GET', _url('me'))..headers['Authorization'] = 'Bearer $token');
    }
    if (response.statusCode != 200) throw _failure(response);
    final account = GatewayAccount.fromJson(jsonDecode(response.body) as Map<String, Object?>);
    _remember(account);
    return account;
  }

  @override
  Future<ModelStatus> status() async {
    try {
      final account = await this.account();
      return ModelStatus(
        onDevice: 'unsupported',
        cloud: account.canSpend ? 'available' : 'quota',
        quota: account.quota,
      );
    } on ModelFailure catch (e) {
      return ModelStatus(onDevice: 'unsupported', cloud: e.code == 'quota' ? 'quota' : 'unavailable');
    }
  }

  @override
  Future<ModelReply> respond(ModelRequest request) async {
    if (request.model == ModelChoice.onDevice) {
      throw const ModelFailure('unavailable', 'the cloud runtime has no on-device model');
    }
    final tools = {for (final t in request.tools) t.name: t};
    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': systemPrompt(request)},
      {'role': 'user', 'content': request.prompt},
    ];
    for (var round = 0; round <= maxRounds; round++) {
      final body = {
        'messages': messages,
        if (tools.isNotEmpty) 'tools': [for (final t in tools.values) _function(t)],
        if (tools.isNotEmpty) 'tool_choice': 'auto',
        if (request.schema != null && tools.isEmpty) 'response_format': {'type': 'json_object'},
        if (request.greedy) 'temperature': 0,
      };
      final message = await _chat(body);
      final calls = message['tool_calls'] as List? ?? const [];
      if (calls.isEmpty) {
        final content = message['content'] as String? ?? '';
        return ModelReply(
          content: request.schema == null ? content : jsonObjectIn(content),
          model: 'cloud',
        );
      }
      messages.add({
        'role': 'assistant',
        'content': message['content'],
        'tool_calls': calls,
      });
      for (final raw in calls) {
        final call = Map<String, Object?>.from(raw as Map);
        final function = Map<String, Object?>.from(call['function'] as Map? ?? const {});
        final name = function['name'] as String? ?? '';
        final tool = tools[name];
        String result;
        if (tool == null) {
          result = 'No tool named $name.';
        } else {
          try {
            final text = function['arguments'] as String? ?? '{}';
            final args = text.trim().isEmpty ? <String, Object?>{} : jsonDecode(text);
            result = await tool.run(Map<String, Object?>.from(args as Map));
          } catch (error) {
            // The model reads this and can answer without the tool.
            result = 'The tool failed: $error';
          }
        }
        messages.add({'role': 'tool', 'tool_call_id': call['id'], 'content': result});
      }
    }
    throw const ModelFailure('tool', 'the model kept calling tools');
  }

  /// One call to the gateway; the assistant message, with the balance noted
  /// from the reply headers.
  Future<Map<String, Object?>> _chat(Map<String, Object?> body) async {
    var token = await _token();
    var response = await _post(token, body);
    if (response.statusCode == 401) {
      await tokens.clear();
      token = await _register();
      response = await _post(token, body);
    }
    if (response.statusCode != 200) throw _failure(response);
    final remaining = int.tryParse(response.headers['x-credits-remaining'] ?? '');
    final daily = int.tryParse(response.headers['x-daily-remaining'] ?? '');
    final account = _account;
    if (remaining != null && daily != null && account != null) {
      _remember(account.spent1(credits: remaining, dailyRemaining: daily));
    }
    final json = jsonDecode(response.body) as Map<String, Object?>;
    final choices = json['choices'] as List? ?? const [];
    if (choices.isEmpty) throw const ModelFailure('failed', 'the model gave no choices');
    final choice = Map<String, Object?>.from(choices.first as Map);
    if (choice['finish_reason'] == 'length') {
      throw const ModelFailure('context', 'the reply was cut off');
    }
    if (choice['finish_reason'] == 'content_filter') {
      throw const ModelFailure('refused', 'the model declined');
    }
    return Map<String, Object?>.from(choice['message'] as Map? ?? const {});
  }

  Future<http.Response> _post(String token, Map<String, Object?> body) => _send(
        http.Request('POST', _url('chat'))
          ..headers['Authorization'] = 'Bearer $token'
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(body),
      );

  /// The gateway's coded errors as [ModelFailure] codes.
  static ModelFailure _failure(http.Response response) {
    String code = '', message = '';
    try {
      final error = (jsonDecode(response.body) as Map)['error'] as Map?;
      code = error?['code'] as String? ?? '';
      message = error?['message'] as String? ?? '';
    } catch (_) {
      message = response.body;
    }
    return switch ((response.statusCode, code)) {
      (402, _) || (429, 'daily') || (429, 'registrations') => ModelFailure('quota', message),
      (401, _) => ModelFailure('unavailable', 'not registered: $message'),
      (413, _) => ModelFailure('context', message),
      (503, _) || (502, _) => ModelFailure('unavailable', message),
      (400, _) when message.toLowerCase().contains('context') ||
              message.toLowerCase().contains('token') =>
        ModelFailure('context', message),
      _ => ModelFailure('failed', '${response.statusCode}: $message'),
    };
  }

  static Map<String, Object?> _function(AgentTool tool) => {
        'type': 'function',
        'function': {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.parameters,
        },
      };

  /// The instructions, with the schema spelled out when there is one — the
  /// provider's JSON mode only promises an object, not this object.
  static String systemPrompt(ModelRequest request) {
    final schema = request.schema;
    if (schema == null) return request.instructions;
    return '${request.instructions}\n\nReply with a single JSON object and nothing else — no '
        'prose, no code fence. It must follow this JSON Schema exactly:\n${jsonEncode(schema)}';
  }

  /// The JSON object in [text], which some models wrap in a code fence or a
  /// sentence. Throws [ModelFailure] when there is none.
  static String jsonObjectIn(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final candidate = text.substring(start, end + 1);
      try {
        if (jsonDecode(candidate) is Map) return candidate;
      } on FormatException {
        // fall through
      }
    }
    throw const ModelFailure('failed', 'the reply was not a JSON object');
  }
}
