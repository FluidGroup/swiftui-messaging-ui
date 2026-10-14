import CoreGraphics
import Testing
@testable import MessagingCell

/// Verifies release decisions using displayed distance and physical flick velocity.
struct CellReplyConfigurationTests {
  @Test
  func slowShortDragDoesNotRequestReply() {
    let release = CellReplyRelease(
      offset: CGSize(width: 32, height: 0),
      velocity: CGVector(dx: 40, dy: 0)
    )

    #expect(!CellReplyConfiguration().accepts(release))
  }

  @Test
  func shortFastRightFlickRequestsReply() {
    let release = CellReplyRelease(
      offset: CGSize(width: 24, height: 0),
      velocity: CGVector(dx: 400, dy: 0)
    )

    // A short release can express reply intent without reaching the distance.
    #expect(CellReplyConfiguration().accepts(release))
  }

  @Test
  func sustainedDistanceRequestsReplyWithoutVelocity() {
    let configuration = CellReplyConfiguration()

    #expect(configuration.accepts(.init(
      offset: CGSize(width: 80, height: 0),
      velocity: .zero
    )))
    #expect(configuration.accepts(.init(
      offset: CGSize(width: 64, height: 0),
      velocity: .zero
    )))
  }

  @Test
  func reversingVelocityDoesNotPromoteShortDrag() {
    let release = CellReplyRelease(
      offset: CGSize(width: 36, height: 0),
      velocity: CGVector(dx: -1_000, dy: 0)
    )

    #expect(!CellReplyConfiguration().accepts(release))
  }

  @Test(arguments: [CGFloat(-32), CGFloat.zero])
  func leftOrZeroOffsetDoesNotRequestReplyEvenWithPositiveVelocity(offset: CGFloat) {
    let release = CellReplyRelease(
      offset: CGSize(width: offset, height: 0),
      velocity: CGVector(dx: 2_000, dy: 0)
    )

    #expect(!CellReplyConfiguration().accepts(release))
  }

  @Test
  func disablingProjectionRequiresDistanceRegardlessOfFlickVelocity() {
    let configuration = CellReplyConfiguration(velocityProjectionDuration: 0)

    #expect(!configuration.accepts(.init(
      offset: CGSize(width: 24, height: 0),
      velocity: CGVector(dx: 2_000, dy: 0)
    )))
    #expect(configuration.accepts(.init(
      offset: CGSize(width: 64, height: 0),
      velocity: CGVector(dx: -1_000, dy: 0)
    )))
  }
}
