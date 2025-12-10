//
//  TiledViewDemo.swift
//  TiledView
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import SwiftUI
import MessagingUI

// MARK: - Sample Data

struct ChatMessage: Identifiable, Hashable, Equatable, Sendable {
  let id: Int
  var text: String
  var isExpanded: Bool = false
}

private func generateSampleMessages(count: Int, startId: Int) -> [ChatMessage] {
  let sampleTexts = [
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



// MARK: - Demo View

struct BookTiledView: View {

  @State private var dataSource: TiledDataSource<ChatMessage>
  @State private var nextPrependId = -1
  @State private var nextAppendId = 20

  init() {
    let initial = generateSampleMessages(count: 20, startId: 0)
    _dataSource = State(initialValue: TiledDataSource(items: initial))
  }

  var body: some View {
    VStack(spacing: 0) {
      controlPanel
        .padding()
        .background(Color(.systemBackground))

      TiledViewRepresentable(
        dataSource: dataSource,
        cellBuilder: { message in
          ChatBubbleView(message: message)
        }
      )
    }
  }

  @ViewBuilder
  private var controlPanel: some View {
    VStack(spacing: 12) {
      // Row 1: Prepend / Append
      HStack {
        Button("Prepend 5") {
          let messages = generateSampleMessages(count: 5, startId: nextPrependId - 4)
          dataSource.prepend(messages)
          nextPrependId -= 5
        }
        .buttonStyle(.bordered)

        Spacer()

        Button("Append 5") {
          let messages = generateSampleMessages(count: 5, startId: nextAppendId)
          dataSource.append(messages)
          nextAppendId += 5
        }
        .buttonStyle(.bordered)
      }

      // Row 2: Update / Remove
      HStack {
        Button("Update ID:5") {
          if var item = dataSource.items.first(where: { $0.id == 5 }) {
            item.isExpanded.toggle()
            item.text = item.isExpanded ? "UPDATED & EXPANDED!" : "Updated back"
            dataSource.update([item])
          }
        }
        .buttonStyle(.bordered)

        Spacer()

        Button("Remove ID:10") {
          dataSource.remove(id: 10)
        }
        .buttonStyle(.bordered)
      }

      // Row 3: SetItems (Reset)
      HStack {
        Button("Reset (5 items)") {
          nextPrependId = -1
          nextAppendId = 5
          let newItems = generateSampleMessages(count: 5, startId: 0)
          dataSource.setItems(newItems)
        }
        .buttonStyle(.borderedProminent)

        Spacer()

        Text("Count: \(dataSource.items.count)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

#Preview("TiledView Demo") {
  BookTiledView()
}
