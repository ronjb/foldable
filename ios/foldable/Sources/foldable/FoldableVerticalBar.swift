import UIKit

/// The edge of the window where iOS places the vertical bar.
///
/// On iPhone Duo, apps built against the iOS 27.1 SDK get a vertical bar along
/// one side: the status bar turns vertical and moves into it, and the system
/// adds a leading or trailing safe area inset for it.
enum FoldableVerticalBarEdge: String {
  case leading
  case trailing
  case unspecified
}

/// Reads where the vertical bar sits, and the part of it free for bar content.
///
/// Both APIs arrived in the iOS 27.1 SDK, so they are reached through the
/// runtime like the hinge APIs, and older SDKs keep compiling.
enum FoldableVerticalBar {
  /// The edge `UITraitCollection.verticalBarEdge` reports for `view`.
  static func edge(for view: UIView?) -> FoldableVerticalBarEdge {
    guard let traits = view?.traitCollection,
      let raw = ObjCRuntimeSupport.value(from: traits, keyPath: "verticalBarEdge")
        as? NSNumber
    else { return .unspecified }
    switch raw.intValue {
    case 1: return .leading
    case 2: return .trailing
    default: return .unspecified
    }
  }

  /// The part of the vertical bar free for bar content, in `view`'s
  /// coordinates, or `.zero` while there is no vertical bar.
  ///
  /// This is where UIKit lays out a bar on that edge, as wide as the bar's
  /// safe area inset: below the status bar, above the home indicator, and
  /// centred on the status bar rather than on the inset.
  static func frame(in view: UIView?, edge: FoldableVerticalBarEdge) -> CGRect {
    guard let view = view, edge != .unspecified else { return .zero }
    let isLeft =
      (edge == .leading) == (view.effectiveUserInterfaceLayoutDirection == .leftToRight)
    let inset = isLeft ? view.safeAreaInsets.left : view.safeAreaInsets.right
    guard inset > 0 else { return .zero }

    // NSDirectionalRectEdge: leading is 1 << 1, trailing is 1 << 3.
    let directionalEdge: UInt = edge == .leading ? 1 << 1 : 1 << 3
    guard
      let region = ObjCRuntimeSupport.classObject(
        "UIViewLayoutRegion", "layoutRegionForBarOnDirectionalEdge:extent:",
        directionalEdge, inset),
      let insets = ObjCRuntimeSupport.edgeInsets(
        of: view, selector: NSSelectorFromString("edgeInsetsForLayoutRegion:"),
        object: region)
    else { return .zero }
    let frame = view.bounds.inset(by: insets)

    // A bar too thick for the vertical bar is laid out inside the safe area
    // instead, which is not the vertical bar at all.
    let barMinX = isLeft ? 0 : view.bounds.width - inset
    guard frame.midX > barMinX, frame.midX < barMinX + inset else { return .zero }
    return frame
  }
}
