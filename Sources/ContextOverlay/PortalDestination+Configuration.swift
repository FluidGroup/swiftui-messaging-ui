extension PortalDestination {

  /// Controls how a destination mirrors and interacts with its source rendering.
  ///
  /// These options configure the native portal and can change while it is mounted.
  /// The source view is supplied by the surrounding context overlay. SwiftUI's
  /// geometry matching is controlled separately by `usesMatchedGeometry`.
  public struct Configuration: Equatable, Sendable {

    /// Whether the mirror inherits the source's alpha. Defaults to false.
    public var matchesAlpha: Bool

    /// Whether the mirror inherits the source's transform. Defaults to false.
    public var matchesTransform: Bool

    /// Whether the native mirror follows the source's position. Defaults to false.
    ///
    /// Enable this when native positioning should follow the source rather than
    /// the destination's layout. This does not enable SwiftUI matched geometry.
    public var matchesPosition: Bool

    /// Whether the native portal participates in hit testing. Defaults to true.
    public var allowsHitTesting: Bool

    /// Whether native hit testing resolves hits in the source's subtree.
    ///
    /// Defaults to true. `allowsHitTesting` must also be true to accept portal hits.
    public var forwardsClientHitTestingToSourceView: Bool

    /// Whether the source's drawing is hidden while mirrored. Defaults to true.
    ///
    /// Disabling this keeps both renderings visible. Removing the destination
    /// always restores the source, regardless of this option's last value.
    public var hidesSourceView: Bool

    /// Creates native portal options with independent destination geometry.
    public init(
      matchesAlpha: Bool = false,
      matchesTransform: Bool = false,
      matchesPosition: Bool = false,
      allowsHitTesting: Bool = true,
      forwardsClientHitTestingToSourceView: Bool = true,
      hidesSourceView: Bool = true
    ) {
      self.matchesAlpha = matchesAlpha
      self.matchesTransform = matchesTransform
      self.matchesPosition = matchesPosition
      self.allowsHitTesting = allowsHitTesting
      self.forwardsClientHitTestingToSourceView = forwardsClientHitTestingToSourceView
      self.hidesSourceView = hidesSourceView
    }
  }
}
