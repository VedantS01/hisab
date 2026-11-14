/// AI credit packs and Hisab Plus through the App Store (StoreKit 2). Apple
/// takes the payment; the gateway verifies each signed transaction and keeps
/// the balance ([GatewayRuntime.purchase]). There is no Hisab account: the
/// subscription belongs to the Apple ID (Restore re-links it), and bought
/// credits sit on the gateway against this phone's token, which the Keychain
/// keeps across reinstalls and iCloud Keychain carries to a new iPhone.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hisab_agents/hisab_agents.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'hisab_model.dart';

/// What the store sheet shows while and after a purchase.
class StoreStatus {
  final bool busy;
  final String? message;
  final bool error;
  const StoreStatus({this.busy = false, this.message, this.error = false});
}

abstract final class HisabStore {
  static const credits100 = 'com.vedants.hisab.credits.100';
  static const credits500 = 'com.vedants.hisab.credits.500';
  static const plusMonthly = 'com.vedants.hisab.plus.monthly';
  static const ids = {credits100, credits500, plusMonthly};

  static const termsUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
  static const privacyUrl = 'https://vedants01.github.io/hisab/#privacy';

  /// The App Store only on iPhone; nothing is sold on Android yet.
  static bool get available => defaultTargetPlatform == TargetPlatform.iOS;

  static final status = ValueNotifier<StoreStatus>(const StoreStatus());

  /// The balance after the last purchase the gateway accepted.
  static final account = ValueNotifier<GatewayAccount?>(null);

  static StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// From `main`: transactions left unfinished last time (the gateway was
  /// unreachable, the app was killed mid-purchase) are redelivered now and
  /// handed over again; a transaction counts once on the gateway.
  static void start() {
    if (!available || _subscription != null) return;
    _subscription = InAppPurchase.instance.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          await _handle(purchase);
        }
      },
      onError: (Object e) => status.value = const StoreStatus(
          message: 'The App Store did not answer.', error: true),
    );
  }

  static Future<List<ProductDetails>> products() async {
    if (!available || !await InAppPurchase.instance.isAvailable())
      return const [];
    final response = await InAppPurchase.instance.queryProductDetails(ids);
    final order = ids.toList();
    return response.productDetails
      ..sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
  }

  static Future<void> buy(ProductDetails product) async {
    status.value = const StoreStatus(busy: true);
    final param = PurchaseParam(productDetails: product);
    try {
      final started = product.id == plusMonthly
          ? await InAppPurchase.instance.buyNonConsumable(purchaseParam: param)
          : await InAppPurchase.instance.buyConsumable(purchaseParam: param);
      if (!started) status.value = const StoreStatus();
    } catch (e) {
      status.value = const StoreStatus(
          message: 'That purchase could not start. Try again.', error: true);
    }
  }

  /// Re-links a subscription bought on this Apple ID (a reinstall, a second
  /// iPhone). Credit packs are not restorable by Apple's design; they live
  /// on the gateway against this phone's token.
  static Future<void> restore() async {
    status.value = const StoreStatus(busy: true);
    try {
      await InAppPurchase.instance.restorePurchases();
      // Restored transactions arrive on the stream; with none, say so.
      Timer(const Duration(seconds: 4), () {
        if (status.value.busy) {
          status.value = const StoreStatus(
              message: 'No subscription to restore on this Apple ID.');
        }
      });
    } catch (_) {
      status.value = const StoreStatus(
          message: 'Restore did not reach the App Store.', error: true);
    }
  }

  static Future<void> _handle(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        status.value = const StoreStatus(
            busy: true, message: 'Waiting for the App Store…');
        return;
      case PurchaseStatus.canceled:
        status.value = const StoreStatus();
        await _finish(purchase);
        return;
      case PurchaseStatus.error:
        status.value = StoreStatus(
            message: purchase.error?.message ?? 'The purchase failed.',
            error: true);
        await _finish(purchase);
        return;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        try {
          final after = await gateway
              .purchase(purchase.verificationData.serverVerificationData);
          account.value = after;
          status.value = StoreStatus(message: _thanks(purchase, after));
          await _finish(purchase);
        } on ModelFailure catch (e) {
          if (e.code == 'purchase') {
            // Refused for what it is (refunded, another app's): finishing it
            // stops it coming back; retrying would never succeed.
            status.value = StoreStatus(message: e.message, error: true);
            await _finish(purchase);
          } else {
            // Unreachable gateway: left unfinished, StoreKit hands it back
            // on the next launch and it is applied then.
            status.value = const StoreStatus(
                message: 'Paid. Hisab will add it as soon as it is online.',
                error: true);
          }
        }
    }
  }

  static String _thanks(PurchaseDetails purchase, GatewayAccount after) =>
      switch (purchase.productID) {
        plusMonthly => after.plus
            ? 'Hisab Plus is on: ${after.dailyCap} free credits a day.'
            : 'Subscription restored.',
        _ => 'Added. You have ${after.credits} banked credits.',
      };

  static Future<void> _finish(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await InAppPurchase.instance.completePurchase(purchase);
    }
  }
}
