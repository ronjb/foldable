import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';
import 'package:foldable/src/platform/foldable_codec.dart';

/// The window controls' corner in a window on the iPad mini (A20 Pro)
/// simulator, as measured on iPadOS 27.2.
const Rect kWindowControls = Rect.fromLTWH(0, 0, 66, 53);

/// A snapshot from a device without a hinge, at [supportLevel].
FoldableData ipadWith({
  Rect controls = Rect.zero,
  Rect topBar = Rect.zero,
  FoldableSupportLevel supportLevel = FoldableSupportLevel.availableNoHinge,
}) => FoldableData(
  capabilities: FoldableCapabilities(
    supportLevel: supportLevel,
    isFoldable: false,
    hingeApiPresent: supportLevel != FoldableSupportLevel.unsupported,
    regionApiPresent: supportLevel != FoldableSupportLevel.unsupported,
    angleUnitVerified: false,
    strategy: 'test',
  ),
  status: HingeStatus.unknown,
  angleDegrees: null,
  regions: const <ReservedRegion>[],
  displayFeatures: const [],
  topBarFrame: topBar,
  windowControlsFrame: controls,
);

Future<void> push(
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
    test('decodes the window controls', () {
      final FoldableData data = FoldableCodec.decodeSnapshot(
        const <Object?, Object?>{
          'windowControls': <String, Object?>{
            'left': 0,
            'top': 0,
            'width': 66,
            'height': 53,
          },
        },
      );
      expect(data.windowControlsFrame, kWindowControls);
    });

    test('missing or malformed values mean no controls', () {
      for (final Map<Object?, Object?> raw in <Map<Object?, Object?>>[
        const <Object?, Object?>{},
        const <Object?, Object?>{'windowControls': 'x'},
      ]) {
        expect(
          FoldableCodec.decodeSnapshot(raw).windowControlsFrame,
          Rect.zero,
        );
      }
    });
  });

  testWidgets('a window controls change rebuilds only its readers', (
    WidgetTester tester,
  ) async {
    final StreamController<FoldableData> feed =
        StreamController<FoldableData>.broadcast();
    addTearDown(feed.close);

    late Rect frame;
    int topBarBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FoldableProvider(
          debugData: feed.stream,
          child: Column(
            children: <Widget>[
              Builder(
                builder: (BuildContext context) {
                  frame = DuoMediaQuery.windowControlsFrameOf(context);
                  return const SizedBox();
                },
              ),
              Builder(
                builder: (BuildContext context) {
                  DuoMediaQuery.topBarFrameOf(context);
                  topBarBuilds++;
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      ),
    );

    await push(tester, feed, ipadWith());
    expect(frame, Rect.zero);
    final int topBarBaseline = topBarBuilds;

    await push(tester, feed, ipadWith(controls: kWindowControls));

    expect(frame, kWindowControls);
    expect(
      topBarBuilds,
      topBarBaseline,
      reason: 'top bar reader rebuilt on a window-controls-only change',
    );
  });

  // iPadOS 26 has the window controls but not the hinge API, so its support
  // level is `unsupported`. iPadOS 27 has the hinge API, but an iPad never
  // sends the hinge update that would settle it as `availableNoHinge`, so it
  // stays `unknown`: measured on an iPad Pro (11-inch, 3rd generation) and on
  // the iPad mini (A20 Pro) simulator. Whatever the level, the controls must
  // come over the layout stream.
  for (final FoldableSupportLevel level in <FoldableSupportLevel>[
    FoldableSupportLevel.unsupported,
    FoldableSupportLevel.unknown,
    FoldableSupportLevel.availableNoHinge,
  ]) {
    testWidgets('layout changes arrive without a hinge (${level.name})', (
      WidgetTester tester,
    ) async {
      final _FakePlatform platform = _FakePlatform(
        ipadWith(supportLevel: level),
      );
      addTearDown(platform.layout.close);

      Rect? frame;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            platform: platform,
            child: Builder(
              builder: (BuildContext context) {
                frame = DuoMediaQuery.windowControlsFrameOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(frame, Rect.zero);

      await push(
        tester,
        platform.layout,
        ipadWith(supportLevel: level, controls: kWindowControls),
      );
      expect(frame, kWindowControls);

      // Full screen: the controls go away with no change of window size.
      await push(tester, platform.layout, ipadWith(supportLevel: level));
      expect(frame, Rect.zero);

      await tester.pumpWidget(const SizedBox());
      expect(
        platform.layout.hasListener,
        isFalse,
        reason: 'the provider kept listening after it was removed',
      );
    });
  }
}

/// A platform without a hinge whose layout changes the test sends by hand.
class _FakePlatform extends FoldablePlatform {
  _FakePlatform(this.snapshot);

  final FoldableData snapshot;
  final StreamController<FoldableData> layout =
      StreamController<FoldableData>.broadcast();

  @override
  Future<FoldableData> getSnapshot() async => snapshot;

  @override
  Stream<FoldableData> get events => const Stream<FoldableData>.empty();

  @override
  Stream<FoldableData> get layoutChanges => layout.stream;
}
