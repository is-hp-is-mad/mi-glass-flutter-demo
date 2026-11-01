import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_glass/hyper_glass.dart';
import 'package:hyper_glass/hyper_ui.dart';

void main() {
  testWidgets('glass outside a scene says what is wrong', (tester) async {
    await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: HyperGlass()));
    expect(tester.takeException().toString(), contains('HyperGlassScene'));
  });

  testWidgets('HyperOverlay.of without one says what is wrong', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    expect(() => HyperOverlay.of(context), throwsA(isA<FlutterError>()));
  });

  testWidgets('a shadow before init says what is wrong', (tester) async {
    await tester.pumpWidget(const ViewShadow(radius: 8, child: SizedBox.expand()));
    expect(tester.takeException().toString(), contains('HyperGlass.init'));
  });

  testWidgets('the theme decides light, dark and the accent', (tester) async {
    late BuildContext inner;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: HyperTheme(
          primary: const Color(0xff00aa00),
          child: Builder(
            builder: (c) {
              inner = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(HyperTheme.isDark(inner), isTrue);
    expect(HyperTheme.primaryOf(inner), const Color(0xff00aa00));
  });
}
