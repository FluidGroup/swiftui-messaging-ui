import SwiftUI

/// Presents an existing rendering at a destination chosen by the caller.
///
/// Place this view above the source hierarchy with `.overlay`. Its content
/// builder can compose any layout or actions around the presentation's
/// ``ContextOverlayPresentation/sourcePlaceholder``. The source remains mounted
/// and the single live Portal moves between geometry proxies in this host.
/// The mirrored source is display-only. Compose interactive controls in the
/// destination content alongside its placeholder.
public struct ContextOverlay<Context, Content: View>: View {
  let state: ContextOverlayState<Context>
  let content: (ContextOverlayPresentation<Context>) -> Content
  @Namespace private var namespace

  /// Creates an overlay without imposing a background, destination or gesture.
  /// - Parameters:
  ///   - state: The presenting screen's stable state and selected source.
  ///   - content: Destination layout containing exactly one source placeholder.
  public init(
    state: ContextOverlayState<Context>,
    @ViewBuilder content: @escaping (ContextOverlayPresentation<Context>) -> Content
  ) {
    self.state = state
    self.content = content
  }

  public var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        if let presentation = state.presentation {
          // A single source proxy exists in this host. The real source's bounds
          // and contents stay unchanged while its Portal follows this position.
          if !state.isPresented {
            Color.clear
              .frame(width: presentation.size.width, height: presentation.size.height)
              .matchedGeometryEffect(id: presentation.id, in: namespace, properties: .position)
              .position(
                x: state.isDismissing ? presentation.returnRect.midX : presentation.sourceRect.midX,
                y: state.isDismissing ? presentation.returnRect.midY : presentation.sourceRect.midY
              )
              .transition(.identity)
          }

          content(presentation)
            .environment(\.contextOverlayGeometry, OverlayGeometry(
              id: presentation.id, namespace: namespace, isAtDestination: state.isPresented,
              onDestinationFrame: { [weak overlayState = state] id, frame in
                overlayState?.registerDestinationFrame(frame, for: id)
              }
            ))
            .disabled(state.isDismissing)

          PortalView(mirror: presentation.mirror)
            .id(presentation.id)
            .frame(width: presentation.size.width, height: presentation.size.height)
            .matchedGeometryEffect(id: presentation.id, in: namespace, properties: .position, isSource: false)
            .allowsHitTesting(false)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .coordinateSpace(name: namespace)
      .background {
        OverlayCoordinateMarker { [weak overlayState = state] view, attached in
          overlayState?.registerCoordinateView(view, attached: attached)
        }
      }
      .allowsHitTesting(state.presentation != nil)
    }
    .onDisappear { state.cancel() }
  }
}

/// A layout footprint for a presentation's live rendering, with no duplicate UI.
struct ContextOverlayDestination: View {
  let id: UUID
  let size: CGSize
  @Environment(\.contextOverlayGeometry) private var geometry

  var body: some View {
    let coordinateSpace = geometry?.namespace
    ZStack {
      Color.clear
      if let geometry, geometry.id == id, geometry.isAtDestination {
        Color.clear
          .matchedGeometryEffect(id: id, in: geometry.namespace, properties: .position)
          .transition(.identity)
      }
    }
    .frame(width: size.width, height: size.height)
    .onGeometryChange(for: CGRect.self) { proxy in
      guard let coordinateSpace else { return .null }
      return proxy.frame(in: .named(coordinateSpace))
    } action: { frame in
      geometry?.onDestinationFrame(id, frame)
    }
  }
}

/// Carries proxy matching data only through the caller's destination subtree.
private struct OverlayGeometry: Sendable {
  let id: UUID
  let namespace: Namespace.ID
  let isAtDestination: Bool
  let onDestinationFrame: @MainActor @Sendable (UUID, CGRect) -> Void
}

private extension EnvironmentValues {
  @Entry var contextOverlayGeometry: OverlayGeometry?
}
