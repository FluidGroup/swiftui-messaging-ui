import XCTest
@testable import MessagingUI

final class ScrollViewGeometryTests: XCTestCase {

  // MARK: - Content Not Scrollable

  func test_contentOffsetToMakeRectVisible_contentSmallerThanBounds_returnsNil() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 400),
      contentOffset: .zero,
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: .zero
    )

    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 300, width: 320, height: 50)
    )

    XCTAssertNil(result, "Should return nil when content is smaller than bounds")
  }

  func test_contentOffsetToMakeRectVisible_contentEqualToBounds_returnsNil() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 600),
      contentOffset: .zero,
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: .zero
    )

    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 300, width: 320, height: 50)
    )

    XCTAssertNil(result, "Should return nil when content equals bounds")
  }

  func test_contentOffsetToMakeRectVisible_withInsets_contentNotScrollable_returnsNil() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 500),
      contentOffset: .zero,
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: UIEdgeInsets(top: 50, left: 0, bottom: 50, right: 0)
    )

    // visibleHeight = 600 - 50 - 50 = 500, contentSize.height = 500 -> not scrollable
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 300, width: 320, height: 50)
    )

    XCTAssertNil(result, "Should return nil when content equals visible height with insets")
  }

  // MARK: - Rect Already Visible

  func test_contentOffsetToMakeRectVisible_rectFullyVisible_returnsNil() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 0, y: 100),
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: .zero
    )

    // visibleRect: y = 100, height = 600 -> 100...700
    // rect: y = 200, height = 50 -> 200...250 (fully inside 100...700)
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 200, width: 320, height: 50)
    )

    XCTAssertNil(result, "Should return nil when rect is already fully visible")
  }

  func test_contentOffsetToMakeRectVisible_rectAtTopEdgeOfVisible_returnsNil() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 0, y: 100),
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: .zero
    )

    // visibleRect: 100...700
    // rect: 100...150 (exactly at top edge)
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 100, width: 320, height: 50)
    )

    XCTAssertNil(result, "Should return nil when rect is at top edge of visible area")
  }

  func test_contentOffsetToMakeRectVisible_rectAtBottomEdgeOfVisible_returnsNil() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 0, y: 100),
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: .zero
    )

    // visibleRect: 100...700
    // rect: 650...700 (exactly at bottom edge)
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 650, width: 320, height: 50)
    )

    XCTAssertNil(result, "Should return nil when rect is at bottom edge of visible area")
  }

  // MARK: - Scroll Down (Rect Below Visible)

  func test_contentOffsetToMakeRectVisible_rectBelowVisible_scrollsDown() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 0, y: 0),
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: .zero
    )

    // visibleRect: 0...600
    // rect: 700...750 (below visible)
    // Need to scroll so rect.maxY (750) aligns with visibleRect.maxY
    // newOffset = 0 + (750 - 600) = 150
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 700, width: 320, height: 50)
    )

    XCTAssertNotNil(result)
    XCTAssertEqual(result!.y, 150, accuracy: 0.001)
  }

  func test_contentOffsetToMakeRectVisible_rectPartiallyBelowVisible_scrollsMinimum() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 0, y: 0),
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: .zero
    )

    // visibleRect: 0...600
    // rect: 580...630 (partially visible, bottom cut off)
    // newOffset = 0 + (630 - 600) = 30
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 580, width: 320, height: 50)
    )

    XCTAssertNotNil(result)
    XCTAssertEqual(result!.y, 30, accuracy: 0.001)
  }

  // MARK: - Scroll Up (Rect Above Visible)

  func test_contentOffsetToMakeRectVisible_rectAboveVisible_scrollsUp() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 0, y: 500),
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: .zero
    )

    // visibleRect: 500...1100
    // rect: 200...250 (above visible)
    // Need to scroll so rect.minY (200) aligns with visibleRect.minY
    // newOffset = 500 - (500 - 200) = 200
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 200, width: 320, height: 50)
    )

    XCTAssertNotNil(result)
    XCTAssertEqual(result!.y, 200, accuracy: 0.001)
  }

  func test_contentOffsetToMakeRectVisible_rectPartiallyAboveVisible_scrollsMinimum() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 0, y: 100),
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: .zero
    )

    // visibleRect: 100...700
    // rect: 80...130 (partially visible, top cut off)
    // newOffset = 100 - (100 - 80) = 80
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 80, width: 320, height: 50)
    )

    XCTAssertNotNil(result)
    XCTAssertEqual(result!.y, 80, accuracy: 0.001)
  }

  // MARK: - Clamping

  func test_contentOffsetToMakeRectVisible_clampsToMinOffset() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 0, y: 100),
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: UIEdgeInsets(top: 50, left: 0, bottom: 0, right: 0)
    )

    // minOffsetY = -50
    // rect at very top, requesting scroll to y = -100 would exceed min
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 0, width: 320, height: 50)
    )

    XCTAssertNotNil(result)
    XCTAssertGreaterThanOrEqual(result!.y, -50, "Should clamp to minimum offset")
  }

  func test_contentOffsetToMakeRectVisible_clampsToMaxOffset() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 0, y: 0),
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: UIEdgeInsets(top: 0, left: 0, bottom: 50, right: 0)
    )

    // maxOffsetY = 1000 - 600 + 50 = 450
    // rect at very bottom
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 950, width: 320, height: 100)
    )

    XCTAssertNotNil(result)
    XCTAssertLessThanOrEqual(result!.y, 450, "Should clamp to maximum offset")
  }

  // MARK: - With Content Insets

  func test_contentOffsetToMakeRectVisible_withTopInset_calculatesCorrectly() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 0, y: -100),  // negative offset due to top inset
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: UIEdgeInsets(top: 100, left: 0, bottom: 0, right: 0)
    )

    // visibleHeight = 600 - 100 - 0 = 500
    // visibleRect.y = -100 + 100 = 0
    // visibleRect: 0...500
    // rect: 600...650 (below visible)
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 600, width: 320, height: 50)
    )

    XCTAssertNotNil(result)
    XCTAssertGreaterThan(result!.y, -100)
  }

  // MARK: - No Change Needed

  func test_contentOffsetToMakeRectVisible_offsetUnchanged_returnsNil() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 0, y: 200),
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: .zero
    )

    // visibleRect: 200...800
    // rect is fully visible
    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 300, width: 320, height: 100)
    )

    XCTAssertNil(result, "Should return nil when no offset change is needed")
  }

  // MARK: - X Coordinate Preservation

  func test_contentOffsetToMakeRectVisible_preservesXOffset() {
    let geometry = ScrollViewGeometry(
      contentSize: CGSize(width: 320, height: 1000),
      contentOffset: CGPoint(x: 50, y: 0),
      bounds: CGSize(width: 320, height: 600),
      adjustedContentInset: .zero
    )

    let result = geometry.contentOffsetToMakeRectVisible(
      CGRect(x: 0, y: 700, width: 320, height: 50)
    )

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.x, 50, "Should preserve x offset")
  }
}
