import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

const StandardMethodCodec codec = StandardMethodCodec();

Map<String, Object?> payload({
  required bool isFoldable,
  String status = 'partiallyOpen',
  Object? angle = 97.4,
}) => <String, Object?>{
  'wireVersion': 1,
  'supportLevel': isFoldable ? 'available' : 'unsupported',
  'isFoldable': isFoldable,
  'hingeApiPresent': isFoldable,
  'regionApiPresent': isFoldable,
  'angleUnitVerified': false,
  'strategy': isFoldable ? 'interactionKVO' : 'none',
  'status': status,
  'angleDegrees': angle,
  'regions': const <Object?>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late MethodChannelFoldable platform;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    platform = MethodChannelFoldable();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(kFoldableMethodChannel),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(kFoldableEventChannel),
      null,
    );
  });

  void mockMethods(Map<String, Object?>? snapshot) {
    messenger.setMockMethodCallHandler(
      const MethodChannel(kFoldableMethodChannel),
      (MethodCall call) async => call.method == 'getSnapshot' ? snapshot : null,
    );
  }

  /// Accepts the EventChannel's `listen`/`cancel` handshake.
  void mockEventHandshake() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(kFoldableEventChannel),
      (MethodCall call) async => null,
    );
  }

  /// Holds every snapshot reply until [reply] completes, and records the
  /// EventChannel handshake so a test can see whether native events started.
  List<String> mockSlowSnapshot(Completer<Object?> reply) {
    final List<String> handshake = <String>[];
    messenger
      ..setMockMethodCallHandler(
        const MethodChannel(kFoldableMethodChannel),
        (MethodCall call) => reply.future,
      )
      ..setMockMethodCallHandler(const MethodChannel(kFoldableEventChannel), (
        MethodCall call,
      ) async {
        handshake.add(call.method);
        return null;
      });
    return handshake;
  }

  Future<void> emit(Map<String, Object?> event) =>
      messenger.handlePlatformMessage(
        kFoldableEventChannel,
        codec.encodeSuccessEnvelope(event),
        (_) {},
      );

  /// A `null` reply is how the platform signals FlutterEndOfEventStream.
  Future<void> endStream() =>
      messenger.handlePlatformMessage(kFoldableEventChannel, null, (_) {});

  group('getSnapshot', () {
    test('decodes a platform response', () async {
      mockMethods(payload(isFoldable: true));
      final FoldableData data = await platform.getSnapshot();

      expect(data.isFoldable, isTrue);
      expect(data.status, HingeStatus.partiallyOpen);
      expect(data.angleDegrees, 97.4);
      expect(data.capabilities.strategy, 'interactionKVO');
    });

    test('MissingPluginException yields unsupported, never throws', () async {
      // No handler registered at all.
      await expectLater(platform.getSnapshot(), completion(isNotNull));
      expect(await platform.getSnapshot(), FoldableData.unsupported);
    });

    test('PlatformException yields unsupported', () async {
      messenger.setMockMethodCallHandler(
        const MethodChannel(kFoldableMethodChannel),
        (MethodCall call) async => throw PlatformException(code: 'boom'),
      );
      expect(await platform.getSnapshot(), FoldableData.unsupported);
    });

    test('null response yields unsupported', () async {
      mockMethods(null);
      expect(await platform.getSnapshot(), FoldableData.unsupported);
    });

    test('a native wire version mismatch is reported, not fatal', () async {
      mockMethods(<String, Object?>{
        ...payload(isFoldable: true),
        'wireVersion': 2,
      });
      final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
      final FlutterExceptionHandler? previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      final FoldableData data = await platform.getSnapshot();

      expect(data.isFoldable, isTrue);
      expect(errors.single.exception.toString(), contains('wire version 2'));
    });
  });

  group('empty stream contract', () {
    test('non-foldable device completes without emitting', () async {
      mockMethods(payload(isFoldable: false, angle: null));

      final List<FoldableData> received = <FoldableData>[];
      bool done = false;
      platform.events.listen(received.add, onDone: () => done = true);

      await pumpEventQueue();

      expect(received, isEmpty, reason: 'a hinge-less device emitted data');
      expect(done, isTrue, reason: 'stream must close, not hang');
    });

    test('missing plugin completes without emitting', () async {
      bool done = false;
      platform.events.listen((_) {}, onDone: () => done = true);
      await pumpEventQueue();
      expect(done, isTrue);
    });

    test('hingeAngleStream is empty on a non-foldable device', () async {
      mockMethods(payload(isFoldable: false, angle: null));
      FoldablePlatform.instance = platform;
      addTearDown(Foldable.debugReset);

      expect(await Foldable.hingeAngleStream.toList(), isEmpty);
    });
  });

  group('foldable device', () {
    test('replays the current snapshot to a new listener', () async {
      mockMethods(payload(isFoldable: true));
      mockEventHandshake();

      final List<FoldableData> received = <FoldableData>[];
      platform.events.listen(received.add);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.angleDegrees, 97.4);
    });

    test('a later listener also receives the current snapshot', () async {
      mockMethods(payload(isFoldable: true));
      mockEventHandshake();

      platform.events.listen((_) {});
      await pumpEventQueue();

      final List<FoldableData> later = <FoldableData>[];
      platform.events.listen(later.add);
      await pumpEventQueue();

      expect(later, hasLength(1));
      expect(later.single.angleDegrees, 97.4);
    });

    test('a listener that leaves before the snapshot starts nothing', () async {
      final Completer<Object?> reply = Completer<Object?>();
      final List<String> handshake = mockSlowSnapshot(reply);

      final StreamSubscription<FoldableData> early = platform.events.listen(
        (_) {},
      );
      await pumpEventQueue();
      await early.cancel();
      reply.complete(payload(isFoldable: true));
      await pumpEventQueue();

      expect(handshake, isEmpty);
    });

    test(
      'a listener replacing one that left subscribes natively once',
      () async {
        final Completer<Object?> reply = Completer<Object?>();
        final List<String> handshake = mockSlowSnapshot(reply);

        final StreamSubscription<FoldableData> early = platform.events.listen(
          (_) {},
        );
        await pumpEventQueue();
        await early.cancel();
        final List<FoldableData> received = <FoldableData>[];
        platform.events.listen(received.add);
        await pumpEventQueue();
        reply.complete(payload(isFoldable: true));
        await pumpEventQueue();

        expect(handshake, <String>['listen']);
        expect(received, hasLength(1));
      },
    );

    test('forwards live events after the replay', () async {
      mockMethods(payload(isFoldable: true));
      mockEventHandshake();

      final List<double?> angles = <double?>[];
      platform.events.listen((FoldableData d) => angles.add(d.angleDegrees));
      await pumpEventQueue();

      await emit(payload(isFoldable: true, angle: 120.0));
      await emit(payload(isFoldable: true, angle: 180.0));
      await pumpEventQueue();

      expect(angles, <double>[97.4, 120.0, 180.0]);
    });

    test('an integer angle from the wire does not throw', () async {
      mockMethods(payload(isFoldable: true));
      mockEventHandshake();

      final List<double?> angles = <double?>[];
      platform.events.listen((FoldableData d) => angles.add(d.angleDegrees));
      await pumpEventQueue();

      await emit(payload(isFoldable: true, angle: 90));
      await pumpEventQueue();

      expect(angles.last, 90.0);
    });

    test('platform end-of-stream closes the Dart stream', () async {
      mockMethods(payload(isFoldable: true));
      mockEventHandshake();

      bool done = false;
      platform.events.listen((_) {}, onDone: () => done = true);
      await pumpEventQueue();
      expect(done, isFalse);

      await endStream();
      await pumpEventQueue();
      expect(done, isTrue);
    });
  });

  group('derived streams', () {
    test('hingeAngleStream skips null angles', () async {
      mockMethods(payload(isFoldable: true, angle: null));
      mockEventHandshake();
      FoldablePlatform.instance = platform;
      addTearDown(Foldable.debugReset);

      final List<double> angles = <double>[];
      Foldable.hingeAngleStream.listen(angles.add);
      await pumpEventQueue();

      await emit(payload(isFoldable: true, angle: null));
      await emit(payload(isFoldable: true, angle: 45.0));
      await pumpEventQueue();

      expect(angles, <double>[45.0]);
    });

    test('hingeStatusStream emits only on posture change', () async {
      mockMethods(payload(isFoldable: true, status: 'partiallyOpen'));
      mockEventHandshake();
      FoldablePlatform.instance = platform;
      addTearDown(Foldable.debugReset);

      final List<HingeStatus> statuses = <HingeStatus>[];
      Foldable.hingeStatusStream.listen(statuses.add);
      await pumpEventQueue();

      // Angle sweeps at a constant posture must not produce events.
      await emit(
        payload(isFoldable: true, status: 'partiallyOpen', angle: 100.0),
      );
      await emit(
        payload(isFoldable: true, status: 'partiallyOpen', angle: 140.0),
      );
      await emit(payload(isFoldable: true, status: 'fullyOpen', angle: 180.0));
      await pumpEventQueue();

      expect(statuses, <HingeStatus>[
        HingeStatus.partiallyOpen,
        HingeStatus.fullyOpen,
      ]);
    });
  });
}
