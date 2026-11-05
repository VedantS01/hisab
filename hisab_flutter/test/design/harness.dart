// Shared pump helper for the design-system tests: a 320-wide phone (the
// narrowest we support) so overflow shows up, in either theme.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/design/design.dart';

const themes = {'light': false, 'dark': true};

Future<void> pumpApp(WidgetTester tester, Widget home, {bool dark = false}) {
  tester.view.physicalSize = const Size(320 * 3, 640 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(MaterialApp(
    theme: HisabDesign.light(),
    darkTheme: HisabDesign.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: home,
  ));
}

/// [child] in a scrolling, padded page body.
Future<void> pumpComponent(WidgetTester tester, Widget child,
        {bool dark = false}) =>
    pumpApp(
      tester,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(HisabSpace.gutter),
          children: [child],
        ),
      ),
      dark: dark,
    );
