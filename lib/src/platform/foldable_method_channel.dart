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

/// The event channel carrying layout snapshots.
const String kFoldableLayoutChannel = 'foldable/layout';

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

  /// The event channel carrying layout changes.
  @visibleForTesting
  final EventChannel layoutChannel = const EventChannel(kFoldableLayoutChannel);

  Stream<FoldableData>? _events;
  Stream<FoldableData>? _layoutChanges;

  /// Whether the last [getSnapshot] found no plugin to answer it.
  bool _pluginMissing = false;

  @override
  Future<FoldableData> getSnapshot() async {
    try {
      final Map<Object?, Object?>? raw = await methodChannel
          .invokeMapMethod<Object?, Object?>('getSnapshot');
      _pluginMissing = false;
      assert(() {
        _debugCheckWireVersion(raw?['wireVersion']);
        return true;
      }());
      return FoldableCodec.decodeSnapshot(raw);
    } on MissingPluginException {
      // Plugin not registered: another platform, or a hot-restart race.
      _pluginMissing = true;
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

  @override
  Stream<FoldableData> get layoutChanges =>
      _layoutChanges ??= _createLayoutStream();

  /// Builds the broadcast stream of layout changes.
  ///
  /// Listening to an `EventChannel` with no plugin behind it reports a
  /// `MissingPluginException` through `FlutterError.reportError`, out of the
  /// stream's reach, which fails the widget tests of an app that targets iOS
  /// without the plugin. So, as for [events], the method channel is asked
  /// first, and the layout channel is only listened to once the plugin has
  /// answered.
  Stream<FoldableData> _createLayoutStream() {
    // Only the iOS plugin has the channel.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const Stream<FoldableData>.empty();
    }

    late final StreamController<FoldableData> controller;
    StreamSubscription<Object?>? subscription;

    Future<void> start() async {
      await getSnapshot();
      // While the snapshot was in flight the last listener may have left, or
      // a later start() may already have subscribed.
      if (_pluginMissing || !controller.hasListener || subscription != null) {
        return;
      }
      subscription = layoutChannel.receiveBroadcastStream().listen(
        (Object? event) {
          if (event is Map) {
            controller.add(
              FoldableCodec.decodeSnapshot(event.cast<Object?, Object?>()),
            );
          }
        },
        onError: (Object error, StackTrace stack) {
          // A native hiccup must not tear down every consumer.
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'foldable',
              context: ErrorDescription('while receiving layout events'),
            ),
          );
        },
      );
    }

    controller = StreamController<FoldableData>.broadcast(
      onListen: () => unawaited(start()),
      onCancel: () {
        unawaited(subscription?.cancel());
        subscription = null;
      },
    );

    // The plugin sends the current layout only when the channel is first
    // listened to, so a later listener is sent a fresh snapshot. The last
    // event would not do: an iPad's size classes change with its window
    // without a layout event. The plugin answers and sends events in order,
    // so the snapshot is never older than an event that arrives before it.
    return Stream<FoldableData>.multi((
      MultiStreamController<FoldableData> listener,
    ) {
      if (subscription != null) unawaited(getSnapshot().then(listener.add));
      final StreamSubscription<FoldableData> forwarding = controller.stream
          .listen(
            listener.add,
            onError: listener.addError,
            onDone: listener.close,
          );
      listener.onCancel = forwarding.cancel;
    }, isBroadcast: true);
  }

  /// Drops the cached streams so a test can start from a clean slate.
  void debugReset() {
    _events = null;
    _layoutChanges = null;
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

  /// Reports a native plugin that speaks another wire version, which happens
  /// when a hot restart runs this Dart code against native code from another
  /// version of the package. Decoding carries on regardless.
  static void _debugCheckWireVersion(Object? version) {
    if (version == null || version == FoldableCodec.wireVersion) return;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError(
          'foldable: the iOS plugin speaks wire version $version, but this '
          'Dart code speaks ${FoldableCodec.wireVersion}. Rebuild the app so '
          'both come from the same version of the package.',
        ),
        library: 'foldable',
      ),
    );
  }
}
