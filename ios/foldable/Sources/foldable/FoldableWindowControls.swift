import UIKit

/// Reads the corner of the window that the iPad's window controls take.
///
/// When an iPad runs apps in windows, iPadOS 26 and later draw the close,
/// minimize and full-screen controls in a top corner of the window, inside the
/// safe area, so `safeAreaInsets` leave them out. UIKit's way to keep clear of
/// them is a safe-area layout region with corner adaptation: horizontal
/// adaptation insets the side, vertical adaptation the top.
///
/// Both adaptations also grow for rounded corners. Measured on the iPad mini
/// (A20 Pro) simulator, a window's corners add 9.5 to both horizontal insets,
/// and in full screen the display's corners add 14, but only the controls push
/// the vertical adaptation's top inset past the safe area's: in a window it is
/// 43 below the safe area's top, in full screen it is the safe area's own.
///
/// That holds only where the safe area's top already clears the display's
/// corners. Where it does not, the corners push the vertical adaptation down
/// too: on the iPhone 17 simulator in landscape, 18 below a safe area top of 0,
/// on the iPhone Duo simulator's cover display, whose status bar is in the
/// vertical bar, 17.3, and on the iPad mini with its status bar hidden, 9.5.
/// So only an iPad is read, as the only device that draws window controls, and
/// only when one side grows more than the other: the display's corners widen
/// both sides alike, the controls only their own. The iPhone Duo's inner
/// display puts two apps side by side with a divider between them, but draws
/// no window controls on either.
///
/// The API arrived in the iOS 26 SDK, so it is reached through the runtime
/// like the bar regions, and older SDKs keep compiling.
enum FoldableWindowControls {
  /// The rectangle the controls reserve in `view`'s coordinates, from the
  /// window's top corner to where content beside or below them may start, or
  /// `.zero` where there are none or the API is missing.
  ///
  /// The room reserved is the collapsed controls'. Expanding them draws the
  /// full-size buttons over the content for a moment and changes nothing here.
  static func frame(in view: UIView?) -> CGRect {
    // UIViewLayoutRegionAdaptivityAxis: horizontal is 1, vertical is 2.
    guard let view = view,
      view.traitCollection.userInterfaceIdiom == .pad,
      let horizontal = insets(of: view, adaptation: 1),
      let vertical = insets(of: view, adaptation: 2)
    else { return .zero }
    let safe = view.safeAreaInsets
    let left = horizontal.left - safe.left
    let right = horizontal.right - safe.right
    guard vertical.top > safe.top, abs(left - right) >= 1 else { return .zero }

    // The controls' side is the one their corner widens the most; the other
    // grows only by its rounding.
    if left > right {
      return CGRect(x: 0, y: 0, width: horizontal.left, height: vertical.top)
    }
    return CGRect(
      x: view.bounds.width - horizontal.right, y: 0, width: horizontal.right,
      height: vertical.top)
  }

  private static func insets(of view: UIView, adaptation: UInt) -> UIEdgeInsets? {
    guard
      let region = ObjCRuntimeSupport.classObject(
        "UIViewLayoutRegion", "safeAreaLayoutRegionWithCornerAdaptation:", adaptation)
    else { return nil }
    return ObjCRuntimeSupport.edgeInsets(
      of: view, selector: NSSelectorFromString("edgeInsetsForLayoutRegion:"), object: region)
  }
}
