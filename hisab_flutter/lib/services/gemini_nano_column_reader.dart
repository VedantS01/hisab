/// Gemini Nano reading a statement table's columns, on the phone. The Android
/// counterpart of OnDeviceColumnReader.swift; the Kotlin half is in
/// MainActivity. Nothing it says is trusted until the balance chain closes
/// under it (ProposedMapping).
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hisab_core/hisab_core.dart';

class GeminiNanoColumnReader implements ColumnRoleProposer {
  const GeminiNanoColumnReader();

  static const _channel = MethodChannel('hisab/column_reader');

  /// False without Gemini Nano: a phone AICore doesn't serve, the model not
  /// downloaded yet, or not Android at all.
  static Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<String>('status') == 'available';
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<ColumnRoles?> propose(List<String>? header, List<List<String>> rows) async {
    final width = [header ?? const <String>[], ...rows].fold(0, (w, r) => r.length > w ? r.length : w);
    final reply = await _channel
        .invokeMethod<String>('label', {'prompt': ColumnLabelPrompt.build(header, rows)});
    return reply == null ? null : ColumnRoles.fromLabels(ColumnLabelPrompt.parse(reply, width));
  }
}
