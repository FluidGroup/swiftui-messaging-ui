import SwiftUI

// MARK: - Sample Data

struct ChatMessage: Identifiable, Hashable, Equatable, Sendable {
  let id: Int
  var text: String
  var isExpanded: Bool = false
}

func generateSampleMessages(count: Int, startId: Int) -> [ChatMessage] {
  let sampleTexts: [String] = [
    "こんにちは！",
    "今日はいい天気ですね。散歩に行きませんか？",
    "昨日の映画、すごく面白かったです！特にラストシーンが印象的でした。もう一度観たいなと思っています。",
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt",
    "了解です👍",
    "ちょっと待ってください。確認してから返信しますね。",
    "週末の予定はどうですか？もし空いていたら、一緒にカフェでも行きませんか？新しくオープンしたお店があるんですよ。",
    "OK",
    "今から出発します！",
    "長いメッセージのテストです。Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.",
    "🎉🎊✨",
  ]

  return (0..<count).map { index in
    let id = startId + index
    let textIndex = abs(id) % sampleTexts.count
    return ChatMessage(id: id, text: sampleTexts[textIndex])
  }
}

// MARK: - Chat Bubble View

/// Cell with @State to demonstrate state persistence.
/// When cachesCellState is enabled, counter and isExpanded persist across cell reuse.
struct ChatBubbleView: View {

  let message: ChatMessage

  @State private var counter = 0
  @State private var isExpanded = false

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("ID: \(message.id)")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button {
            counter += 1
          } label: {
            Text("\(counter)")
              .font(.caption)
              .monospacedDigit()
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(
                Capsule()
                  .fill(counter > 0 ? Color.blue : Color(.systemGray5))
              )
              .foregroundStyle(counter > 0 ? .white : .secondary)
          }
          .buttonStyle(.plain)
        }

        Text(message.text)
          .font(.system(size: 16))
          .fixedSize(horizontal: false, vertical: true)

        if isExpanded {
          Text("Expanded (local @State)")
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
    .onTapGesture {
      withAnimation(.snappy) {
        isExpanded.toggle()
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
  }
}

#Preview("SwiftUI Direct") {
  ChatBubbleView(
    message: .init(
      id: 1,
      text: "昨日の映画、すごく面白かったです！特にラストシーンが印象的でした。もう一度観たいなと思っています。"
    )
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

  VStack {
    Text("Size: \(size.width) x \(size.height)")
    ZStack {
      HostingControllerWrapper(
        content: 
            ChatBubbleView(
              message: .init(
                id: 1,
                text: "昨日の映画、すごく面白かったです！特にラストシーンが印象的でした。もう一度観たいなと思っています。"
              )
            )
      )
    }
    .background(.red)
    .onGeometryChange(for: CGSize.self, of: \.size) { n in
      size = n
    }
  }
}
