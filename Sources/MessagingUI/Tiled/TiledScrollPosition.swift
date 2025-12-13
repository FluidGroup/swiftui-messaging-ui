
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

  public init() {}

  public mutating func scrollTo(edge: Edge, animated: Bool = true) {
    self.edge = edge
    self.animated = animated
    self.version += 1
  }
}
