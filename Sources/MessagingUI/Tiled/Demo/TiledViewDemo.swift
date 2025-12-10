//
//  TiledViewDemo.swift
//  TiledView
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import SwiftUI

// MARK: - Sample Data

struct ChatMessage: Identifiable, Hashable, Sendable {
  let id: Int
  let text: String
}

private func generateSampleMessages(count: Int, startId: Int) -> [ChatMessage] {
  let sampleTexts = [
    "こんにちは！",
    "今日はいい天気ですね。散歩に行きませんか？",
    "昨日の映画、すごく面白かったです！特にラストシーンが印象的でした。もう一度観たいなと思っています。",
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

private struct ChatBubbleView: View {
  let message: ChatMessage

  var body: some View {
    HStack {
      Text(message.text)
        .font(.system(size: 16))
        .foregroundStyle(.primary)
        .padding(12)
        .background(
          RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray6))
        )

      Spacer(minLength: 44)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }
}

// MARK: - Height Calculator

private func calculateCellHeight(for message: ChatMessage, width: CGFloat) -> CGFloat {
  let padding: CGFloat = 12
  let maxBubbleWidth = width - 60

  let label = UILabel()
  label.numberOfLines = 0
  label.font = .systemFont(ofSize: 16)
  label.text = message.text

  let labelSize = label.sizeThatFits(CGSize(width: maxBubbleWidth - padding * 2, height: .greatestFiniteMagnitude))
  return labelSize.height + padding * 2 + 16
}

// MARK: - Demo View

struct BookTiledView: View {

  @State private var viewController: TiledViewController<ChatMessage, ChatBubbleView>?
  @State private var nextPrependId = -1
  @State private var nextAppendId = 20

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("Prepend 5") {
          guard let viewController else { return }
          let messages = generateSampleMessages(count: 5, startId: nextPrependId - 4)
          viewController.prependItems(messages)
          nextPrependId -= 5
        }

        Spacer()

        Button("Append 5") {
          guard let viewController else { return }
          let messages = generateSampleMessages(count: 5, startId: nextAppendId)
          viewController.appendItems(messages)
          nextAppendId += 5
        }
      }
      .padding()
      .background(Color(.systemBackground))

      TiledViewRepresentable(
        viewController: $viewController,
        items: [],
        cellBuilder: { message in
          ChatBubbleView(message: message)
        },
        heightCalculator: calculateCellHeight
      )
      .onAppear {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          let initial = generateSampleMessages(count: 20, startId: 0)
          viewController?.setItems(initial)
        }
      }
    }
  }
}

#Preview("TiledView Demo") {
  BookTiledView()
}
