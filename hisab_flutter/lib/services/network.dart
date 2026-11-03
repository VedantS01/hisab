/// Whether the phone has a network, for the offline banner. Offline, Apple's
/// cloud model is out of reach (the agents fall back to the on-device one)
/// and the home feed stays as last fetched.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../feed/home_feed.dart';

abstract final class Network {
  static final offline = ValueNotifier<bool>(false);
  static StreamSubscription<List<ConnectivityResult>>? _changes;

  static Future<void> watch() async {
    final connectivity = Connectivity();
    void update(List<ConnectivityResult> results) {
      final wasOffline = offline.value;
      offline.value = results.every((r) => r == ConnectivityResult.none);
      if (wasOffline && !offline.value) HomeFeed.refresh();
    }

    try {
      update(await connectivity.checkConnectivity());
      _changes ??= connectivity.onConnectivityChanged.listen(update);
    } catch (_) {
      // No plugin (tests): assume online, as before this existed.
    }
  }
}
