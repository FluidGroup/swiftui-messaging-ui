import MessagingUI
import Observation
import SwiftUI
import UIKit

/// Tests message-to-overlay geometry transitions from TiledView's cell hosts.
///
/// Each row uses the library's actual `UIHostingConfiguration`. The outer overlay
/// shares its namespace and selection transaction with these independent hosts.
struct ReplyGeometryDemo: View {
  @Namespace private var namespace
  @State private var session = ReplyGeometrySession()
  @State private var scrollPosition = TiledScrollPosition()

  var body: some View {
    @Bindable var session = session

    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        Toggle("Slow animation", isOn: $session.isSlow)
          .disabled(session.selected != nil)

        Text("TiledView cell hosts → overlay")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(12)

      Divider()

      messageList
        .allowsHitTesting(session.selected == nil)
        .overlay {
          if let message = session.selected {
            replyOverlay(message: message)
              // Retain outgoing rendering while geometry returns to the source.
              .transition(.opacity)
          }
        }

      Divider()

      Text("Tap a bubble and compare its spinner phase and render ID during travel. This overlay rebuilds the bubble; it does not use a portal yet.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
    }
    .navigationTitle("Reply Geometry Lab")
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private var messageList: some View {
    // TiledView retains its initial builder. Capture reference state and the
    // namespace once; selection is observed inside each row's SwiftUI body.
    let capturedSession = session
    let capturedNamespace = namespace

    TiledView(items: session.messages, scrollPosition: $scrollPosition) { message in
      ReplyGeometryCell(
        item: message,
        session: capturedSession,
        namespace: capturedNamespace
      )
    }
    .revealConfiguration(.disabled)
  }

  private func replyOverlay(message: Message) -> some View {
    GeometryReader { geometry in
      ZStack {
        Color(.systemBackground)
          .opacity(0.9)
          .transition(.opacity)

        ScrollView(.vertical) {
          VStack(spacing: 16) {
            Spacer(minLength: 0)

            Text("Reply target")
              .font(.headline)

            HStack(spacing: 0) {
              if message.isSentByMe { Spacer(minLength: 60) }

              ReplyGeometryBubble(message: message)
                .matchedGeometryEffect(id: message.id, in: namespace)
                .transition(.opacity)
                .accessibilityIdentifier("reply-geometry-overlay-bubble")

              if !message.isSentByMe { Spacer(minLength: 60) }
            }
            .padding(.horizontal, 12)

            Button("Close") {
              withAnimation(session.animation) {
                session.selected = nil
              }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("reply-geometry-close")
          }
          .padding(.bottom, 32)
          // Preserve the resting destination while letting taller content grow.
          .frame(minHeight: geometry.size.height, alignment: .bottom)
        }
        // A short bubble still needs to move with the user's vertical drag.
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("reply-geometry-overlay-scroll")
      }
    }
    .zIndex(1)
  }
}

/// Owns the selection shared by the outer overlay and independently hosted rows.
///
/// Reference identity lets rows observe selection changes even though TiledView
/// keeps the builder supplied when its UIKit view is first created.
@MainActor
@Observable
private final class ReplyGeometrySession {
  var selected: Message?
  var isSlow = false
  let messages: [Message]

  init() {
    var messages = generateConversation(count: 18, startId: 0)
    messages[4].text = "Want to grab dinner? That new Italian place has a quiet terrace, so we could catch up there after work."
    self.messages = messages
  }

  var animation: Animation {
    .spring(response: isSlow ? 3 : 0.45, dampingFraction: 0.82)
  }
}

/// Adapts the shared experiment row to TiledView's production cell interface.
private struct ReplyGeometryCell: TiledCellContent {
  typealias StateValue = Void

  let item: Message
  let session: ReplyGeometrySession
  let namespace: Namespace.ID

  func body(context: CellContext<Void>) -> some View {
    ReplyGeometryRow(
      message: item,
      session: session,
      namespace: namespace
    )
  }
}

/// Keeps the source row's layout intact while its bubble lives in the overlay.
private struct ReplyGeometryRow: View {
  let message: Message
  let session: ReplyGeometrySession
  let namespace: Namespace.ID
  @State private var isAttachedToWindow = false

  var body: some View {
    HStack(spacing: 0) {
      if message.isSentByMe { Spacer(minLength: 60) }

      Group {
        if session.selected?.id == message.id {
          // Hidden content reserves the exact wrapping and height, but does not
          // register another matched-geometry source or expose an invisible button.
          ReplyGeometryBubble(message: message, animatesProbe: false)
            .hidden()
            .accessibilityHidden(true)
        } else if isAttachedToWindow {
          ReplyGeometryBubble(message: message)
            .matchedGeometryEffect(id: message.id, in: namespace)
            .transition(.opacity)
            .onTapGesture {
              withAnimation(session.animation) {
                session.selected = message
              }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("reply-geometry-source-\(message.id)")
        } else {
          // TiledView's off-window sizing cell must never become a second source.
          ReplyGeometryBubble(message: message, animatesProbe: false)
        }
      }

      if !message.isSentByMe { Spacer(minLength: 60) }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 2)
    .background {
      ReplyGeometryWindowProbe { isAttachedToWindow = $0 }
    }
  }
}

/// Renders a message with an independent animation probe for live-mirror testing.
private struct ReplyGeometryBubble: View {
  let message: Message
  var animatesProbe = true

  var body: some View {
    HStack(spacing: 8) {
      Text(message.text)
        .font(.body)

      ReplyAnimationProbe(isActive: animatesProbe)
    }
    .foregroundStyle(message.isSentByMe ? .white : .primary)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background {
      RoundedRectangle(cornerRadius: 18)
        .fill(message.isSentByMe ? Color.blue : Color(.systemGray5))
    }
  }
}

/// Identifies one rendered instance and animates independently of all other probes.
///
/// A live portal should mirror this instance's ID and ongoing rotation phase.
/// A snapshot freezes the rotation, while a newly rendered bubble gets a new ID
/// and starts its own rotation. No clock or phase is shared through the session.
private struct ReplyAnimationProbe: View {
  let isActive: Bool
  @State private var renderID = UUID()
  @State private var isRotating = false

  var body: some View {
    VStack(spacing: 3) {
      Circle()
        .trim(from: 0, to: 0.75)
        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .frame(width: 16, height: 16)
        .rotationEffect(.degrees(isRotating ? 360 : 0))
        .animation(
          isActive ? .linear(duration: 1.2).repeatForever(autoreverses: false) : nil,
          value: isRotating
        )

      Text(String(renderID.uuidString.prefix(6)))
        .font(.system(size: 9, design: .monospaced))
        .opacity(0.7)
    }
    .frame(width: 40)
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Animation probe, render ID \(renderID.uuidString)")
    .onAppear {
      // Hidden placeholders and off-window measurement hosts reserve the same
      // geometry without starting an animation that cannot be observed.
      isRotating = isActive
    }
  }
}

/// Detects actual window attachment without treating a sizing host as visible.
private struct ReplyGeometryWindowProbe: UIViewRepresentable {
  let onChange: (Bool) -> Void

  func makeUIView(context: Context) -> WindowObserver {
    let view = WindowObserver()
    view.onChange = onChange
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ uiView: WindowObserver, context: Context) {
    uiView.onChange = onChange
  }

  /// Reports attachment after UIKit has completed its view hierarchy mutation.
  final class WindowObserver: UIView {
    var onChange: ((Bool) -> Void)?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.onChange?(self.window != nil)
      }
    }
  }
}

#Preview {
  NavigationStack {
    ReplyGeometryDemo()
  }
}
