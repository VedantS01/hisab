/// The home feed: which sections the dashboard shows, in what order, and
/// any cards added to it — a static JSON document on GitHub Pages
/// (docs/feed/v1.json), cached on the phone, with [HomeFeed.bundled] in the
/// app for a first launch offline. The insights agent's cards render as the
/// same [FeedCard].
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Where a card goes when tapped.
class FeedAction {
  /// transactions | detections | import | url
  final String open;
  final String? category;
  final String? url;
  const FeedAction(this.open, {this.category, this.url});

  static FeedAction? fromJson(Object? json) {
    if (json is! Map) return null;
    final open = json['open'];
    if (open is! String) return null;
    return FeedAction(open,
        category: json['category'] as String?, url: json['url'] as String?);
  }
}

class FeedCard {
  /// A Material icon name from [FeedIcons]; unknown names get a default.
  final String icon;
  final String title;
  final String body;
  final FeedAction? action;

  /// Not shown from this moment on.
  final DateTime? until;

  const FeedCard({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.until,
  });

  static FeedCard? fromJson(Map<Object?, Object?> json) {
    final title = json['title'], body = json['body'];
    if (title is! String || body is! String) return null;
    return FeedCard(
      icon: json['icon'] as String? ?? 'info',
      title: title,
      body: body,
      action: FeedAction.fromJson(json['action']),
      until: DateTime.tryParse(json['until'] as String? ?? ''),
    );
  }
}

class FeedSection {
  /// sampleDataBar | captureHealth | insights | monthPicker | hero | trend |
  /// breakdown | merchants | card. A type this build doesn't know is skipped,
  /// so a newer feed never breaks an older app.
  final String type;
  final FeedCard? card;
  const FeedSection(this.type, [this.card]);
}

class HomeFeed {
  static const version = 1;
  static const remote = 'https://vedants01.github.io/hisab/feed/v1.json';

  final List<FeedSection> sections;
  const HomeFeed(this.sections);

  /// Shipped with the app; docs/feed/v1.json starts as the same document.
  static const bundledJson = '''
{
  "version": 1,
  "sections": [
    {"type": "sampleDataBar"},
    {"type": "captureHealth"},
    {"type": "insights"},
    {"type": "monthPicker"},
    {"type": "hero"},
    {"type": "trend"},
    {"type": "breakdown"},
    {"type": "merchants"}
  ]
}''';

  static final bundled = parse(bundledJson)!;

  /// What the dashboard shows now.
  static final current = ValueNotifier<HomeFeed>(bundled);

  /// A feed document, or null when it isn't one this build can show.
  static HomeFeed? parse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map || json['version'] != version) return null;
      final sections = <FeedSection>[];
      for (final raw in json['sections'] as List) {
        final s = Map<Object?, Object?>.from(raw as Map);
        final type = s['type'] as String;
        if (type == 'card') {
          final card = FeedCard.fromJson(s);
          if (card != null) sections.add(FeedSection(type, card));
        } else {
          sections.add(FeedSection(type));
        }
      }
      return sections.isEmpty ? null : HomeFeed(sections);
    } catch (_) {
      return null;
    }
  }

  /// The cached feed, then a fresh one from the site in the background.
  static Future<void> load() async {
    try {
      final cached = await _cacheFile();
      if (await cached.exists()) {
        final feed = parse(await cached.readAsString());
        if (feed != null) current.value = feed;
      }
    } catch (_) {}
    refresh();
  }

  /// Fetches the site's feed; the cache and [current] change only when it
  /// is one this build can show.
  static Future<void> refresh() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.getUrl(Uri.parse(remote));
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final text = await response.transform(utf8.decoder).join();
      final feed = parse(text);
      if (feed == null) return;
      await (await _cacheFile()).writeAsString(text);
      current.value = feed;
    } catch (_) {
      // Offline or the site is down: the cached or bundled feed stays.
    } finally {
      client.close();
    }
  }

  static Future<File> _cacheFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/home-feed-v1.json');
}
