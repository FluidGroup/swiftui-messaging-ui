/// Controls scroll position in TiledView.
///
/// Use this struct to programmatically scroll to edges and configure auto-scroll behavior.
/// Pass it as a binding to TiledView for two-way communication.
///
/// ## Auto-scroll Configuration
///
/// Configure automatic scrolling behavior for messaging UIs:
///
/// ```swift
/// @State private var scrollPosition = TiledScrollPosition(
///   autoScrollsToBottomOnAppend: true,   // Auto-scroll when new messages arrive
///   scrollsToBottomOnReplace: true       // Start at bottom on initial load
/// )
///
/// TiledView(dataSource: dataSource, scrollPosition: $scrollPosition) { ... }
/// ```
///
/// ## Programmatic Scrolling
///
/// Scroll to edges programmatically using ``scrollTo(edge:animated:)``:
///
/// ```swift
/// Button("Scroll to Bottom") {
///   scrollPosition.scrollTo(edge: .bottom, animated: true)
/// }
/// ```
///
/// ## Dynamic Auto-scroll
///
/// Adjust auto-scroll based on user's scroll position:
///
/// ```swift
/// .onTiledScrollGeometryChange { geometry in
///   // Only auto-scroll when user is near bottom
///   scrollPosition.autoScrollsToBottomOnAppend = geometry.pointsFromBottom < 100
/// }
/// ```
public struct TiledScrollPosition: Equatable, Sendable {

  /// The edge to scroll to.
  public enum Edge: Equatable, Sendable {
    /// Scroll to the top of the content.
    case top
    /// Scroll to the bottom of the content.
    case bottom
  }

  /// The target edge for the next scroll action.
  var edge: Edge?

  /// Whether the scroll should be animated.
  var animated: Bool = true

  /// Version counter for change tracking.
  private(set) var version: UInt = 0

  /// Whether to automatically scroll to bottom when new items are appended.
  ///
  /// Set this to `true` for typical messaging behavior where new messages
  /// should appear and the view scrolls down automatically.
  ///
  /// You can dynamically toggle this based on scroll position:
  /// ```swift
  /// .onTiledScrollGeometryChange { geometry in
  ///   scrollPosition.autoScrollsToBottomOnAppend = geometry.pointsFromBottom < 100
  /// }
  /// ```
  public var autoScrollsToBottomOnAppend: Bool

  /// Whether to scroll to bottom when items are replaced (initial load).
  ///
  /// Set this to `true` for messaging apps where you want to show
  /// the most recent messages first when the conversation loads.
  public var scrollsToBottomOnReplace: Bool

  /// Creates a scroll position with the specified auto-scroll configuration.
  ///
  /// - Parameters:
  ///   - autoScrollsToBottomOnAppend: Whether to auto-scroll when items are appended. Defaults to `false`.
  ///   - scrollsToBottomOnReplace: Whether to scroll to bottom on initial load. Defaults to `false`.
  public init(
    autoScrollsToBottomOnAppend: Bool = false,
    scrollsToBottomOnReplace: Bool = false
  ) {
    self.autoScrollsToBottomOnAppend = autoScrollsToBottomOnAppend
    self.scrollsToBottomOnReplace = scrollsToBottomOnReplace
  }

  /// Scrolls to the specified edge.
  ///
  /// - Parameters:
  ///   - edge: The edge to scroll to (`.top` or `.bottom`).
  ///   - animated: Whether to animate the scroll. Defaults to `true`.
  public mutating func scrollTo(edge: Edge, animated: Bool = true) {
    self.edge = edge
    self.animated = animated
    makeDirty()
  }

  private mutating func makeDirty() {
    self.version &+= 1
  }
}
