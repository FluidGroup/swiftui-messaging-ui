import ContextOverlay
import MessagingCell
import MessagingUI
import SwiftUI

/// Adapts the generic contextual overlay to right-swipe reply in a TiledView.
///
/// Message data, sent/received alignment, and destination controls belong here.
/// ContextOverlay owns the live rendering handoff and geometry interpolation.
@available(iOS 18.0, *)
struct ReplyGeometryDemo: View {
  @State private var state = ContextOverlayState<Message>()
  @State private var scrollPosition = TiledScrollPosition()
  @State private var isSlow = false
  private let messages: [Message] = {
    var messages = generateConversation(count: 18, startId: 0)
    messages[4].text = "Want to grab dinner? That new Italian place has a quiet terrace, so we could catch up there after work."
    return messages
  }()

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        Toggle("Slow animation", isOn: $isSlow)
          .disabled(state.presentation != nil)

        Text("Right: reply · Left: timestamps · Vertical: scroll")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(12)

      Divider()

      messageList
        .allowsHitTesting(state.presentation == nil)
        .overlay {
          ContextOverlay(state: state) { presentation in
            replyDestination(presentation)
          }
        }

      Divider()

      VStack(alignment: .leading, spacing: 4) {
        Text(state.status)
        Text("Swipe a cell right or tap. The portal keeps the spinner ID and rotation. Drag the overlay vertically.")
          .foregroundStyle(.secondary)
      }
      .font(.caption)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
    }
    .navigationTitle("Reply Geometry Lab")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: isSlow) { _, slow in
      state.animation = .spring(response: slow ? 3 : 0.45, dampingFraction: 0.82)
      state.presentationSpringDuration = slow ? 3 : 0.45
    }
  }

  private var messageList: some View {
    // TiledView retains its initial builder, so rows share stable overlay state.
    let capturedState = state
    return TiledView(items: messages, scrollPosition: $scrollPosition) { message in
      ReplyGeometryCell(item: message, state: capturedState)
    }
    .revealConfiguration(.default)
  }

  /// The reply-specific destination composes the generic rendering placeholder.
  private func replyDestination(_ presentation: ContextOverlayPresentation<Message>) -> some View {
    GeometryReader { geometry in
      ZStack {
        Color(.systemBackground)
          .opacity(state.isPresented ? 0.9 : 0)
          .allowsHitTesting(false)

        ScrollView(.vertical) {
          VStack(spacing: 16) {
            Spacer(minLength: 0)
            Text("Reply target")
              .font(.headline)

            HStack(spacing: 0) {
              if presentation.context.isSentByMe { Spacer(minLength: 60) }
              presentation.sourcePlaceholder
              if !presentation.context.isSentByMe { Spacer(minLength: 60) }
            }
            .padding(.horizontal, 12)

            Button("Close") { state.dismiss() }
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("reply-geometry-close")
          }
          .padding(.bottom, 32)
          .frame(minHeight: geometry.size.height, alignment: .bottom)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollIndicators(.hidden)
        .opacity(state.isPresented ? 1 : 0)
        .accessibilityIdentifier("reply-geometry-overlay-scroll")
      }
    }
  }
}

/// Adapts the shared experiment row to TiledView's production cell interface.
@available(iOS 18.0, *)
private struct ReplyGeometryCell: TiledCellContent {
  typealias StateValue = Void

  let item: Message
  let state: ContextOverlayState<Message>

  func body(context: CellContext<Void>) -> some View {
    ReplyGeometryRow(
      message: item,
      state: state,
      reveal: context.cellReveal
    )
  }
}

/// Keeps one bubble subtree alive throughout portal presentation and return.
@available(iOS 18.0, *)
private struct ReplyGeometryRow: View {
  let message: Message
  let state: ContextOverlayState<Message>
  let reveal: CellReveal?
  @State private var source = CellSource()
  @State private var isAttachedToWindow = false

  var body: some View {
    let revealOffset = reveal?.rubberbandedOffset(max: 64) ?? 0
    let phase: CellReplyPhase = state.presentation?.context.id == message.id
      ? (state.isSourceHidden ? .presented : .preparing) : .idle

    HStack(spacing: 0) {
      if message.isSentByMe { Spacer(minLength: 60) }

      MessageCell(
        source: source,
        isReplyEnabled: state.presentation == nil && revealOffset < 0.5,
        replyPhase: phase,
        onReply: { source, release in
          state.present(message, from: source, velocity: release.velocity)
        },
        onSourceChange: { [weak state] source, attached in
          state?.sourceDidChange(source, attached: attached)
          DispatchQueue.main.async {
            if isAttachedToWindow != attached { isAttachedToWindow = attached }
          }
        }
      ) {
        ReplyGeometryBubble(message: message, animatesProbe: isAttachedToWindow)
      }
        .overlay(alignment: .trailing) {
          Text("12:00")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .offset(x: 48)
            .opacity(min(revealOffset / 40, 1))
            .allowsHitTesting(false)
        }
        .offset(x: -revealOffset)
        .onTapGesture { state.present(message, from: source) }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(message.text)
        .accessibilityIdentifier("reply-geometry-source-\(message.id)")

      if !message.isSentByMe { Spacer(minLength: 60) }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 2)
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
      // Off-window measurement hosts reserve the same geometry without starting
      // an animation that cannot be observed.
      isRotating = isActive
    }
    .onChange(of: isActive) { _, active in isRotating = active }
  }
}

#Preview {
  if #available(iOS 18.0, *) {
    NavigationStack { ReplyGeometryDemo() }
  }
}
