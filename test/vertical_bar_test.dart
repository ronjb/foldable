import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';
import 'package:foldable/src/platform/foldable_codec.dart';

/// The vertical bar's frame on the iPhone Duo cover display, as measured on
/// the simulator.
const Rect kCoverBar = Rect.fromLTWH(376, 174, 84, 470);

FoldableData dataWith({
  Rect bar = Rect.zero,
  HingeStatus status = HingeStatus.closed,
}) => FoldableData(
  capabilities: const FoldableCapabilities(
    supportLevel: FoldableSupportLevel.available,
    isFoldable: true,
    hingeApiPresent: true,
    regionApiPresent: true,
    angleUnitVerified: true,
    strategy: 'test',
  ),
  status: status,
  angleDegrees: 0,
  regions: const <ReservedRegion>[],
  displayFeatures: const [],
  verticalBarEdge: VerticalBarEdge.trailing,
  verticalBarFrame: bar,
);

Future<void> pushData(
  WidgetTester tester,
  StreamController<FoldableData> controller,
  FoldableData data,
) async {
  controller.add(data);
  await tester.pump();
  await tester.pump();
}

void main() {
  group('wire decoding', () {
    test('decodes the edge and the frame', () {
      final FoldableData data = FoldableCodec.decodeSnapshot(
        const <Object?, Object?>{
          'verticalBarEdge': 'trailing',
          'verticalBar': <String, Object?>{
            'left': 376,
            'top': 174,
            'width': 84,
            'height': 470,
          },
        },
      );
      expect(data.verticalBarEdge, VerticalBarEdge.trailing);
      expect(data.verticalBarFrame, kCoverBar);
    });

    test('missing or malformed values mean no bar', () {
      for (final Map<Object?, Object?> raw in <Map<Object?, Object?>>[
        const <Object?, Object?>{},
        const <Object?, Object?>{'verticalBarEdge': 'top', 'verticalBar': 'x'},
      ]) {
        final FoldableData data = FoldableCodec.decodeSnapshot(raw);
        expect(data.verticalBarEdge, VerticalBarEdge.unspecified);
        expect(data.verticalBarFrame, Rect.zero);
      }
    });

    test('every wire name round trips', () {
      for (final VerticalBarEdge value in VerticalBarEdge.values) {
        expect(VerticalBarEdge.fromWire(value.wireName), value);
      }
    });
  });

  group('DuoMediaQuery', () {
    testWidgets('exposes the vertical bar', (WidgetTester tester) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      late VerticalBarEdge edge;
      late Rect frame;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            debugData: feed.stream,
            child: Builder(
              builder: (BuildContext context) {
                edge = DuoMediaQuery.verticalBarEdgeOf(context);
                frame = DuoMediaQuery.verticalBarFrameOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await pushData(tester, feed, dataWith(bar: kCoverBar));

      expect(edge, VerticalBarEdge.trailing);
      expect(frame, kCoverBar);
    });

    testWidgets('posture readers ignore a vertical bar change', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      int statusBuilds = 0;
      int barBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            debugData: feed.stream,
            child: Column(
              children: <Widget>[
                Builder(
                  builder: (BuildContext context) {
                    DuoMediaQuery.statusOf(context);
                    statusBuilds++;
                    return const SizedBox();
                  },
                ),
                Builder(
                  builder: (BuildContext context) {
                    DuoMediaQuery.verticalBarFrameOf(context);
                    barBuilds++;
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );

      await pushData(tester, feed, dataWith());
      final int statusBaseline = statusBuilds;
      final int barBaseline = barBuilds;

      await pushData(tester, feed, dataWith(bar: kCoverBar));

      expect(
        statusBuilds,
        statusBaseline,
        reason: 'posture reader rebuilt on a vertical-bar-only change',
      );
      expect(barBuilds, greaterThan(barBaseline));
    });

    testWidgets('without a provider there is no bar', (
      WidgetTester tester,
    ) async {
      late VerticalBarEdge edge;
      late Rect frame;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            edge = DuoMediaQuery.verticalBarEdgeOf(context);
            frame = DuoMediaQuery.verticalBarFrameOf(context);
            return const SizedBox();
          },
        ),
      );
      expect(edge, VerticalBarEdge.unspecified);
      expect(frame, Rect.zero);
    });
  });

  testWidgets('the provider re-reads the platform when the safe area changes', (
    WidgetTester tester,
  ) async {
    final _FakePlatform platform = _FakePlatform();
    addTearDown(tester.view.reset);

    Rect? frame;
    await tester.pumpWidget(
      MaterialApp(
        home: FoldableProvider(
          platform: platform,
          child: Builder(
            builder: (BuildContext context) {
              frame = DuoMediaQuery.verticalBarFrameOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(frame, Rect.zero);

    // The bar appearing changes the safe area, not the window size.
    platform.next = dataWith(bar: kCoverBar);
    tester.view.viewPadding = FakeViewPadding(
      right: kCoverBar.width * tester.view.devicePixelRatio,
    );
    await tester.pump();
    await tester.pump();

    expect(frame, kCoverBar);
  });
}

/// A platform that answers every snapshot request with [next].
class _FakePlatform extends FoldablePlatform {
  FoldableData next = dataWith();

  @override
  Future<FoldableData> getSnapshot() async => next;

  @override
  Stream<FoldableData> get events => const Stream<FoldableData>.empty();
}
