import SwiftUI

struct ChatBubbleView: View {

  let message: ChatMessage

  @State private var isLocalExpanded: Bool = true

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("ID: \(message.id)")
            .font(.caption)
            .foregroundStyle(.secondary)

          Spacer()

          Image(systemName: isLocalExpanded ? "chevron.up" : "chevron.down")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text(message.text)
          .font(.system(size: 16))
        

        if message.isExpanded {
          Text("(DataSource expanded)")
            .font(.system(size: 14))
            .foregroundStyle(.orange)
        }

        if isLocalExpanded {
          VStack(alignment: .leading, spacing: 10) {
            Text("Local expanded content")
              .font(.system(size: 14))
              .foregroundStyle(.blue)
            
            Text("This is additional content that appears when you tap the cell. It demonstrates that local @State changes can also affect cell height.")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
//              .fixedSize(horizontal: false, vertical: true)

            HStack {
              ForEach(0..<3) { i in
                Circle()
                  .fill(Color.blue.opacity(0.3))
                  .frame(width: 30, height: 30)
                  .overlay(Text("\(i + 1)").font(.caption2))
              }
            }
          }          
          .padding(.top, 8)
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
      withAnimation(.smooth) {        
        isLocalExpanded.toggle()
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.init(white: 0.1, opacity: 0.5))
 
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
    hostingController.view
      .setContentCompressionResistancePriority(.required, for: .vertical)
    hostingController.view.backgroundColor = .clear
    hostingController.safeAreaRegions = []

    return hostingController
  }

  func updateUIViewController(_ uiViewController: UIHostingController<Content>, context: Context) {
    uiViewController.rootView = content
  }
  
  func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: Self.UIViewControllerType, context: Self.Context) -> CGSize? {
    
    var size = uiViewController.sizeThatFits(
     in: CGSize(
        width: proposal.width ?? UIView.layoutFittingCompressedSize.width,
        height: proposal.height ?? UIView.layoutFittingCompressedSize.height
      )
    )
//           size.height += 80
    print(size)
                      

    return size
    
    
  }
}
#Preview("UIHostingController") {
 

  ZStack {
    HostingControllerWrapper(
      content: ChatBubbleView(
        message: .init(
          id: 1,
          text: "昨日の映画、すごく面白かったです！特にラストシーンが印象的でした。もう一度観たいなと思っています。"
        )
      )
    )
  }
  .background(.red)
  .onGeometryChange(for: CGSize.self, of: \.size) { n in
    print("Size changed: \(n)")
  }
}
