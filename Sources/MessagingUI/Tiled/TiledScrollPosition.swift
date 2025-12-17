
public struct TiledScrollPosition: Equatable, Sendable {

  public enum Edge: Equatable, Sendable {
    case top
    case bottom
  }

  /// Current scroll edge
  var edge: Edge?
  var animated: Bool = true

  /// Version for change tracking
  private(set) var version: UInt = 0

  /// Auto-scroll to bottom when items are appended
  public var autoScrollsToBottomOnAppend: Bool

  /// Scroll to bottom when items are set (initial load)
  public var scrollsToBottomOnSetItems: Bool

  public init(
    autoScrollsToBottomOnAppend: Bool = false,
    scrollsToBottomOnSetItems: Bool = false
  ) {
    self.autoScrollsToBottomOnAppend = autoScrollsToBottomOnAppend
    self.scrollsToBottomOnSetItems = scrollsToBottomOnSetItems
  }

  public mutating func scrollTo(edge: Edge, animated: Bool = true) {
    self.edge = edge
    self.animated = animated
    makeDirty()
  }
  
  private mutating func makeDirty() {
    self.version &+= 1
  }
}
