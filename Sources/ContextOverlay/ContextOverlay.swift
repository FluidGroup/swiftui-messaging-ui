import SwiftUI
import UIKit

public struct ContextOverlayContainer<Content: View>: View {

  let content: Content

  @Namespace var namespace
  @State private var context: PortalContext = .init()

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    content
      .blur(radius: context.overlay?.configuration.backgroundBlurRadius ?? 0)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay {
        ZStack {
          if let overlay = context.overlay?.content {
            ZStack {
              overlay
            }
            .transition(_Transition())
          }
        }
      }
      .environment(\.portalContext, context)
      .environment(\.portalNamespace, namespace)
  }

}

public struct ContextOverlay: Equatable {
  
  public struct Configuration {
    public let backgroundBlurRadius: CGFloat
    
    public init(backgroundBlurRadius: CGFloat) {
      self.backgroundBlurRadius = backgroundBlurRadius
    }
  }
  
  public static func == (lhs: ContextOverlay, rhs: ContextOverlay) -> Bool {
    lhs.requestID == rhs.requestID
  }
      
  public let requestID: UUID
  public let content: AnyView
  public let configuration: Configuration
  
  init(
    content: AnyView,
    configuration: Configuration
  ) {
    self.requestID = .init()
    self.content = content
    self.configuration = configuration
  }
  
}


@MainActor
@Observable
private final class PortalContext: @MainActor Equatable {
  
  static func == (lhs: PortalContext, rhs: PortalContext) -> Bool {
    lhs === rhs
  }

  weak var targetView: UIView? {
    didSet {
      print("targetView: \(targetView?.description ?? "nil")")
    }
  }    

  private(set) var overlay: ContextOverlay?

  func showOverlay<Content: View>(
    _ overlay: Content,
    configuration: ContextOverlay.Configuration
  ) {
    self.overlay = .init(
      content: AnyView(overlay),
      configuration: configuration
    )
  }

  func hideOverlay() {
    self.overlay = nil
  }

  init() {

  }
 
}

struct _Transition: Transition {

  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .environment(\.portalTransitionPhase, phase)
  }

}

extension EnvironmentValues {
  @Entry fileprivate var portalContext: PortalContext?
  @Entry fileprivate var portalNamespace: Namespace.ID?
  @Entry fileprivate var portalTransitionPhase: TransitionPhase?
}

extension View {

  public func contextOverlay<Overlay: View>(
    isEnabled: Binding<Bool>,
    configuration: ContextOverlay.Configuration = .init(backgroundBlurRadius: 16),
    @ViewBuilder _ overlay: @escaping (TransitionPhase) -> Overlay
  ) -> some View {
    modifier(
      ContextOverlayModifier(
        isTransmitting: isEnabled,
        configuration: configuration,
        overlay: overlay
      )
    )
  }

}

struct ContextOverlayModifier<Overlay: View>: ViewModifier {

  private let overlay: (TransitionPhase) -> Overlay
  private let configuration: ContextOverlay.Configuration
  
  @Binding var isTransmitting: Bool

  init(
    isTransmitting: Binding<Bool>,
    configuration: ContextOverlay.Configuration,
    overlay: @escaping (TransitionPhase) -> Overlay
  ) {
    self._isTransmitting = isTransmitting
    self.configuration = configuration
    self.overlay = overlay
  }

  func body(content: Content) -> some View {
    SourceWrapper(
      isTransmitting: $isTransmitting,
      configuration: configuration,
      content: { content },
      overlay: { OverlayWrapper(overlay: overlay) }
    )
  }

  struct OverlayWrapper: View {

    @Environment(\.portalTransitionPhase) private var phase

    let overlay: (TransitionPhase) -> Overlay

    var body: some View {
      if let phase {
        overlay(phase)
      } else {
        Text("phase is nil")
      }
    }
  }

  struct SourceWrapper<Content: View, _Overlay: View>: View {

    private let content: Content
    private let isTransmitting: Binding<Bool>

    @Environment(\.portalContext) private var context
    @Environment(\.portalNamespace) private var namespace
    @State private var ref: UIView?
    private let overlay: _Overlay
    private let configuration: ContextOverlay.Configuration

    init(
      isTransmitting: Binding<Bool>,
      configuration: ContextOverlay.Configuration,
      @ViewBuilder content: () -> Content,
      @ViewBuilder overlay: () -> _Overlay
    ) {
      self.content = content()
      self.configuration = configuration
      self.isTransmitting = isTransmitting
      self.overlay = overlay()
    }

    var body: some View {
      if let namespace, let context {
        SourceViewRepresentable(
          content: content,
          intercepter: { view in
            Task {
              self.ref = view
            }
          }
        )
        .onChange(of: isTransmitting.wrappedValue, initial: true) {
          _,
          isTransmitting in

          withAnimation(.smooth) {
            if isTransmitting {
              context.targetView = ref
              context.showOverlay(
                overlay,
                configuration: configuration
              )
            } else {
              context.hideOverlay()
            }
          }

        }
        .matchedGeometryEffect(
          id: ref.map { ObjectIdentifier($0) } as ObjectIdentifier?,
          in: namespace,
          properties: [.position],
          anchor: .center,
          isSource: true
        )
      } else {
        Text("⚠️ Portal: Context not set")
      }
    }
  }

}

