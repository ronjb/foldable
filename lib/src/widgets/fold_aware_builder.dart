import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../model/foldable_data.dart';
import '../model/hinge_status.dart';
import '../model/reserved_region.dart';
import '../model/size_class.dart';
import 'duo_media_query.dart';

/// Fold state, with geometry translated into the builder's own coordinates.
@immutable
class FoldInfo {
  /// Creates fold information.
  const FoldInfo({
    required this.isFoldable,
    required this.status,
    required this.angleDegrees,
    required this.divisionRects,
    required this.occlusionRects,
    this.horizontalSizeClass = SizeClass.unspecified,
    this.verticalSizeClass = SizeClass.unspecified,
  });

  /// The value used when there is no fold information available.
  static const FoldInfo none = FoldInfo(
    isFoldable: false,
    status: HingeStatus.unknown,
    angleDegrees: null,
    divisionRects: <Rect>[],
    occlusionRects: <Rect>[],
  );

  /// Whether this device physically has a hinge.
  final bool isFoldable;

  /// The current fold posture.
  final HingeStatus status;

  /// The hinge angle in degrees, as of the builder's last rebuild.
  ///
  /// Angle changes alone do not rebuild a [FoldAwareBuilder]. For per-frame
  /// values use `Foldable.hingeAngleStream`.
  final double? angleDegrees;

  /// Active fold areas that overlap the builder, in its local coordinate
  /// space.
  final List<Rect> divisionRects;

  /// Active camera cutouts, in the builder's local coordinate space.
  final List<Rect> occlusionRects;

  /// The horizontal size class iOS reports for this window.
  ///
  /// Prefer this over a width breakpoint where it is available: it is what the
  /// system lays out from, and it accounts for Split View. Falls back to
  /// [SizeClass.unspecified] off iOS, where `constraints` remains the signal.
  final SizeClass horizontalSizeClass;

  /// The vertical size class iOS reports for this window.
  final SizeClass verticalSizeClass;

  /// Whether iOS considers this window wide.
  bool get isRegularWidth => horizontalSizeClass == SizeClass.regular;

  /// Whether the hinge rests between closed and flat.
  bool get isPartiallyOpen => status == HingeStatus.partiallyOpen;

  /// Whether the device is fully unfolded.
  bool get isFullyOpen => status == HingeStatus.fullyOpen;

  /// Whether the device is folded shut.
  bool get isClosed => status == HingeStatus.closed;

  /// Whether a fold currently crosses this builder's area.
  bool get spansDivision => divisionRects.any((Rect rect) => !rect.isEmpty);

  /// The first fold crossing this builder, if any.
  Rect? get divisionRect => divisionRects.isEmpty ? null : divisionRects.first;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoldInfo &&
          other.isFoldable == isFoldable &&
          other.status == status &&
          other.angleDegrees == angleDegrees &&
          other.horizontalSizeClass == horizontalSizeClass &&
          other.verticalSizeClass == verticalSizeClass &&
          listEquals(other.divisionRects, divisionRects) &&
          listEquals(other.occlusionRects, occlusionRects);

  @override
  int get hashCode => Object.hash(
    isFoldable,
    status,
    angleDegrees,
    horizontalSizeClass,
    verticalSizeClass,
    Object.hashAll(divisionRects),
    Object.hashAll(occlusionRects),
  );
}

/// Signature for [FoldAwareBuilder.builder].
typedef FoldAwareWidgetBuilder = Widget Function(
  BuildContext context,
  BoxConstraints constraints,
  FoldInfo fold,
);

/// Rebuilds when the fold posture or geometry changes.
///
/// Unlike [LayoutBuilder], which only reports box constraints, this also
/// reports *where* the fold falls and what posture the device is in. On the
/// iPhone Duo's 626x890pt inner display a plain [LayoutBuilder] cannot tell
/// an unfolded phone from a tablet of the same width.
///
/// The raw hinge angle deliberately does not drive rebuilds here. Apple's
/// guidance is to use the angle for effects and interactions, not layout. For
/// a continuously animated value, use `Foldable.hingeAngleStream` with a
/// `StreamBuilder` around just the widget that animates.
///
/// Works without a `FoldableProvider` above it: the builder simply receives
/// [FoldInfo.none].
class FoldAwareBuilder extends StatefulWidget {
  /// Creates a fold-aware builder.
  const FoldAwareBuilder({super.key, required this.builder});

