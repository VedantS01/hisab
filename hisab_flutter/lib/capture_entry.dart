/// The Dart side of iOS's "Add Transaction Alert" Shortcuts action.
///
/// An automation runs the action with the app closed and nothing on screen,
/// so the Runner starts a second, headless Flutter engine at [captureMain]
/// (see ios/Runner/CaptureBridge.swift) instead of booting the whole app.
/// It always uses that engine, even when the app is open, so there is one
/// path to test; the app's engine is told afterwards to re-read its tables.
library;

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'services/capture_intake.dart';
import 'services/notification_capture.dart';
import 'storage/database.dart';

const captureChannel = MethodChannel('hisab/capture');

@pragma('vm:entry-point')
Future<void> captureMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase(driftDatabase(name: 'hisab'));
  captureChannel.setMethodCallHandler((call) async {
    if (call.method != 'ingest') {
      throw MissingPluginException('hisab/capture has no ${call.method}');
    }
    final args = Map<String, Object?>.from(call.arguments as Map);
    final result = await CaptureIntake.ingest(
      text: args['text'] as String? ?? '',
      note: args['note'] as String?,
      db: db,
      now: DateTime.now(),
      extractor: await NotificationCapture.extractor(),
    );
    return {'outcome': result.outcome.name, 'dialog': result.dialog};
  });
  // The native side holds the action until this arrives: a call made before
  // the handler exists would be dropped as "no implementation".
  await captureChannel.invokeMethod<void>('ready');
}
