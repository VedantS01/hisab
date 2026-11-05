/// Apple's language models for hisab_agents, through the iOS channel
/// (ios/Runner/AppleModelChannel.swift): Private Cloud Compute when the build
/// is entitled, the on-device model otherwise. Elsewhere there is no model
/// and [ChannelRuntime.status] says so.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hisab_agents/hisab_agents.dart';
import 'package:hisab_core/hisab_core.dart';

import 'gemini_nano_column_reader.dart';

class ChannelRuntime implements ModelRuntime {
  static const _channel = MethodChannel('hisab/apple_model');

  /// The tools of requests in flight, by name: the model calls them back
  /// through the channel while it answers.
  final _tools = <String, AgentTool>{};

  ChannelRuntime() {
    _channel.setMethodCallHandler(_handle);
  }

  static bool get _supported => !kIsWeb && Platform.isIOS;

  @override
  Future<ModelStatus> status() async {
    if (!_supported) return ModelStatus.unsupported;
    try {
      final text = await _channel.invokeMethod<String>('status');
      return ModelStatus.fromJson(jsonDecode(text ?? '{}') as Map<String, Object?>);
    } on PlatformException {
      return ModelStatus.unsupported;
    } on MissingPluginException {
      return ModelStatus.unsupported;
    }
  }

  @override
  Future<ModelReply> respond(ModelRequest request) async {
    if (!_supported) throw const ModelFailure('unavailable', 'no Apple model here');
    for (final tool in request.tools) {
      _tools[tool.name] = tool;
    }
    try {
      final text = await _channel.invokeMethod<String>('respond', jsonEncode(request.toJson()));
      return ModelReply.fromJson(jsonDecode(text ?? '{}') as Map<String, Object?>);
    } on PlatformException catch (e) {
      throw ModelFailure(e.code, e.message ?? '');
    } on MissingPluginException {
      throw const ModelFailure('unavailable', 'no Apple model channel');
    } finally {
      for (final tool in request.tools) {
        _tools.remove(tool.name);
      }
    }
  }

  /// Apple's sheet for more cloud requests (iCloud+), when the daily limit
  /// is near or reached.
  Future<void> showQuotaOptions() => _channel.invokeMethod<void>('showQuotaOptions');

  Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'tool') throw MissingPluginException(call.method);
    final args = Map<String, Object?>.from(call.arguments as Map);
    final tool = _tools[args['name']];
    if (tool == null) return 'No tool named ${args['name']}.';
    try {
      return await tool.run(jsonDecode(args['arguments'] as String) as Map<String, Object?>);
    } catch (error) {
      // The model reads this and can answer without the tool.
      return 'The tool failed: $error';
    }
  }
}

/// The one runtime the app's agents share.
final appleModel = ChannelRuntime();

/// Whether one of Apple's models can answer on this phone. Asked once per
/// process.
final Future<bool> appleModelReady =
    appleModel.status().then((s) => s.ready, onError: (_) => false);

/// The phone's own model for reading an unknown statement's columns: Apple's
/// on iOS, Gemini Nano on Android; null when neither can.
Future<ColumnRoleProposer?> columnReaderOnThisPhone() async {
  if (!kIsWeb && Platform.isIOS) {
    return (await appleModel.status()).onDeviceReady ? AppleColumnReader(appleModel) : null;
  }
  return await GeminiNanoColumnReader.isAvailable() ? const GeminiNanoColumnReader() : null;
}
