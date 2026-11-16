/// The one model runtime the app's agents share: cloud models through
/// ai-gateway on the install's credits, and Apple's on-device model on
/// iPhone behind it — for requests that must stay on the phone, and when the
/// cloud is out of reach or out of credits.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hisab_agents/hisab_agents.dart';

import 'apple_model.dart';

/// Set at build time: --dart-define=HISAB_GATEWAY_APP_KEY=… (CI: a secret;
/// locally: --dart-define-from-file=gateway.json, git-ignored).
const gatewayUrl = String.fromEnvironment('HISAB_GATEWAY_URL',
    defaultValue: 'https://ai-gateway.draftsmith.workers.dev/v1/hisab');
const gatewayAppKey = String.fromEnvironment('HISAB_GATEWAY_APP_KEY');

/// The device's gateway token, in the platform keystore like statement
/// passwords. On iPhone it is a synchronizable Keychain item: the Keychain
/// keeps it across a reinstall, and iCloud Keychain carries it to a new
/// iPhone, so bought credits follow the user with no account. A token
/// written before 2.2 (device-only) moves over on first read.
class SecureTokenStore implements GatewayTokenStore {
  static const _legacy = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(synchronizable: true),
  );
  static const _key = 'gateway-token';

  @override
  Future<String?> read() async {
    try {
      final synced = await _storage.read(key: _key);
      if (synced != null) return synced;
      final old = await _legacy.read(key: _key);
      if (old != null) {
        await _storage.write(key: _key, value: old);
        await _legacy.delete(key: _key);
      }
      return old;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _key);
    await _legacy.delete(key: _key);
  }
}

final gateway = GatewayRuntime(
  base: Uri.parse(gatewayUrl),
  appKey: gatewayAppKey,
  tokens: SecureTokenStore(),
);

/// Cloud first, the phone's own model behind it.
class HisabModel implements ModelRuntime {
  final GatewayRuntime cloud;
  final ModelRuntime local;
  const HisabModel({required this.cloud, required this.local});

  @override
  Future<ModelStatus> status() async {
    final results = await Future.wait([cloud.status(), local.status()]);
    final remote = results[0], device = results[1];
    return ModelStatus(
        onDevice: device.onDevice, cloud: remote.cloud, quota: remote.quota);
  }

  @override
  Future<ModelReply> respond(ModelRequest request) async {
    if (request.model == ModelChoice.onDevice) return local.respond(request);
    if (request.model == ModelChoice.cloud) return cloud.respond(request);
    final remote = await cloud.status();
    String? fallback;
    if (remote.cloudReady) {
      try {
        return await cloud.respond(request);
      } on ModelFailure catch (e) {
        // The request's own faults (too long, refused) stand; the cloud's
        // don't, when the phone can answer itself.
        if (!const {'unavailable', 'quota', 'timeout'}.contains(e.code))
          rethrow;
        if (!(await local.status()).onDeviceReady) rethrow;
        fallback = e.code == 'quota' ? 'quota' : 'network';
        debugPrint('model: cloud ${e.code}, falling back on-device');
      }
    } else {
      fallback = remote.cloud == 'quota' ? 'quota' : 'unavailable';
      if (!(await local.status()).onDeviceReady) {
        throw ModelFailure(remote.cloud == 'quota' ? 'quota' : 'unavailable',
            'no cloud model (${remote.cloud}) and no on-device model');
      }
    }
    final reply = await local.respond(request);
    return ModelReply(
        content: reply.content, model: reply.model, fallback: fallback);
  }
}

final hisabModel = HisabModel(cloud: gateway, local: appleModel);

/// Whether some model can answer on this phone. Asked once per process; the
/// cloud side registers the device on first use.
final Future<bool> hisabModelReady =
    hisabModel.status().then((s) => s.ready, onError: (_) => false);
