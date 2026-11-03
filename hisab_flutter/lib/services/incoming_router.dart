/// Statement files opened or shared into Hisab, and hisab:// links, arriving
/// from the native side (ios/Runner/IncomingRouter.swift, and its Android
/// twin). Mirrors the Swift app's DeepLinkRouter.
///
/// Values are parked in notifiers rather than acted on here, because a cold
/// launch delivers them before any screen exists to act; `RootTabs` drains
/// them on its first frame and listens for the rest.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'capture_notifier.dart';

class IncomingFile {
  /// A private copy the native side staged; deleted once read.
  final String path;
  final String name;
  const IncomingFile(this.path, this.name);
}

/// Where a link asked to go. [memo] links also set
/// `CaptureRouter.reviewRequest`, which opens the memo itself.
enum LinkTarget { dashboard, transactions }

abstract final class IncomingRouter {
  static const _channel = MethodChannel('hisab/incoming');

  static final ValueNotifier<IncomingFile?> file = ValueNotifier(null);
  static final ValueNotifier<LinkTarget?> link = ValueNotifier(null);

  static Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') route(call.arguments);
    });
    try {
      final queued = await _channel.invokeListMethod<Object?>('pending');
      for (final item in queued ?? const []) {
        route(item);
      }
    } on MissingPluginException {
      // Tests, and any platform without the native half.
    }
  }

  @visibleForTesting
  static void route(Object? arguments) {
    final item = Map<String, Object?>.from(arguments as Map);
    switch (item['kind']) {
      case 'file':
        file.value = IncomingFile(item['path'] as String, item['name'] as String);
      case 'link':
        final uri = Uri.parse(item['url'] as String);
        final value = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
        if (uri.host == 'memo' && value.isNotEmpty) {
          CaptureRouter.reviewRequest.value = value;
        }
        link.value = uri.host == 'transaction'
            ? LinkTarget.transactions
            : LinkTarget.dashboard;
    }
  }
}
