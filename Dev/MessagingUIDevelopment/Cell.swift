import SwiftUI
import MessagingUI

// MARK: - Sample Data

struct ChatMessage: Identifiable, Hashable, Equatable, Sendable {
  let id: Int
  var text: String
}

// MARK: - Cell State

/// Per-cell state managed by CellStateStorage
struct ChatBubbleCellState {
  var counter: Int = 0
  var isExpanded: Bool = false
}

func generateSampleMessages(count: Int, startId: Int) -> [ChatMessage] {
  let sampleTexts: [String] = [
    "Hello!",
    "Nice weather today. Want to go for a walk?",
    "The movie yesterday was amazing! The ending scene was so impressive. I'd love to watch it again.",
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt.",
    "Got it 👍",
    "Hold on, let me check and get back to you.",
    "Any plans for the weekend? If you're free, want to grab coffee? There's a new place that just opened.",
    "OK",
    "On my way!",
    "This is a long message for testing. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam.",
    "🎉🎊✨",
  ]

  return (0..<count).map { index in
    let id = startId + index
    let textIndex = abs(id) % sampleTexts.count
    return ChatMessage(id: id, text: sampleTexts[textIndex])
  }
}

// MARK: - Chat Bubble View

/// Cell that uses CellStateStorage for state persistence.
/// counter and isExpanded are persisted via CellStateStorage across cell reuse.
struct ChatBubbleView: View {

  let message: ChatMessage
  let state: CellStateStorage<ChatBubbleCellState>

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("ID: \(message.id)")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button {
            state.value.counter += 1
          } label: {
            Text("\(state.value.counter)")
              .font(.caption)
              .monospacedDigit()
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(
                Capsule()
                  .fill(state.value.counter > 0 ? Color.blue : Color(.systemGray5))
              )
              .foregroundStyle(state.value.counter > 0 ? .white : .secondary)
          }
          .buttonStyle(.plain)

          Button("Expand") {
            withAnimation(.smooth) {
              state.value.isExpanded.toggle()
            }
          }
        }

        Text(message.text)
          .font(.system(size: 16))
          .fixedSize(horizontal: false, vertical: true)

        if state.value.isExpanded {
          Text("Expanded (CellStateStorage)")
            .font(.caption)
            .foregroundStyle(.blue)
            .padding(.top, 4)
        }
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color(.systemGray6))
      )

      Spacer(minLength: 44)
    }
    .contentShape(Rectangle())
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
  }
}

// MARK: - TiledCellContent Conforming Cell

/// A cell wrapper conforming to TiledCellContent for use with TiledView
struct ChatBubbleCell: TiledCellContent {
  typealias StateValue = ChatBubbleCellState

  let item: ChatMessage

  func body(context: CellContext<ChatBubbleCellState>) -> some View {
    ChatBubbleView(message: item, state: context.state)
  }
}

/// A cell wrapper with NavigationLink for use with TiledView
struct ChatBubbleCellWithNavigation: TiledCellContent {
  typealias StateValue = ChatBubbleCellState

  let item: ChatMessage
  let namespace: Namespace.ID
  let useMatchedTransition: Bool

  @ViewBuilder
  func body(context: CellContext<ChatBubbleCellState>) -> some View {
    if #available(iOS 18.0, *), useMatchedTransition {
      NavigationLink(value: item) {
        ChatBubbleView(message: item, state: context.state)
          .matchedTransitionSource(id: item.id, in: namespace)
      }
    } else {
      NavigationLink(value: item) {
        ChatBubbleView(message: item, state: context.state)
      }
    }
  }
}

#Preview("SwiftUI Direct") {
  @Previewable @State var state = CellStateStorage(ChatBubbleCellState())

  ChatBubbleView(
    message: .init(
      id: 1,
      text: "昨日の映画、すごく面白かったです！特にラストシーンが印象的でした。もう一度観たいなと思っています。"
    ),
    state: state
  )
}
struct HostingControllerWrapper<Content: View>: UIViewControllerRepresentable {
  let content: Content

  func makeUIViewController(context: Context) -> UIHostingController<Content> {
    let hostingController = UIHostingController(rootView: content)
    hostingController.view.backgroundColor = .systemBackground
    hostingController.sizingOptions = .intrinsicContentSize
    hostingController._disableSafeArea = true    
    hostingController.view.backgroundColor = .clear
    hostingController.view
      .setContentHuggingPriority(.required, for: .vertical)
    hostingController.view
      .setContentCompressionResistancePriority(.required, for: .vertical)

    return hostingController
  }

  func updateUIViewController(_ uiViewController: UIHostingController<Content>, context: Context) {
    uiViewController.rootView = content
  }
  
  func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: Self.UIViewControllerType, context: Self.Context) -> CGSize? {
    
    var size = uiViewController.view.systemLayoutSizeFitting(
      CGSize(
        width: proposal.width ?? UIView.layoutFittingCompressedSize.width,
        height: 1000
      ),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )
        
    print(size)
                      
    return size
    
    
  }
}
#Preview("UIHostingController") {

  @Previewable @State var size: CGSize = .zero
  @Previewable @State var state = CellStateStorage(ChatBubbleCellState())

  VStack {
    Text("Size: \(size.width) x \(size.height)")
    ZStack {
      HostingControllerWrapper(
        content:
            ChatBubbleView(
              message: .init(
                id: 1,
                text: "昨日の映画、すごく面白かったです！特にラストシーンが印象的でした。もう一度観たいなと思っています。"
              ),
              state: state
            )
      )
    }
    .background(.red)
    .onGeometryChange(for: CGSize.self, of: \.size) { n in
      size = n
    }
  }
}
