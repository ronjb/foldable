import 'dart:async';
import 'dart:ui' show DisplayFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../bridge/display_feature_bridge.dart';
import '../model/foldable_capabilities.dart';
import '../model/foldable_data.dart';
import '../platform/foldable_platform.dart';
import 'duo_media_query.dart';

/// Feeds fold state into the widget tree.
///
/// Place it above the widgets that need fold information, typically around
/// `MaterialApp`, or around the screen that adapts.
///
/// ```dart
/// FoldableProvider(
///   child: MaterialApp(home: HomePage()),
/// )
/// ```
class FoldableProvider extends StatefulWidget {
  /// Creates a provider.
  const FoldableProvider({
    super.key,
    required this.child,
    this.bridgeMode = DisplayFeatureBridgeMode.none,
    this.platform,
    this.debugData,
  });

  /// The subtree that can read fold state.
  final Widget child;

  /// Whether fold geometry is also published to `MediaQuery.displayFeatures`.
  ///
  /// Defaults to [DisplayFeatureBridgeMode.none], which leaves framework
  /// behaviour untouched.
  ///
  /// Turning this to [DisplayFeatureBridgeMode.full] makes Flutter confine
  /// dialogs, bottom sheets, popup menus and pickers to one side of the fold,
  /// roughly half of the 7.6" inner display. Measure your app before enabling
  /// it. See https://github.com/flutter/flutter/issues/192515.
  final DisplayFeatureBridgeMode bridgeMode;

  /// Overrides the platform implementation, for tests.
  final FoldablePlatform? platform;

  /// Drives the provider from a stream instead of the platform, for tests and
  /// for the example app's on-device simulator panel.
  final Stream<FoldableData>? debugData;

  @override
  State<FoldableProvider> createState() => _FoldableProviderState();
}

class _FoldableProviderState extends State<FoldableProvider> {
  FoldableData _data = FoldableData.unsupported;
  List<DisplayFeature> _features = const <DisplayFeature>[];
  StreamSubscription<FoldableData>? _subscription;
  AppLifecycleListener? _lifecycle;
  bool _warnedAboutUpstream = false;
  Size? _lastSize;
  EdgeInsets? _lastViewPadding;

  /// Identifies the current [_start], so that a platform reply arriving after
  /// the provider switched to another platform or to [FoldableProvider.debugData]
  /// is dropped instead of overwriting the new source.
  Object? _session;

  FoldablePlatform get _platform =>
      widget.platform ?? FoldablePlatform.instance;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Size classes change without the hinge moving: entering Split View,
    // rotating, or opening the device. The event stream only runs on hardware
    // that has a hinge, so the window size is what tells us to re-read them.
    // The vertical bar can come and go without the size changing, but not
    // without the safe area changing.
    final Size size = MediaQuery.sizeOf(context);
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    if (_lastSize != null &&
        (size != _lastSize || viewPadding != _lastViewPadding)) {
      _refresh();
    }
    _lastSize = size;
    _lastViewPadding = viewPadding;
  }

  @override
  void didUpdateWidget(FoldableProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.platform != oldWidget.platform ||
        widget.debugData != oldWidget.debugData) {
      _stop();
      _start();
    } else if (widget.bridgeMode != oldWidget.bridgeMode) {
      _apply(_data);
    }
  }

  void _start() {
    final Object session = _session = Object();
    if (widget.debugData != null) {
      _subscription = widget.debugData!.listen(_apply);
      return;
    }

    // Capability detection goes through the one-shot query, never the stream:
    // EventChannel swallows activation failures, so a silent stream cannot be
    // told apart from a missing plugin.
    unawaited(
      _platform.getSnapshot().then((FoldableData snapshot) {
        if (!mounted || session != _session) return;
        _apply(snapshot);
        // The platform reports the absence of a hinge only through a hinge
        // update, so the first snapshot may still be `unknown`. Subscribe
        // unless support is definitively absent; on a device without a
        // hinge the stream closes itself once that is settled, and size
        // classes still arrive, refreshed from didChangeDependencies when
        // the window changes shape.
        if (snapshot.capabilities.supportLevel ==
            FoldableSupportLevel.unsupported) {
          return;
        }
        _subscription = _platform.events.listen(_apply);
        _lifecycle = AppLifecycleListener(onResume: _refresh);
      }),
    );
  }

  void _stop() {
    _subscription?.cancel();
    _subscription = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  void _refresh() {
    // Simulated state must not be overwritten by the real platform's.
    if (widget.debugData != null) return;

    final Object? session = _session;
    unawaited(
      _platform.getSnapshot().then((FoldableData snapshot) {
        if (mounted && session == _session) _apply(snapshot);
      }),
    );
  }

  void _apply(FoldableData next) {
    final List<DisplayFeature> features = DisplayFeatureBridge.build(
      mode: _effectiveBridgeMode,
      regions: next.regions,
      status: next.status,
    );

    setState(() {
      // Keep the previous list instance when the contents are unchanged.
      // MediaQuery compares its display feature list by identity, so handing
      // it a fresh equal list every frame would rebuild every dependent.
      if (!listEquals(features, _features)) {
        _features = features;
      }
      _data = next.copyWith(
        displayFeatures: _features,
        angleDegrees: _publishedAngle(next),
      );
    });
  }

  /// The angle to publish for [next].
  ///
  /// Holds the last published angle until the new one moves more than
  /// [DuoMediaQuery.angleRebuildThresholdDegrees] away from it, so angle
  /// readers are not rebuilt by jitter. The threshold is measured from what
  /// was published, not from the previous reading, so a slow fold made of many
  /// small steps still gets through. A posture change always publishes the
  /// exact angle, keeping the two consistent.
  double? _publishedAngle(FoldableData next) {
    final double? published = _data.angleDegrees;
    final double? angle = next.angleDegrees;
    if (angle == null || published == null || next.status != _data.status) {
      return angle;
    }
    return (angle - published).abs() >
            DuoMediaQuery.angleRebuildThresholdDegrees
        ? angle
        : published;
  }

  /// The bridge mode actually in force.
  ///
  /// Falls back to [DisplayFeatureBridgeMode.none] once Flutter itself starts
  /// reporting display features on iOS, so the fold is never published twice.
  DisplayFeatureBridgeMode get _effectiveBridgeMode => _upstreamProvidesFeatures
      ? DisplayFeatureBridgeMode.none
      : widget.bridgeMode;

  bool get _upstreamProvidesFeatures {
    if (!mounted) return false;
    // Reads the raw FlutterView, not our own MediaQuery override, so we never
    // mistake our own output for the engine's.
    return View.of(context).displayFeatures.isNotEmpty;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bridgeMode != DisplayFeatureBridgeMode.none &&
        _upstreamProvidesFeatures) {
      _warnAboutUpstreamOnce();
    }

    // The MediaQuery is always present, even with nothing to publish, so the
    // shape of the tree never changes. Inserting it only while there were
    // features remounted everything below on each fold and each change of
    // bridge mode, discarding scroll positions and State.
    final MediaQueryData ambient = MediaQuery.of(context);
    return MediaQuery(
      data: _features.isEmpty
          ? ambient
          : ambient.copyWith(displayFeatures: _features),
      child: DuoMediaQuery(data: _data, child: widget.child),
    );
  }

  void _warnAboutUpstreamOnce() {
    if (_warnedAboutUpstream) return;
    _warnedAboutUpstream = true;
    assert(() {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError(
            'foldable: Flutter now reports display features on this platform, '
            'so bridgeMode was ignored to avoid publishing the fold twice.',
          ),
          library: 'foldable',
        ),
      );
      return true;
    }());
  }
}
