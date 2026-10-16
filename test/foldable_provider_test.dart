import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

FoldableData dataFor(HingeStatus status) => FoldableData(
  capabilities: const FoldableCapabilities(
    supportLevel: FoldableSupportLevel.available,
    isFoldable: true,
    hingeApiPresent: true,
    regionApiPresent: true,
    angleUnitVerified: true,
    strategy: 'test',
  ),
  status: status,
  angleDegrees: status == HingeStatus.fullyOpen ? 180 : 95,
  regions: const <ReservedRegion>[
    ReservedRegion(
      kind: ReservedRegionKind.division,
      bounds: Rect.fromLTWH(455.5, 0, 40, 669),
      isActive: true,
    ),
  ],
  displayFeatures: const [],
);

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static int initCount = 0;

  @override
  void initState() {
    super.initState();
    initCount++;
  }

  @override
  Widget build(BuildContext context) =>
      Text('${MediaQuery.of(context).displayFeatures.length}');
}

void main() {
  testWidgets('publishing and withdrawing a fold keeps the subtree mounted', (
    WidgetTester tester,
  ) async {
    // The provider used to insert a MediaQuery only while it had features to
    // publish. That changed the shape of the tree, so every fold and unfold in
    // `full` mode, and every change of bridge mode, rebuilt the whole app below
    // it from scratch: scroll positions, text fields and State were lost.
    _ProbeState.initCount = 0;
    final StreamController<FoldableData> feed =
        StreamController<FoldableData>.broadcast();
    addTearDown(feed.close);

    Future<void> pump(DisplayFeatureBridgeMode mode) => tester.pumpWidget(
      MaterialApp(
        home: FoldableProvider(
          bridgeMode: mode,
          debugData: feed.stream,
          child: const _Probe(),
        ),
      ),
    );

    Future<void> push(HingeStatus status) async {
      feed.add(dataFor(status));
      await tester.pump();
      await tester.pump();
    }

    await pump(DisplayFeatureBridgeMode.full);
    await push(HingeStatus.fullyOpen);
    expect(find.text('0'), findsOneWidget);

    await push(HingeStatus.partiallyOpen);
    expect(find.text('1'), findsOneWidget);

    await push(HingeStatus.fullyOpen);
    expect(find.text('0'), findsOneWidget);

    await pump(DisplayFeatureBridgeMode.none);
    await push(HingeStatus.partiallyOpen);
    expect(find.text('0'), findsOneWidget);

    await pump(DisplayFeatureBridgeMode.full);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    expect(_ProbeState.initCount, 1);
  });

  testWidgets('a resize keeps simulated debugData state', (
    WidgetTester tester,
  ) async {
    // A resize re-reads size classes from the platform. While debugData drives
    // the provider, the platform's answer must not replace the simulated one.
    final _FakePlatform platform = _FakePlatform()
      ..reply.complete(dataFor(HingeStatus.closed));
    final StreamController<FoldableData> feed =
        StreamController<FoldableData>.broadcast();
    addTearDown(feed.close);
    addTearDown(tester.view.reset);

    HingeStatus? status;
    await tester.pumpWidget(
      MaterialApp(
        home: FoldableProvider(
          platform: platform,
          debugData: feed.stream,
          child: Builder(
            builder: (BuildContext context) {
              status = DuoMediaQuery.statusOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await _push(tester, feed, HingeStatus.partiallyOpen);

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pump();
    await tester.pump();

    expect(status, HingeStatus.partiallyOpen);
  });

  testWidgets('a platform reply after switching to debugData is dropped', (
    WidgetTester tester,
  ) async {
    // The first platform snapshot is still in flight when the provider is
    // switched to debugData. Applied late, it would also subscribe to the old
    // platform, whose events would then overwrite the simulated state.
    final _FakePlatform platform = _FakePlatform();
    final StreamController<FoldableData> feed =
        StreamController<FoldableData>.broadcast();
    addTearDown(feed.close);

    HingeStatus? status;
    Future<void> pump({Stream<FoldableData>? debugData}) => tester.pumpWidget(
      MaterialApp(
        home: FoldableProvider(
          platform: platform,
          debugData: debugData,
          child: Builder(
            builder: (BuildContext context) {
              status = DuoMediaQuery.statusOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await pump();
    await pump(debugData: feed.stream);
    platform.reply.complete(dataFor(HingeStatus.closed));
    await _push(tester, feed, HingeStatus.partiallyOpen);
    platform.controller.add(dataFor(HingeStatus.fullyOpen));
    await tester.pump();
    await tester.pump();

    expect(platform.controller.hasListener, isFalse);
    expect(status, HingeStatus.partiallyOpen);
  });
}

/// Pushes a snapshot and lets the resulting setState reach a build.
Future<void> _push(
  WidgetTester tester,
  StreamController<FoldableData> feed,
  HingeStatus status,
) async {
  feed.add(dataFor(status));
  await tester.pump();
  await tester.pump();
}

/// A platform whose snapshot reply the test releases by hand.
class _FakePlatform extends FoldablePlatform {
  final Completer<FoldableData> reply = Completer<FoldableData>();
  final StreamController<FoldableData> controller =
      StreamController<FoldableData>.broadcast();

  @override
  Future<FoldableData> getSnapshot() => reply.future;

  @override
  Stream<FoldableData> get events => controller.stream;
}
