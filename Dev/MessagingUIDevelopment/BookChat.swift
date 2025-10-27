import MessagingUI
import Foundation
import SwiftUI

// MARK: - Previews

private enum MessageSender {
  case me
  case other
}

private struct PreviewMessage: Identifiable {
  let id: UUID
  let text: String
  let sender: MessageSender

  init(id: UUID = UUID(), text: String, sender: MessageSender = .other) {
    self.id = id
    self.text = text
    self.sender = sender
  }
}

struct MessageListPreviewContainer: View {
  @State private var messages: [PreviewMessage] = [
    PreviewMessage(text: "Hello, how are you?", sender: .other),
    PreviewMessage(text: "I'm fine, thank you!", sender: .me),
    PreviewMessage(text: "What about you?", sender: .other),
    PreviewMessage(text: "I'm doing great, thanks for asking!", sender: .me),
  ]
  @State private var isLoadingOlder = false
  @State private var autoScrollToBottom = true
  @State private var olderMessageCounter = 0
  @State private var newMessageCounter = 0

  private static let sampleTexts = [
    "Hey, did you see that?",
    "I totally agree with you",
    "That's interesting!",
    "Can you explain more?",
    "I was thinking the same thing",
    "Wow, really?",
    "Let me check on that",
    "Thanks for sharing",
    "That makes sense",
    "Good point!",
    "I'll get back to you",
    "Sounds good to me",
    "Looking forward to it",
    "Nice work!",
    "Got it, thanks",
    "Let's do this!",
    "Perfect timing",
    "I see what you mean",
    "Absolutely!",
    "That's amazing",
  ]

  var body: some View {
    VStack(spacing: 16) {
      VStack(spacing: 8) {
        Toggle("Auto-scroll to new messages", isOn: $autoScrollToBottom)
          .font(.caption)

        Text("Scroll up to load older messages")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      MessageList(
        messages: messages,
        autoScrollToBottom: $autoScrollToBottom,
        onLoadOlderMessages: {
          print("Loading older messages...")
          try? await Task.sleep(for: .seconds(1))

          // Add older messages at the beginning
          // The scroll position will be automatically maintained
          let newMessages = (0..<5).map { _ in
            let randomText = Self.sampleTexts.randomElement() ?? "Message"
            let sender: MessageSender = Bool.random() ? .me : .other
            return PreviewMessage(text: randomText, sender: sender)
          }
          messages.insert(contentsOf: newMessages.reversed(), at: 0)
        }
      ) { message in
        Text(message.text)
          .padding(12)
          .background(message.sender == .me ? Color.green.opacity(0.2) : Color.blue.opacity(0.1))
          .cornerRadius(8)
          .frame(maxWidth: .infinity, alignment: message.sender == .me ? .trailing : .leading)
      }

      HStack(spacing: 12) {
        Button("Add New Message") {
          let randomText = Self.sampleTexts.randomElement() ?? "Message"
          let sender: MessageSender = Bool.random() ? .me : .other
          messages.append(PreviewMessage(text: randomText, sender: sender))
        }
        .buttonStyle(.borderedProminent)

        Button("Add Old Message") {
          count += 1
        }
        .buttonStyle(.bordered)

        Button("Clear All", role: .destructive) {
          messages.removeAll()
        }
        .buttonStyle(.bordered)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding()
    .task(id: count) { 
      let newMessages = (0..<10).map { _ in
        let randomText = Self.sampleTexts.randomElement() ?? "Message"
        let sender: MessageSender = Bool.random() ? .me : .other
        return PreviewMessage(text: randomText, sender: sender)
      }
      try? await Task.sleep(for: .milliseconds(500))
      messages.insert(contentsOf: newMessages.reversed(), at: 0)
    }
  }
  
  @State var count: Int = 0
}

#Preview("Interactive Preview") {
  MessageListPreviewContainer()
}

#Preview("Simple Preview") {
  MessageList(messages: [
    PreviewMessage(text: "Hello, how are you?", sender: .other),
    PreviewMessage(text: "I'm fine, thank you!", sender: .me),
    PreviewMessage(text: "What about you?", sender: .other),
    PreviewMessage(text: "I'm doing great, thanks for asking!", sender: .me),
  ]) { message in
    Text(message.text)
      .padding(12)
      .background(message.sender == .me ? Color.green.opacity(0.2) : Color.blue.opacity(0.1))
      .cornerRadius(8)
      .frame(maxWidth: .infinity, alignment: message.sender == .me ? .trailing : .leading)
  }
  .padding()
}
