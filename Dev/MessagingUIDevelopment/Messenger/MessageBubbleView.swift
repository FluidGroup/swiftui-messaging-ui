//
//  MessageBubbleView.swift
//  MessagingUIDevelopment
//
//  Shared message bubble cell with swipe-to-reveal timestamp support.
//

import SwiftUI
import MessagingUI

// MARK: - MessageContent Protocol

/// Protocol for message content that can be displayed in MessageBubbleCell.
protocol MessageContent {
  var text: String { get }
  var isSentByMe: Bool { get }
  var timestamp: Date { get }
}

// MARK: - MessageBubbleCell

/// iMessage-style bubble cell with swipe-to-reveal timestamp.
///
/// Uses `TiledCellContent` protocol to receive reveal offset from context
/// instead of reading from `@Environment`.
struct MessageBubbleCell<Content: MessageContent>: TiledCellContent {
  typealias StateValue = Void

  let item: Content

  private let maxRevealOffset: CGFloat = 60

  private static var timeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter
  }

  func body(context: CellContext<Void>) -> some View {
    let revealOffset = context.cellReveal?.rubberbandedOffset(max: maxRevealOffset) ?? 0

    HStack(spacing: 0) {
      if item.isSentByMe {
        Spacer(minLength: 60)
      }

      bubbleContent

      if !item.isSentByMe {
        Spacer(minLength: 60)
      }
    }
    .offset(x: -revealOffset)
    .overlay(alignment: .trailing) {
      // Timestamp hidden off-screen, revealed on swipe
      Text(Self.timeFormatter.string(from: item.timestamp))
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(width: maxRevealOffset)
        .offset(x: maxRevealOffset - revealOffset)
    }
    .clipped()
    .padding(.horizontal, 12)
    .padding(.vertical, 2)
  }

  private var bubbleContent: some View {
    Text(item.text)
      .font(.body)
      .foregroundStyle(item.isSentByMe ? .white : .primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 18)
          .fill(item.isSentByMe ? Color.blue : Color(.systemGray5))
      )
  }
}

// MARK: - MessageBubbleWithStatusCell

/// Extended bubble cell that shows message status (for sent messages).
struct MessageBubbleWithStatusCell<Content: MessageContentWithStatus>: TiledCellContent {
  typealias StateValue = Void

  let item: Content

  private let maxRevealOffset: CGFloat = 60

  private static var timeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter
  }

  func body(context: CellContext<Void>) -> some View {
    let revealOffset = context.cellReveal?.rubberbandedOffset(max: maxRevealOffset) ?? 0

    HStack(spacing: 0) {
      if item.isSentByMe {
        Spacer(minLength: 60)
      }

      bubbleContent

      if !item.isSentByMe {
        Spacer(minLength: 60)
      }
    }
    .offset(x: -revealOffset)
    .overlay(alignment: .trailing) {
      // Timestamp + status hidden off-screen, revealed on swipe
      VStack(alignment: .trailing, spacing: 2) {
        Text(Self.timeFormatter.string(from: item.timestamp))
          .font(.caption2)
          .foregroundStyle(.secondary)

        if item.isSentByMe {
          statusIcon
        }
      }
      .frame(width: maxRevealOffset)
      .offset(x: maxRevealOffset - revealOffset)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 2)
  }

  private var bubbleContent: some View {
    Text(item.text)
      .font(.body)
      .foregroundStyle(item.isSentByMe ? .white : .primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 18)
          .fill(bubbleColor)
      )
  }

  private var bubbleColor: Color {
    if item.isSentByMe {
      return item.status == .failed ? .red : .blue
    } else {
      return Color(.systemGray5)
    }
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch item.status {
    case .sending:
      ProgressView()
        .scaleEffect(0.5)
        .frame(width: 12, height: 12)
    case .sent:
      Image(systemName: "checkmark")
        .font(.caption2)
        .foregroundStyle(.secondary)
    case .delivered:
      Image(systemName: "checkmark")
        .font(.caption2)
        .foregroundStyle(.blue)
    case .read:
      Image(systemName: "checkmark.circle.fill")
        .font(.caption2)
        .foregroundStyle(.blue)
    case .failed:
      Image(systemName: "exclamationmark.circle.fill")
        .font(.caption2)
        .foregroundStyle(.red)
    }
  }
}

// MARK: - MessageContentWithStatus Protocol

/// Protocol for message content with delivery status.
protocol MessageContentWithStatus: MessageContent {
  var status: MessageStatus { get }
}

/// Message delivery status.
enum MessageStatus: Int, Codable {
  case sending = 0
  case sent = 1
  case delivered = 2
  case read = 3
  case failed = 4
}
