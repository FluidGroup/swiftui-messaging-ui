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
          VStack(alignment: .leading, spacing: 8) {
            Text("Local expanded content")
              .font(.system(size: 14))
              .foregroundStyle(.blue)

            Text("This is additional.")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
            
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
          
//          .padding(.top, 8)
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

#Preview {
  ChatBubbleView(
    message: .init(
      id: 1,
      text: "昨日の映画、すごく面白かったです！特にラストシーンが印象的でした。もう一度観たいなと思っています。"
    )
  )
}
