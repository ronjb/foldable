## Unreleased

- **Vertical bar.** On iPhone Duo the status bar moves into a vertical bar
  along one side of the window. `FoldableData.verticalBarFrame` and
  `DuoMediaQuery.verticalBarFrameOf` give the part of it free for your own
  buttons, below the status bar and above the home indicator, as UIKit lays
  out a bar on that edge. `verticalBarEdge` and
  `DuoMediaQuery.verticalBarEdgeOf` say which edge it is on. Both are read
  through the Objective-C runtime, so older SDKs keep compiling.
- `FoldableProvider` also re-reads the platform when the safe area changes,
  since the vertical bar can come and go without the window resizing.
- **Example app:** example buttons in the vertical bar, tinted and labelled
  with the space available, and the cards no longer run under the status bar.

## 1.1.0

- **Requires Flutter 3.47 and Dart 3.13.** Flutter 3.47 also raises its own
  iOS minimum to 15.0, which the plugin already targeted. Apps on older
  Flutter versions keep resolving 1.0.5.
- **iOS: UIScene lifecycle.** The iOS 27 SDK requires the `UIScene` lifecycle
  for UIKit apps, so the plugin now also registers as a scene delegate and
  installs the hinge interaction from `sceneDidBecomeActive`. Apps that have
  not migrated keep working through the application delegate. The plugin
  also takes its Flutter view from `registrar.viewController` instead of
  searching the app's windows, which could pick another view in add-to-app
  or multi-scene apps.
- **Fixed:** `DuoMediaQuery.angleOf` missed slow folds. Its 0.5° threshold
  was measured from the previous reading, so a fold made of small steps
  never rebuilt the widgets reading it. `FoldableProvider` now measures the
  threshold from the last angle it published, and publishes the exact angle
  whenever the posture changes.
- **Fixed:** `FoldAwareBuilder` rebuilt on every hinge-angle update, despite
  being documented not to. It now rebuilds only for posture, regions, size
  classes and capabilities, and `FoldInfo.angleDegrees` is the angle as of
  the last rebuild.
- **Fixed:** `FoldInfo.divisionRects` and `spansDivision` included folds
  outside the builder, so a builder inside one pane reported the fold as
  crossing it. They now include only folds that overlap the builder, and they
  follow the builder when its scroll view scrolls.
- **Fixed:** only the first listener of `Foldable.changes`,
  `hingeAngleStream` or `hingeStatusStream` received the current snapshot.
  Because `FoldableProvider` usually listens first, a `StreamBuilder` on
  `hingeAngleStream` stayed empty until the hinge moved. Every listener now
  receives it.
- **Fixed:** with `debugData`, resizing the window replaced the simulated
  state with the platform's, and a platform snapshot that arrived after
  switching to `debugData` subscribed to the old platform anyway.
- **Fixed:** cancelling the last listener before the first snapshot arrived
  left native hinge events running, or, when a new listener arrived in time,
  subscribed to them twice.
- **Fixed (iOS):** on a foldable, a nil hinge, which iOS sends when the
  interaction leaves a hierarchy that provides hinge updates, was treated as
  "no hinge" and ended the event stream for the rest of the session.
- **Fixed (iOS):** the hinge interaction stayed on the old view when the
  Flutter view was replaced, event snapshots could read UIKit off the main
  thread, and `debugDumpNativeApi` leaked a small buffer.
- A channel field of the wrong type now falls back like a missing one instead
  of throwing, and a native plugin that speaks another wire version is
  reported in debug builds.
- **Docs:** iOS 15 throughout. `FoldableSupportLevel.unknown` means the
  platform has not yet settled whether there is a hinge, and
  `FoldableCapabilities.angleUnitVerified` is `true` whenever an angle is
  reported.
- **Example app:** moved to Swift Package Manager and `material_ui`, and no
  longer needs the `ARCHS = arm64` workaround for Xcode 27.1's `lipo`.

## 1.0.5

- **Fixed:** `FoldableProvider` subscribed to the event stream only when the
  first snapshot already reported a hinge. The platform reports the absence
  of a hinge only through a hinge update, so a first snapshot of
  `supportLevel: unknown` is legitimate, and when it arrived before that
  update the provider never listened again: later folds reached neither
  `DuoMediaQuery` nor `MediaQuery.displayFeatures`. The provider now
  subscribes unless support is definitively `unsupported`, the same rule
  `Foldable.changes` follows; on a device without a hinge the stream closes
  itself.

