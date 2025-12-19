//
//  MessageBubbleView.swift
//  MessagingUIDevelopment
//
//  Shared message bubble view with swipe-to-reveal timestamp support.
//

import SwiftUI
import MessagingUI

// MARK: - MessageContent Protocol

/// Protocol for message content that can be displayed in MessageBubbleView.
protocol MessageContent {
  var text: String { get }
  var isSentByMe: Bool { get }
  var timestamp: Date { get }
}

// MARK: - MessageBubbleView

/// iMessage-style bubble view with swipe-to-reveal timestamp.
struct MessageBubbleView<Content: MessageContent>: View {

  let message: Content

  @Environment(\.cellReveal) private var cellReveal

  private let maxRevealOffset: CGFloat = 60

  private static var timeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter
  }

  var body: some View {
    let revealOffset = cellReveal?.rubberbandedOffset(max: maxRevealOffset) ?? 0

    HStack(spacing: 0) {
      if message.isSentByMe {
        Spacer(minLength: 60)
      }

      bubbleContent

      if !message.isSentByMe {
        Spacer(minLength: 60)
      }
    }
    .offset(x: -revealOffset)
    .overlay(alignment: .trailing) {
      // Timestamp hidden off-screen, revealed on swipe
      Text(Self.timeFormatter.string(from: message.timestamp))
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
    Text(message.text)
      .font(.body)
      .foregroundStyle(message.isSentByMe ? .white : .primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 18)
          .fill(message.isSentByMe ? Color.blue : Color(.systemGray5))
      )
  }
}

// MARK: - MessageBubbleView with Status

/// Extended bubble view that shows message status (for sent messages).
struct MessageBubbleWithStatusView<Content: MessageContentWithStatus>: View {

  let message: Content

  @Environment(\.cellReveal) private var cellReveal

  private let maxRevealOffset: CGFloat = 60

  private static var timeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter
  }

  var body: some View {
    let revealOffset = cellReveal?.rubberbandedOffset(max: maxRevealOffset) ?? 0

    HStack(spacing: 0) {
      if message.isSentByMe {
        Spacer(minLength: 60)
      }

      bubbleContent

      if !message.isSentByMe {
        Spacer(minLength: 60)
      }
    }
    .offset(x: -revealOffset)
    .overlay(alignment: .trailing) {
      // Timestamp + status hidden off-screen, revealed on swipe
      VStack(alignment: .trailing, spacing: 2) {
        Text(Self.timeFormatter.string(from: message.timestamp))
          .font(.caption2)
          .foregroundStyle(.secondary)

        if message.isSentByMe {
          statusIcon
        }
      }
      .frame(width: maxRevealOffset)
      .offset(x: maxRevealOffset - revealOffset)
    }
    .clipped()
    .padding(.horizontal, 12)
    .padding(.vertical, 2)
  }

  private var bubbleContent: some View {
    Text(message.text)
      .font(.body)
      .foregroundStyle(message.isSentByMe ? .white : .primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 18)
          .fill(bubbleColor)
      )
  }

  private var bubbleColor: Color {
    if message.isSentByMe {
      return message.status == .failed ? .red : .blue
    } else {
      return Color(.systemGray5)
    }
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch message.status {
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