/// Displays the active source's live rendering at a matched-geometry destination.
///
/// The source remains mounted and keeps its original SwiftUI state. The internal
/// native portal owns rendering and UIKit hit forwarding at the destination.
public struct PortalDestination: View {

  @Environment(\.portalContext) private var context
  @Environment(\.portalNamespace) private var namespace

  private let usesMatchedGeometry: Bool
  private let configuration: Configuration

  /// Creates a destination with independently configurable native portal behavior.
  ///
  /// - Parameters:
  ///   - usesMatchedGeometry: Whether SwiftUI matches the destination's position
  ///     to the source. This is separate from native `Configuration.matchesPosition`.
  ///   - configuration: Native rendering and hit-testing options, applied on every update.
  public init(
    usesMatchedGeometry: Bool = true,
    configuration: Configuration = .init()
  ) {
    self.usesMatchedGeometry = usesMatchedGeometry
    self.configuration = configuration
  }

  /// Creates a destination using the original SwiftUI position-matching argument.
  @available(
    *,
    deprecated,
    message: "Use init(usesMatchedGeometry:configuration:) instead."
  )
  public init(matchesPosition: Bool) {
    self.init(usesMatchedGeometry: matchesPosition)
  }

  public var body: some View {
    if let uiView = context?.targetView, let namespace {
      NativePortalViewRepresentable(
        sourceView: uiView,
        configuration: configuration
      )
      .fixedSize()
      .matchedGeometryEffect(
        id: usesMatchedGeometry ? Optional.some(ObjectIdentifier(uiView)) : nil,
        in: namespace,
        properties: [.position],
        anchor: .center,
        isSource: false
      )
    } else {
      Text("⚠️ Portal: Context not set")
    }
  }

}

/// UIViewRepresentable that displays the source view
private struct SourceViewRepresentable<Content: View>: UIViewRepresentable {

  typealias UIViewType = UIView

  final class Coordinator {
    let container: SourceViewContainer<Content>

    init(container: SourceViewContainer<Content>) {
      self.container = container
    }
  }

  let content: Content
  let intercepter: @MainActor (UIView) -> Void

  func makeCoordinator() -> Coordinator {
    .init(container: .init(content: content))
  }

  init(
    content: Content,
    intercepter: @escaping @MainActor (UIView) -> Void
  ) {
    self.content = content
    self.intercepter = intercepter
  }

  func makeUIView(context: Context) -> UIViewType {
    intercepter(context.coordinator.container.view)
    return context.coordinator.container.view
  }

  func updateUIView(_ uiView: UIViewType, context: Context) {
    context.coordinator.container.update(content: content)
    uiView.invalidateIntrinsicContentSize()
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: UIViewType,
    context: Context
  ) -> CGSize? {
    uiView.systemLayoutSizeFitting(
      .init(
        width: proposal.width ?? .greatestFiniteMagnitude,
        height: proposal.height ?? .greatestFiniteMagnitude
      ),
      withHorizontalFittingPriority: .defaultHigh,
      verticalFittingPriority: .fittingSizeLevel
    )
  }
}

/// Container that holds a SwiftUI view in a UIHostingController
/// and exposes the UIView for portaling
@MainActor
private final class SourceViewContainer<Content: View> {

  private let hostingController: UIHostingController<Content>

  var view: UIView {
    hostingController.view
  }

  init(content: Content) {
    self.hostingController = UIHostingController(rootView: content)
    self.hostingController.safeAreaRegions = []
    self.hostingController.view.backgroundColor = .clear
    self.hostingController.sizingOptions = .preferredContentSize

    hostingController.view.setNeedsLayout()
  }

  func update(content: Content) {
    hostingController.rootView = content
    // Let the layout system determine the size
    view.setNeedsLayout()
  }
}

#if DEBUG
  struct PreviewContent: View {

    @State var uiView: UIView?
    @State var isTransmitting: Bool = false

    var body: some View {

      ContextOverlayContainer {

        ZStack {

          ScrollView {

            RoundedRectangle(cornerRadius: 20)
              .fill(Color.red)
              .frame(width: 300, height: 300)
              .overlay {
                VStack {
                  Text("Hello")
                  Button.init("Action") { 
                    
                  }
                  ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { 
                  Button.init("Action") { 
                    
                  }
                }
              }
              .onTapGesture {
                print("tap")
                isTransmitting.toggle()
              }
              .contextOverlay(isEnabled: $isTransmitting) { phase in
                ZStack {

                  Color.black
                    .opacity(phase == .identity ? 0.25 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                  
                  VStack {

                    Capsule()
                      .frame(width: 100, height: 100)
                      .foregroundColor(
                        .red
                      )
                      .scaleEffect(phase == .identity ? 1 : 0)
                    
                    Button.init("Dismiss") { 
                      isTransmitting = false
                    }

                    PortalDestination(
                      usesMatchedGeometry: phase != .identity
                    )

                    Capsule()
                      .frame(width: 100, height: 100)
                      .foregroundColor(
                        .red
                      )
                      .scaleEffect(phase == .identity ? 1 : 0)

                  }
                }
              }

          }

        }
      }
    }
  }

  #Preview {

    PreviewContent()

  }
#endif
