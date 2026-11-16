import UIKit

/// Reads where native apps put their top bar beside the status bar.
///
/// On the iPhone Duo's inner display held in portrait, iOS gathers the status
/// bar into a cluster at the top right, and native apps put their top bar in
/// the same row, left of the cluster. There UIKit's frame for a bar on the top
/// edge starts above the safe area and ends where the cluster begins, so it
/// narrows when a Live Activity widens the cluster. Everywhere else it starts
/// at or below the top of the safe area, where Flutter already lays out an app
/// bar, so it is reported as `.zero`.
///
/// The API arrived in the iOS 27.1 SDK, so it is reached through the runtime
/// like the vertical bar's, and older SDKs keep compiling.
enum FoldableTopBar {
  /// UIKit's default height for a top bar. Only the frame's height depends on
  /// it: measured on the iPhone Duo simulator, 44, 50 and 60 all centre on
  /// the status bar's clock.
  private static let extent: CGFloat = 48

  /// The top bar's frame beside the status bar, in `view`'s coordinates, or
  /// `.zero` where there is none or the API is missing.
  static func frame(in view: UIView?) -> CGRect {
    // UIRectEdge.top is 1 << 0.
    guard let view = view,
      let region = ObjCRuntimeSupport.classObject(
        "UIViewLayoutRegion", "layoutRegionForBarOnEdge:extent:", 1, extent),
      let insets = ObjCRuntimeSupport.edgeInsets(
        of: view, selector: NSSelectorFromString("edgeInsetsForLayoutRegion:"),
        object: region)
    else { return .zero }
    let frame = view.bounds.inset(by: insets)
    guard !frame.isEmpty, frame.minY < view.safeAreaInsets.top else { return .zero }
    return frame
  }
}
