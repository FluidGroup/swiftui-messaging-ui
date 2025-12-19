//
//  MessengerDemo.swift
//  MessagingUIDevelopment
//
//  Simple messenger demo using TiledView.
//

import SwiftUI
import MessagingUI

// MARK: - Message Model

struct Message: Identifiable, Hashable, Equatable, Sendable, MessageContent {
  let id: Int
  var text: String
  var isSentByMe: Bool
  var timestamp: Date
}

// MARK: - Sample Data Generator

func generateConversation(count: Int, startId: Int) -> [Message] {
  let conversations: [(String, Bool)] = [
    ("Hey! How's it going?", false),
    ("Pretty good! Just finished work", true),
    ("Nice! Any plans for tonight?", false),
    ("Not really, maybe watch a movie", true),
    ("Want to grab dinner?", false),
    ("Sure! Where?", true),
    ("How about that new Italian place?", false),
    ("Sounds great", true),
    ("Cool, I'll make a reservation for 7pm", false),
    ("Perfect, see you there!", true),
    ("Can't wait!", false),
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

// MARK: - MessengerDemo View

struct MessengerDemo: View {

  @State private var dataSource = ListDataSource<Message>()
  @State private var scrollPosition = TiledScrollPosition()
  @State private var nextPrependId = -1
  @State private var nextAppendId = 0
  @State private var inputText = ""
  @State private var isPrependLoading = false
  @State private var isAppendLoading = false

  var body: some View {
    VStack(spacing: 0) {
      // Messages
      TiledView(
        dataSource: dataSource,
        scrollPosition: $scrollPosition
      ) { message, state in
        MessageBubbleCell(item: message)
      }
      .revealConfiguration(.default)
      .prependLoadingIndicator(isLoading: isPrependLoading) {
        HStack(spacing: 8) {
          ProgressView()
          Text("Loading older messages...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
      }
      .appendLoadingIndicator(isLoading: isAppendLoading) {
        HStack(spacing: 8) {
          ProgressView()
          Text("Loading newer messages...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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
    guard !isPrependLoading else { return }
    isPrependLoading = true
    Task {
      try? await Task.sleep(for: .seconds(1))
      let messages = generateConversation(count: 5, startId: nextPrependId - 4)
      dataSource.prepend(messages)
      nextPrependId -= 5
      isPrependLoading = false
    }
  }

  private func loadNewerMessages() {
    guard !isAppendLoading else { return }
    isAppendLoading = true
    Task {
      try? await Task.sleep(for: .seconds(1))
      let messages = generateConversation(count: 5, startId: nextAppendId)
      dataSource.append(messages)
      nextAppendId += 5
      isAppendLoading = false
    }
  }

  private func resetConversation() {
    nextPrependId = -1
    nextAppendId = 10
    let initialMessages = generateConversation(count: 10, startId: 0)
    dataSource.replace(with: initialMessages)
  }
}

#Preview {
  NavigationStack {
    MessengerDemo()
  }
}
