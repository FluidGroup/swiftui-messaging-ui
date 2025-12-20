//
//  ListDemo.swift
//  MessagingUIDevelopment
//
//  Created by Hiroshi Kimura on 2025/12/21.
//

import SwiftUI

struct ListDemo: View {

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
      List {
        ForEach(messages) { message in
          MessageRow(message: message)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)

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
    .navigationTitle("List Demo")
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
      "I've heard List can have issues with large datasets.",
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
    @State private var reactionCount: Int = 0

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
                  if isLiked {
                    reactionCount += 1
                  }
                }
              } label: {
                HStack(spacing: 4) {
                  Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.caption)
                    .foregroundStyle(isLiked ? .red : .secondary)
                  if reactionCount > 0 {
                    Text("\(reactionCount)")
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                  }
                }
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
    ListDemo()
  }
}
