import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/feed/home_feed.dart';

void main() {
  test('the site starts from the bundled feed', () {
    final site = HomeFeed.parse(File('../docs/feed/v1.json').readAsStringSync())!;
    expect([for (final s in site.sections) s.type],
        [for (final s in HomeFeed.bundled.sections) s.type]);
    expect(HomeFeed.bundled.sections.first.type, 'sampleDataBar');
  });

  test('a card section carries its card and action', () {
    final feed = HomeFeed.parse(jsonEncode({
      'version': 1,
      'sections': [
        {
          'type': 'card',
          'icon': 'lightbulb',
          'title': 'Paste a payment',
          'body': 'Find in text reads an SMS or email.',
          'action': {'open': 'detections'},
          'until': '2026-12-01T00:00:00Z',
        },
        {'type': 'card', 'icon': 'info'},
        {'type': 'somethingNewer'},
      ]
    }))!;
    final card = feed.sections.first.card!;
    expect([card.title, card.action!.open, card.until!.month], ['Paste a payment', 'detections', 12]);
    // A card without its text is dropped; a type this build doesn't know is
    // kept and skipped by the dashboard.
    expect([for (final s in feed.sections) s.type], ['card', 'somethingNewer']);
  });

  test('a feed this build cannot show is not one', () {
    expect(HomeFeed.parse('{"version": 2, "sections": [{"type": "hero"}]}'), isNull);
    expect(HomeFeed.parse('{"version": 1, "sections": []}'), isNull);
    expect(HomeFeed.parse('<html>'), isNull);
  });
}