Thanks to @ohyeh for the report and the failing test, which is now part of
the suite ([#2](https://github.com/berkaycatak/foldable/issues/2)).

## 1.0.4

- README: a short pointer to `adaptive_platform_ui`, which builds on this
  package for the native iPhone Duo look. No code changes.

## 1.0.3

- The iOS plugin no longer re-reads the reserved regions on a timer. UIKit
  tracks a region read made during layout and runs layout again when that
  region changes, so the regions are now read from a view's `layoutSubviews`
  and the snapshot is emitted again on that pass. Measured on the iPhone Duo
  simulator, it follows every change of the fold division: about a second
  after the hinge reads partially open, and a millisecond or two after it
  reads fully open.
- No API changes.

## 1.0.2

- **Fixed:** a stale fold after laying the device flat. Reserved regions lag
  the hinge: inside the update handler the fold division still carries its
  pre-move `isActive`, and because the view's bounds do not change, no layout
  pass or further hinge update follows to correct it. With
  `DisplayFeatureBridgeMode.full` that left a 40pt `postureFlat` fold splitting
  every dialog on a flat device, and `FoldInfo.spansDivision` stayed `true`.
- The posture now decides: a fold is only published, and `FoldInfo` only
  reports a division, while the hinge reads `partiallyOpen`.
- The iOS plugin re-reads the regions after a hinge update until they agree
  with the hinge, for up to two seconds, and emits again, so
  `FoldableData.regions` settles too. Measured on the iPhone Duo simulator:
  flattening clears `isActive` 3 to 14 ms after the handler, folding sets it
  about a second later.
- **Fixed:** `FoldableProvider` inserted its `MediaQuery` only while it had
  display features to publish. That changed the shape of the widget tree, so
  each fold and unfold in `full` mode, and each change of `bridgeMode`,
  remounted everything below the provider and discarded scroll positions and
  `State`. The `MediaQuery` is now always present.
- **Docs:** the inactive division keeps its 40pt frame rather than collapsing
  to zero width.

Reported by @erkamyaman.

## 1.0.1

- Adds pub.dev screenshots: a still of the example app on a partially folded
  iPhone Duo, which becomes the package thumbnail, and the fold/unfold
  recording. No code changes.

## 1.0.0

First stable release. The native layer is now written against the real iOS 27.1
SDK headers and both code paths are verified on the iPhone Duo simulator, so the
API is settled enough to commit to: anything breaking from here waits for 2.0.0.

The hinge APIs shipped differently from what the Tech Talks implied, so the
native layer was rewritten against the real headers.

- **Fixed:** the runtime path never worked. `UIHingeInteraction.init` is
  unavailable, the only initialiser is `initWithUpdateHandler:`, the hinge
  arrives on the update rather than the interaction, and `UIHingeStatus` raw
  values start at 1. Reserved regions take a `UIViewReservedRegionKind` object,
  not an enum. All four are corrected and confirmed on device.
- `hinge.angle` is documented as radians and reads 0 when folded shut, so
  `angleUnitVerified` now reports `true`.
- Both code paths are exercised on the simulator and report identical readings:
  the Objective-C runtime path, and the typed path behind `FOLDABLE_NATIVE_API`
  now that the real types exist.
- A device reports the absence of a hinge only through an update, so
  `supportLevel` can legitimately be `unknown` for a moment. Dart keeps the
  stream open until the answer settles rather than closing on the first
  snapshot.
- **Breaking for the platform interface only:** `HingeSource.hasHinge` is now
  `Bool?`. The Dart API is unchanged.
- Minimum deployment target is now **iOS 15.0**, the lowest Xcode 27.1 accepts.
- README documents the two Flutter 3.44 / Xcode 27.1 build problems and their
  workarounds, and the measured inner display geometry: 951x669pt with a 40pt
  fold division.

## 0.2.0

Adds the iOS size class bridge, and corrects the reserved-region documentation
against Apple's published Tech Talk material.

- **New:** `SizeClass` (`compact` / `regular` / `unspecified`), bridged from
  `traitCollection` and exposed through `FoldableData.horizontalSizeClass`,
  `DuoMediaQuery.horizontalSizeClassOf`, and `FoldInfo.isRegularWidth`. This is
  the signal iOS lays out from, and unlike a width breakpoint it tracks Split
  View, where the class changes without the device folding. Reported on every
  iOS device, so it is useful when `isFoldable` is false.
- `FoldableProvider` now re-reads the snapshot when the window changes shape,
  so size classes stay current without a hinge to drive the event stream.
- `DuoMediaQuery` gains a `sizeClass` aspect, so posture readers are not
  rebuilt when only the size class changes.
- **Docs:** an occlusion region is active only while that camera is in use, and
  the fold division only while the device is folded. Both were already handled
  correctly in code through `isActive`; only the documentation was misleading.
- **Docs:** an app must be built against the iOS 27.1 SDK for reserved regions
  to exist at all. Hinge angle and posture are unaffected.
- **Docs:** note Apple's iOS 27.1 Arrangements API and why this package does
  not mirror it.

No breaking changes. Hinge readings remain unverified against physical
hardware; `FoldableCapabilities.angleUnitVerified` still reports `false`.

## 0.1.0

First release, published ahead of the iPhone Duo's 23 October 2026 launch.

- `Foldable.isFoldable`, `hingeAngleStream` (degrees), `hingeStatusStream`,
  `hingeStatus`, `snapshot`, `changes` and `capabilities`.
- `HingeStatus`: `closed` / `partiallyOpen` / `fullyOpen` / `unknown`,
  following Apple's own terminology.
- `FoldableProvider` + `DuoMediaQuery` (an `InheritedModel`, so the posture and
  the continuously changing angle rebuild independently) and `FoldAwareBuilder`.
- Opt-in `MediaQuery.displayFeatures` bridging via `DisplayFeatureBridgeMode`,
  **off by default**, with invariants that prevent an accidental layout split.
  See flutter/flutter#192515.
- iOS implementation resolves the iOS 27.1 hinge APIs through the Objective-C
  runtime, so the package compiles on older SDKs at an iOS 13.0 deployment
  target and no-ops safely on devices without a hinge.
- `Foldable.debugDumpNativeApi()` for confirming the real API shape on
  hardware.

Hinge readings have not been verified against a physical device;
`FoldableCapabilities.angleUnitVerified` reports `false` until they are.
