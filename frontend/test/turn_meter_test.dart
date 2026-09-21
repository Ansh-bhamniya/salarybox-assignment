import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/turn_meter.dart';

Widget _meter({double? turn, bool inPosition = false}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 300,
        child: TurnMeter(turnDegrees: turn, targetMin: 14, targetMax: 26, inPosition: inPosition),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows which end is the person\'s left and which is their right', (tester) async {
    await tester.pumpWidget(_meter(turn: 0));

    expect(find.text('← LEFT'), findsOneWidget);
    expect(find.text('RIGHT →'), findsOneWidget);
  });

  testWidgets('draws with no face, mid-turn, in position and for a far-off reading without errors', (tester) async {
    for (final turn in <double?>[null, 0, 8, 20, -20, 90, -90]) {
      await tester.pumpWidget(_meter(turn: turn, inPosition: turn == 20));
      expect(tester.takeException(), isNull, reason: 'turn $turn');
    }
  });

  testWidgets('says when the head is in the right position, for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_meter(turn: 20, inPosition: true));

    expect(find.bySemanticsLabel('Head in the right position, hold still'), findsOneWidget);
    handle.dispose();
  });

  group('the bar grows out of the middle', () {
    // Renders the meter on black and reads back how bright a point is.
    Future<int Function(double x)> paintedRow(WidgetTester tester, {double? turn}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                child: SizedBox(
                  width: 300,
                  height: 60,
                  child: TurnMeter(turnDegrees: turn, targetMin: 14, targetMax: 26, inPosition: false),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      late ByteData data;
      late int width;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        width = image.width;
        data = (await image.toByteData())!;
      });
      // The bar is drawn on the line at y = 12.
      final int imageWidth = width;
      return (double x) {
        final int column = x.round();
        final int offset = (12 * imageWidth + column) * 4;
        return data.getUint8(offset) + data.getUint8(offset + 1) + data.getUint8(offset + 2);
      };
    }

    testWidgets('looking straight: no bar on either side of the middle', (tester) async {
      final at = await paintedRow(tester, turn: 0);
      expect(at(110), lessThan(300), reason: 'left of the middle is just the dark track');
      expect(at(190), lessThan(300), reason: 'right of the middle too');
    });

    testWidgets('turning left: a bright bar between the middle and the left, nothing on the right', (tester) async {
      final at = await paintedRow(tester, turn: 20); // 20 degrees to the person\'s left, drawn to the left
      expect(at(110), greaterThan(450), reason: 'the bar covers the stretch from the middle toward the left');
      expect(at(190), lessThan(300), reason: 'nothing on the right');
    });

    testWidgets('turning right: the bar is on the right instead', (tester) async {
      final at = await paintedRow(tester, turn: -20);
      expect(at(190), greaterThan(450));
      expect(at(110), lessThan(300));
    });

    testWidgets('no face: no bar at all', (tester) async {
      final at = await paintedRow(tester, turn: null);
      expect(at(110), lessThan(300));
      expect(at(190), lessThan(300));
    });
  });
}
