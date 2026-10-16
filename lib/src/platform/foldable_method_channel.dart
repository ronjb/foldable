import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/foldable_capabilities.dart';
import '../model/foldable_data.dart';
import 'foldable_codec.dart';
import 'foldable_platform.dart';

/// Channel names shared with the iOS plugin.
const String kFoldableMethodChannel = 'foldable/methods';

/// The event channel carrying state snapshots.
const String kFoldableEventChannel = 'foldable/events';

/// The default [FoldablePlatform], talking to the iOS plugin over channels.
class MethodChannelFoldable extends FoldablePlatform {
  /// The method channel used for one-shot queries.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    kFoldableMethodChannel,
  );

  /// The event channel carrying state changes.
  @visibleForTesting
  final EventChannel eventChannel = const EventChannel(kFoldableEventChannel);

  Stream<FoldableData>? _events;

  @override
  Future<FoldableData> getSnapshot() async {
    try {
      final Map<Object?, Object?>? raw = await methodChannel
          .invokeMapMethod<Object?, Object?>('getSnapshot');
      return FoldableCodec.decodeSnapshot(raw);
    } on MissingPluginException {
      // Plugin not registered: another platform, or a hot-restart race.
      return FoldableData.unsupported;
    } on PlatformException {
      return FoldableData.unsupported;
    }
  }

  @override
  Stream<FoldableData> get events => _events ??= _createEventStream();

  /// Builds the broadcast stream.
  ///
  /// Capability detection happens through [getSnapshot] rather than the event
  /// channel, because `EventChannel` reports activation failures via
  /// `FlutterError.reportError` instead of the stream. A listener would
  /// otherwise get no data, no error and no done, and hang forever.
  ///
  /// On a device without a hinge the controller closes without emitting, which
  /// is the "empty stream" contract: consumers get a clean `onDone`.
  Stream<FoldableData> _createEventStream() {
    late final StreamController<FoldableData> controller;
    StreamSubscription<dynamic>? subscription;
    FoldableData? latest;

    void emit(FoldableData data) {
      latest = data;
      controller.add(data);
    }

    Future<void> start() async {
      final FoldableData snapshot = await getSnapshot();
      // While the snapshot was in flight the last listener may have left, or
      // a later start() may already have subscribed. Subscribing anyway would
      // leave the platform streaming to nobody, or streaming twice.
      if (controller.isClosed ||
          !controller.hasListener ||
          subscription != null) {
        return;
      }

      // A device only reveals that it has no hinge through an update, so the
      // platform answers `unknown` until the first one lands. Closing on that
      // would mean never finding out. Only a settled answer closes the stream.
      if (!snapshot.isFoldable &&
          snapshot.capabilities.supportLevel != FoldableSupportLevel.unknown) {
        await controller.close();
        return;
      }

      emit(snapshot);

      subscription = eventChannel.receiveBroadcastStream().listen(
        (Object? event) {
          if (event is Map && !controller.isClosed) {
            emit(FoldableCodec.decodeSnapshot(event.cast<Object?, Object?>()));
          }
        },
        onError: (Object error, StackTrace stack) {
          // A native hiccup must not tear down every consumer.
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'foldable',
              context: ErrorDescription('while receiving hinge events'),
            ),
          );
        },
        onDone: () {
          if (!controller.isClosed) controller.close();
        },
      );
    }

    controller = StreamController<FoldableData>.broadcast(
      onListen: () {
        unawaited(start());
      },
      onCancel: () async {
        await subscription?.cancel();
        subscription = null;
        latest = null;
      },
    );

    // Replay the current state to every listener, so a late one is not left
    // blank until the hinge next moves. The controller's onListen only runs
    // for the first listener, so the replay happens here instead.
    return Stream<FoldableData>.multi((
      MultiStreamController<FoldableData> listener,
    ) {
      final FoldableData? current = latest;
      if (current != null) listener.add(current);
      final StreamSubscription<FoldableData> forwarding = controller.stream
          .listen(
            listener.add,
            onError: listener.addError,
            onDone: listener.close,
          );
      listener.onCancel = forwarding.cancel;
    }, isBroadcast: true);
  }

  /// Drops the cached stream so a test can start from a clean slate.
  void debugReset() {
    _events = null;
  }

  @override
  Future<Map<String, Object?>> debugDumpNativeApi() async {
    try {
      final Map<String, Object?>? raw = await methodChannel
          .invokeMapMethod<String, Object?>('debugDumpNativeApi');
      return raw ?? const <String, Object?>{};
    } on MissingPluginException {
      return const <String, Object?>{'error': 'plugin not registered'};
    } on PlatformException catch (e) {
      return <String, Object?>{'error': e.message ?? e.code};
    }
  }
}
