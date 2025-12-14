//
//  iMessageDemo.swift
//  MessagingUIDevelopment
//
//  Created by Hiroshi Kimura on 2025/12/14.
//

import SwiftUI
import MessagingUI

// MARK: - iMessage Style Data

struct Message: Identifiable, Hashable, Equatable, Sendable {
  let id: Int
  var text: String
  var isSentByMe: Bool
  var timestamp: Date
}

func generateConversation(count: Int, startId: Int) -> [Message] {
  let conversations: [(String, Bool)] = [
    ("Hey! How's it going?", false),
    ("Pretty good! Just finished work 😊", true),
    ("Nice! Any plans for tonight?", false),
    ("Not really, maybe watch a movie", true),
    ("Want to grab dinner?", false),
    ("Sure! Where?", true),
    ("How about that new Italian place?", false),
    ("Sounds great 👍", true),
    ("Cool, I'll make a reservation for 7pm", false),
    ("Perfect, see you there!", true),
    ("Can't wait! 🍝", false),
    ("Me neither!", true),
  ]

  return (0..<count).map { index in
    let id = startId + index
    let (text, isSentByMe) = conversations[abs(id) % conversations.count]
    return Message(
      id: id,
      text: text,
      isSentByMe: isSentByMe,
      timestamp: Date().addingTimeInterval(Double(id) * 60)
    )
  }
}

// MARK: - iMessage Bubble View

struct MessageBubbleView: View {

  let message: Message

  var body: some View {
    HStack {
      if message.isSentByMe {
        Spacer(minLength: 60)
      }

      VStack(alignment: message.isSentByMe ? .trailing : .leading, spacing: 2) {
        Text(message.text)
          .font(.body)
          .foregroundStyle(message.isSentByMe ? .white : .primary)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(
            RoundedRectangle(cornerRadius: 18)
              .fill(message.isSentByMe ? Color.blue : Color(.systemGray5))
          )

        Text(timeString(from: message.timestamp))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if !message.isSentByMe {
        Spacer(minLength: 60)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 2)
  }

  private func timeString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}

// MARK: - iMessage Demo View

struct iMessageDemo: View {

  @State private var dataSource = ListDataSource<Message>()
  @State private var scrollPosition = TiledScrollPosition()
  @State private var nextPrependId = -1
  @State private var nextAppendId = 0
  @State private var inputText = ""

  var body: some View {
    VStack(spacing: 0) {
      // Messages
      TiledView(
        dataSource: dataSource,
        scrollPosition: $scrollPosition
      ) { message, state in
        MessageBubbleView(message: message)
      }

      Divider()

      // Input bar
      HStack(spacing: 12) {
        TextField("Message", text: $inputText)
          .textFieldStyle(.roundedBorder)

        Button {
          sendMessage()
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.title)
            .foregroundStyle(.blue)
        }
        .disabled(inputText.isEmpty)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.bar)
    }
    .navigationTitle("Messages")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .bottomBar) {
        Button {
          loadOlderMessages()
        } label: {
          Image(systemName: "arrow.up.doc")
        }

        Button {
          loadNewerMessages()
        } label: {
          Image(systemName: "arrow.down.doc")
        }

        Spacer()

        Button {
          scrollPosition.scrollTo(edge: .top)
        } label: {
          Image(systemName: "arrow.up.to.line")
        }

        Button {
          scrollPosition.scrollTo(edge: .bottom)
        } label: {
          Image(systemName: "arrow.down.to.line")
        }

        Spacer()

        Menu {
          Button("Reset") {
            resetConversation()
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .onAppear {
      if dataSource.items.isEmpty {
        resetConversation()
      }
    }
  }

  private func sendMessage() {
    guard !inputText.isEmpty else { return }

    let message = Message(
      id: nextAppendId,
      text: inputText,
      isSentByMe: true,
      timestamp: Date()
    )
    dataSource.append([message])
    nextAppendId += 1
    inputText = ""
    scrollPosition.scrollTo(edge: .bottom, animated: true)
  }

  private func loadOlderMessages() {
    let messages = generateConversation(count: 5, startId: nextPrependId - 4)
    dataSource.prepend(messages)
    nextPrependId -= 5
  }

  private func loadNewerMessages() {
    let messages = generateConversation(count: 5, startId: nextAppendId)
    dataSource.append(messages)
    nextAppendId += 5
  }

  private func resetConversation() {
    nextPrependId = -1
    nextAppendId = 10
    let initialMessages = generateConversation(count: 10, startId: 0)
    dataSource.setItems(initialMessages)
  }
}

#Preview {
  NavigationStack {
    iMessageDemo()
  }
}
