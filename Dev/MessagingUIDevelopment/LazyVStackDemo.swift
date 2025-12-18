//
//  LazyVStackDemo.swift
//  MessagingUIDevelopment
//
//  Created by Hiroshi Kimura on 2025/12/18.
//

import SwiftUI

struct LazyVStackDemo: View {

  struct Message: Identifiable {
    let id: UUID
    let text: String
    let isMe: Bool
    let timestamp: Date
  }

  @State private var messages: [Message] = []
  @State private var inputText: String = ""

  var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(messages) { message in
              MessageRow(message: message)
                .id(message.id)
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
        }
        .onChange(of: messages.count) {
          if let last = messages.last {
            withAnimation {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
        }
      }

      Divider()

      HStack(spacing: 12) {
        TextField("Message", text: $inputText)
          .textFieldStyle(.roundedBorder)

        Button {
          sendMessage()
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.title)
        }
        .disabled(inputText.isEmpty)
      }
      .padding()
    }
    .navigationTitle("LazyVStack Demo")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Add 10 messages") {
            generateMessages(count: 10)
          }
          Button("Add 100 messages") {
            generateMessages(count: 100)
          }
          Button("Add 1000 messages") {
            generateMessages(count: 1000)
          }
          Divider()
          Button("Clear", role: .destructive) {
            messages.removeAll()
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .onAppear {
      generateMessages(count: 20)
    }
  }

  private func sendMessage() {
    guard !inputText.isEmpty else { return }
    let message = Message(
      id: UUID(),
      text: inputText,
      isMe: true,
      timestamp: Date()
    )
    messages.append(message)
    inputText = ""
  }

  private func generateMessages(count: Int) {
    let sampleTexts = [
      "Hello!",
      "How are you?",
      "I'm doing great, thanks for asking!",
      "What's up?",
      "Just working on some code.",
      "That sounds interesting. What kind of project?",
      "Building a messaging UI component for SwiftUI.",
      "Nice! SwiftUI is really powerful for building UIs.",
      "Yes, but there are some tricky parts with scroll performance.",
      "I've heard LazyVStack can have issues with large lists.",
      "That's why I'm exploring UICollectionView-based solutions.",
      "Makes sense. UIKit has more mature APIs for that.",
    ]

    for i in 0..<count {
      let message = Message(
        id: UUID(),
        text: sampleTexts[i % sampleTexts.count],
        isMe: i % 2 == 0,
        timestamp: Date().addingTimeInterval(Double(i) * -60)
      )
      messages.append(message)
    }
  }

  struct MessageRow: View {
    let message: Message
    @State private var isExpanded: Bool = false
    @State private var isLiked: Bool = false

    var body: some View {
      HStack {
        if message.isMe { Spacer(minLength: 60) }

        VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
          Text(message.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.isMe ? Color.blue : Color(.systemGray5))
            .foregroundStyle(message.isMe ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture {
              withAnimation(.snappy) {
                isExpanded.toggle()
              }
            }

          if isExpanded {
            HStack(spacing: 12) {
              Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)

              Button {
                withAnimation(.snappy) {
                  isLiked.toggle()
                }
              } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                  .font(.caption)
                  .foregroundStyle(isLiked ? .red : .secondary)
              }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
          }
        }

        if !message.isMe { Spacer(minLength: 60) }
      }
    }
  }
}

#Preview {
  NavigationStack {
    LazyVStackDemo()
  }
}
