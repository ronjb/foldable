import 'dart:ui' show Rect;

import '../model/foldable_capabilities.dart';
import '../model/foldable_data.dart';
import '../model/hinge_status.dart';
import '../model/reserved_region.dart';
import '../model/size_class.dart';
import '../model/vertical_bar_edge.dart';

/// Decodes platform channel payloads into models.
///
/// Every field is read defensively: one of the wrong type falls back like a
/// missing one instead of throwing. The standard method codec transmits whole
/// numbers as integers, so an angle that happens to land on exactly 90 arrives
/// as `int`, hence numbers are read as `num` and converted.
abstract final class FoldableCodec {
  /// The wire schema version this package speaks.
  static const int wireVersion = 1;

  /// Decodes a snapshot payload. Returns [FoldableData.unsupported] for
  /// `null`, and safe defaults for missing or mistyped fields, rather than
  /// throwing.
  static FoldableData decodeSnapshot(Map<Object?, Object?>? raw) {
    if (raw == null) return FoldableData.unsupported;

    return FoldableData(
      capabilities: FoldableCapabilities(
        supportLevel: FoldableSupportLevel.fromWire(raw['supportLevel']),
        isFoldable: _bool(raw['isFoldable']),
        hingeApiPresent: _bool(raw['hingeApiPresent']),
        regionApiPresent: _bool(raw['regionApiPresent']),
        angleUnitVerified: _bool(raw['angleUnitVerified']),
        strategy: switch (raw['strategy']) {
          final String strategy => strategy,
          _ => 'none',
        },
      ),
      status: HingeStatus.fromWire(raw['status']),
      angleDegrees: _double(raw['angleDegrees']),
      regions: _regions(raw['regions']),
      horizontalSizeClass: SizeClass.fromWire(raw['horizontalSizeClass']),
      verticalSizeClass: SizeClass.fromWire(raw['verticalSizeClass']),
      verticalBarEdge: VerticalBarEdge.fromWire(raw['verticalBarEdge']),
      verticalBarFrame: _rect(raw['verticalBar']) ?? Rect.zero,
      // Bridging is a pure-Dart decision; the platform never supplies these.
      displayFeatures: const [],
    );
  }

  static List<ReservedRegion> _regions(Object? raw) {
    if (raw is! List) return const <ReservedRegion>[];

    final List<ReservedRegion> out = <ReservedRegion>[];
    for (final Object? entry in raw) {
      if (entry is! Map) continue;
      final Rect? bounds = _rect(entry);
      if (bounds == null) continue;
      out.add(
        ReservedRegion(
          kind: ReservedRegionKind.fromWire(entry['kind']),
          bounds: bounds,
          isActive: _bool(entry['active']),
        ),
      );
    }
    return List<ReservedRegion>.unmodifiable(out);
  }

  /// Decodes a `left`/`top`/`width`/`height` map, or `null` when it is not
  /// one.
  static Rect? _rect(Object? raw) {
    if (raw is! Map) return null;
    final double? left = _double(raw['left']);
    final double? top = _double(raw['top']);
    final double? width = _double(raw['width']);
    final double? height = _double(raw['height']);
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    // Points map 1:1 to logical pixels on iOS, so no scaling.
    return Rect.fromLTWH(left, top, width, height);
  }

  static bool _bool(Object? value) => value is bool ? value : false;

  static double? _double(Object? value) =>
      value is num ? value.toDouble() : null;
}
