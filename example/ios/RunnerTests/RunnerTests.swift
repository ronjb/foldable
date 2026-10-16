import Flutter
import UIKit
import XCTest

@testable import foldable

class RunnerTests: XCTestCase {

  func testNilHingeAfterAHingeKeepsTheDeviceFoldable() {
    // A foldable reports a nil hinge when the interaction leaves a hierarchy
    // that provides hinge updates. Settling that as "no hinge" would end the
    // Dart stream for good.
    let source = RuntimeHingeSource()
    source.handle(FakeUpdate(hinge: FakeHinge()))
    source.handle(FakeUpdate(hinge: nil))
    XCTAssertEqual(source.hasHinge, true)
  }

  func testNilHingeFirstSettlesThatThereIsNone() {
    let source = RuntimeHingeSource()
    source.handle(FakeUpdate(hinge: nil))
    XCTAssertEqual(source.hasHinge, false)
  }

  func testInteractionMovesToANewHostView() throws {
    try XCTSkipUnless(RuntimeHingeSource.isAvailable, "Needs the iOS 27.1 hinge APIs.")
    let source = RuntimeHingeSource()
    let oldHost = UIView()
    let newHost = UIView()
    source.start(on: oldHost) { _ in }
    source.start(on: newHost) { _ in }
    XCTAssertEqual(hingeInteractionCount(on: oldHost), 0)
    XCTAssertEqual(hingeInteractionCount(on: newHost), 1, "\(newHost.interactions)")
  }

  func testEmitBuildsTheSnapshotOnTheMainThread() {
    // The snapshot reads UIKit, so it must not be built on the caller's thread.
    let built = expectation(description: "snapshot built")
    var builtOnMain: Bool?
    let handler = HingeStreamHandler(
      hingeSource: FakeHingeSource(),
      snapshotBuilder: { _ in
        builtOnMain = Thread.isMainThread
        built.fulfill()
        return [:]
      })
    _ = handler.onListen(withArguments: nil, eventSink: { _ in })

    DispatchQueue.global().async { handler.emit(nil) }

    wait(for: [built], timeout: 1)
    XCTAssertEqual(builtOnMain, true)
  }
}

/// The number of `UIHingeInteraction`s on `view`, ignoring the helper
/// interactions UIKit attaches alongside one, such as
/// `_UISceneTargetingInteraction`.
private func hingeInteractionCount(on view: UIView) -> Int {
  return view.interactions.filter {
    NSStringFromClass(type(of: $0)) == "UIHingeInteraction"
  }.count
}

/// Stands in for `UIHingeInteractionUpdate`, read through KVC like the real one.
private final class FakeUpdate: NSObject {
  @objc let hinge: NSObject?

  init(hinge: NSObject?) {
    self.hinge = hinge
    super.init()
  }
}

/// Stands in for a partially open `UIHinge`.
private final class FakeHinge: NSObject {
  @objc let status = 2
  @objc let angle = CGFloat.pi / 2
}

private final class FakeHingeSource: HingeSource {
  static var isAvailable: Bool { return true }
  var hasHinge: Bool? { return nil }
  var strategy: String { return "fake" }
  var currentReading: HingeReading? { return nil }

  func start(on view: UIView, onChange: @escaping (HingeReading) -> Void) -> Bool {
    return true
  }

  func stop() {}
}
