import 'package:flutter/foundation.dart';

import 'model/foldable_capabilities.dart';
import 'model/foldable_data.dart';
import 'model/hinge_status.dart';
import 'platform/foldable_method_channel.dart';
import 'platform/foldable_platform.dart';

/// The entry point for reading fold state outside the widget tree.
///
/// Inside a widget tree, prefer `DuoMediaQuery` / `FoldAwareBuilder`, which
/// rebuild only the parts of the tree that care.
abstract final class Foldable {
  /// Whether this device physically has a hinge.
  ///
  /// Returns `false` on every other platform and never throws.
  static Future<bool> get isFoldable async =>
      (await FoldablePlatform.instance.getSnapshot()).isFoldable;

  /// What the platform supports, plus diagnostics about how it was resolved.
  static Future<FoldableCapabilities> get capabilities async =>
      (await FoldablePlatform.instance.getSnapshot()).capabilities;

  /// The current fold posture, read once.
  static Future<HingeStatus> get hingeStatus async =>
      (await FoldablePlatform.instance.getSnapshot()).status;

  /// The full current state, read once.
  static Future<FoldableData> get snapshot =>
      FoldablePlatform.instance.getSnapshot();

  /// Every state change on a device with a hinge, as an atomic snapshot.
  ///
  /// It completes once the platform reports that the device has no hinge,
  /// which it does only through a hinge update. An iPad on iPadOS 27 never
  /// sends one, so there it stays open. The window's layout, such as an iPad's
  /// window controls, changes without a hinge too: [layoutChanges] carries
  /// those everywhere.
  static Stream<FoldableData> get changes => FoldablePlatform.instance.events;

  /// Every change of the window's layout, as an atomic snapshot: a reserved
  /// region, the vertical bar, the top bar, or an iPad's window controls.
  ///
  /// Unlike [changes], it never completes on iOS. It is empty on other
  /// platforms.
  static Stream<FoldableData> get layoutChanges =>
      FoldablePlatform.instance.layoutChanges;

  /// The continuous hinge angle in **degrees**: 0° closed, 180° flat.
  ///
  /// On a device that the platform reports has no hinge, this completes
  /// without emitting, so a `StreamBuilder` lands on [ConnectionState.done]
  /// rather than waiting forever. An iPad on iPadOS 27 never sends that
  /// report, so there it stays open without emitting.
  ///
  /// Apple's guidance is to drive effects and interactions from the raw angle,
  /// not layout. Use [changes] or `FoldAwareBuilder` for layout decisions.
  static Stream<double> get hingeAngleStream => FoldablePlatform.instance.events
      .map((FoldableData d) => d.angleDegrees)
      .where((double? a) => a != null)
      .cast<double>();

  /// Fold posture changes, emitted only when the posture actually changes.
  static Stream<HingeStatus> get hingeStatusStream => FoldablePlatform
      .instance
      .events
      .map((FoldableData d) => d.status)
      .distinct();

  /// Dumps the Objective-C runtime shape of the hinge APIs on the device.
  ///
  /// Apple has not published reference documentation for `UIHingeInteraction`,
  /// so this is how the real selectors and delegate signatures get confirmed.
  /// Debug aid only. Do not ship logic that depends on its shape.
  static Future<Map<String, Object?>> debugDumpNativeApi() =>
      FoldablePlatform.instance.debugDumpNativeApi();

  /// Clears cached platform state so a test can start clean.
  @visibleForTesting
  static void debugReset() {
    final FoldablePlatform platform = FoldablePlatform.instance;
    if (platform is MethodChannelFoldable) {
      platform.debugReset();
    }
  }
}
