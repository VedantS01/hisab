/// [ModelRuntime] over tool/apple_model_cli — the app's Swift runtime on this
/// Mac — for evals. One process serves many requests; tool calls come back
/// over its stdout and are answered on its stdin.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'runtime.dart';

class ProcessRuntime implements ModelRuntime {
  final Process _process;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _tools = <int, List<AgentTool>>{};
  var _nextId = 0;

  ProcessRuntime._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_receive);
    _process.stderr.transform(utf8.decoder).listen(stderr.write);
  }

  /// [executable] is the built CLI (`swift build -c release` in
  /// tool/apple_model_cli); [cloud] only for a build holding the Private
  /// Cloud Compute entitlement.
  static Future<ProcessRuntime> start(String executable, {bool cloud = false}) async =>
      ProcessRuntime._(await Process.start(executable, [if (cloud) '--cloud']));

  @override
  Future<ModelStatus> status() async {
    final message = await _send({'type': 'status'});
    return ModelStatus.fromJson(Map<String, Object?>.from(message['status'] as Map));
  }

  @override
  Future<ModelReply> respond(ModelRequest request) async {
    final message = await _send({'type': 'respond', 'request': request.toJson()},
        tools: request.tools);
    if (message['type'] == 'error') {
      throw ModelFailure(message['code'] as String, message['message'] as String? ?? '');
    }
    return ModelReply.fromJson(Map<String, Object?>.from(message['reply'] as Map));
  }

  Future<void> close() async {
    await _process.stdin.close();
    await _process.exitCode;
  }

  Future<Map<String, Object?>> _send(Map<String, Object?> message,
      {List<AgentTool> tools = const []}) {
    final id = ++_nextId;
    final done = _pending[id] = Completer();
    _tools[id] = tools;
    _process.stdin.writeln(jsonEncode({...message, 'id': id}));
    return done.future.whenComplete(() => _tools.remove(id));
  }

  Future<void> _receive(String line) async {
    final message = jsonDecode(line) as Map<String, Object?>;
    final id = message['id'] as int? ?? 0;
    if (message['type'] != 'toolCall') {
      _pending.remove(id)?.complete(message);
      return;
    }
    final name = message['name'] as String;
    final tool = _tools[id]?.where((t) => t.name == name).firstOrNull;
    String result;
    try {
      result = tool == null
          ? 'No tool named $name.'
          : await tool.run(jsonDecode(message['arguments'] as String) as Map<String, Object?>);
    } catch (error) {
      result = 'The tool failed: $error';
    }
    _process.stdin.writeln(
        jsonEncode({'type': 'toolResult', 'callId': message['callId'], 'result': result}));
  }
}