  /// Builds the subtree from the constraints and fold state.
  final FoldAwareWidgetBuilder builder;

  @override
  State<FoldAwareBuilder> createState() => _FoldAwareBuilderState();
}

class _FoldAwareBuilderState extends State<FoldAwareBuilder> {
  Offset _origin = Offset.zero;
  ScrollPosition? _scrollPosition;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Scrolling moves this builder without rebuilding it, so its position is
    // also re-read whenever the enclosing scroll view scrolls.
    final ScrollPosition? position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.removeListener(_scheduleOriginSync);
      _scrollPosition = position?..addListener(_scheduleOriginSync);
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_scheduleOriginSync);
    super.dispose();
  }

  /// Re-reads this subtree's position once the current frame is laid out,
  /// when there is fold geometry for it to place.
  void _scheduleOriginSync() {
    final bool hasRegions =
        context
            .getInheritedWidgetOfExactType<DuoMediaQuery>()
            ?.data
            .regions
            .isNotEmpty ??
        false;
    if (hasRegions) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncOrigin());
    }
  }

  /// Re-reads this subtree's position after layout.
  ///
  /// Region bounds arrive in view coordinates, but the builder can sit
  /// anywhere in the tree; without this the fold would be drawn in the wrong
  /// place for any inset subtree.
  void _syncOrigin() {
    if (!mounted) return;
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final Offset origin = box.localToGlobal(Offset.zero);
    if (origin != _origin) setState(() => _origin = origin);
  }

  Iterable<Rect> _toLocal(
    List<ReservedRegion> regions,
    ReservedRegionKind kind,
  ) => regions
      .where((ReservedRegion r) => r.kind == kind && r.isActive)
      .map((ReservedRegion r) => r.bounds.shift(-_origin));

  @override
  Widget build(BuildContext context) {
    // Depends on every aspect but the angle, which would otherwise rebuild the
    // whole subtree on each hinge update. The angle is still read, as of this
    // build.
    DuoMediaQuery? scope;
    for (final FoldableAspect aspect in _layoutAspects) {
      scope = InheritedModel.inheritFrom<DuoMediaQuery>(
        context,
        aspect: aspect,
      );
    }
    final FoldableData data = scope?.data ?? FoldableData.unsupported;

    _scheduleOriginSync();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // A fold elsewhere on the screen does not cross this builder.
        final Rect area = Offset.zero & constraints.biggest;
        final FoldInfo fold = data.isFoldable
            ? FoldInfo(
                isFoldable: true,
                status: data.status,
                angleDegrees: data.angleDegrees,
                horizontalSizeClass: data.horizontalSizeClass,
                verticalSizeClass: data.verticalSizeClass,
                // Only while partially open: the region's isActive flag lags
                // the hinge and can stay true after the device has been laid
                // flat.
                divisionRects: data.status == HingeStatus.partiallyOpen
                    ? _toLocal(
                        data.regions,
                        ReservedRegionKind.division,
                      ).where(area.overlaps).toList(growable: false)
                    : const <Rect>[],
                occlusionRects: _toLocal(
                  data.regions,
                  ReservedRegionKind.occlusion,
                ).toList(growable: false),
              )
            : FoldInfo(
                isFoldable: false,
                status: HingeStatus.unknown,
                angleDegrees: null,
                divisionRects: const <Rect>[],
                occlusionRects: const <Rect>[],
                horizontalSizeClass: data.horizontalSizeClass,
                verticalSizeClass: data.verticalSizeClass,
              );
        return widget.builder(context, constraints, fold);
      },
    );
  }
}

/// The [DuoMediaQuery] aspects a [FoldAwareBuilder] rebuilds for.
const List<FoldableAspect> _layoutAspects = <FoldableAspect>[
  FoldableAspect.capabilities,
  FoldableAspect.status,
  FoldableAspect.regions,
  FoldableAspect.sizeClass,
];
