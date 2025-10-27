//
//  MessageList.swift
//  swiftui-messaging-ui
//
//  Created by Hiroshi Kimura on 2025/10/23.
//

import SwiftUI
import SwiftUIIntrospect
import Combine

/// # Spec
///
/// - `MessageList` is a generic, scrollable message list component that displays messages using a custom view builder.
/// - Keeps short lists anchored to the bottom of the scroll view.
/// - Supports loading older messages by scrolling up, with an optional loading indicator at the top.
///
/// ## Usage
///
/// ```swift
/// MessageList(messages: messages) { message in
///   Text(message.text)
///     .padding(12)
///     .background(Color.blue.opacity(0.1))
///     .cornerRadius(8)
/// }
/// ```
public struct MessageList<Message: Identifiable, Content: View>: View {

  public let messages: [Message]
  private let content: (Message) -> Content
  private let autoScrollToBottom: Binding<Bool>?
  private let onLoadOlderMessages: (@MainActor () async -> Void)?

  /// Creates a simple message list without older message loading support.
  ///
  /// - Parameters:
  ///   - messages: Array of messages to display. Must conform to `Identifiable`.
  ///   - content: A view builder that creates the view for each message.
  public init(
    messages: [Message],
    @ViewBuilder content: @escaping (Message) -> Content
  ) {
    self.messages = messages
    self.content = content
    self.autoScrollToBottom = nil
    self.onLoadOlderMessages = nil
  }

  /// Creates a message list with older message loading support.
  ///
  /// - Parameters:
  ///   - messages: Array of messages to display. Must conform to `Identifiable`.
  ///   - autoScrollToBottom: Optional binding that controls automatic scrolling to bottom when new messages are added.
  ///   - onLoadOlderMessages: Async closure called when user scrolls up to trigger loading older messages.
  ///   - content: A view builder that creates the view for each message.
  public init(
    messages: [Message],
    autoScrollToBottom: Binding<Bool>? = nil,
    onLoadOlderMessages: @escaping @MainActor () async -> Void,
    @ViewBuilder content: @escaping (Message) -> Content
  ) {
    self.messages = messages
    self.content = content
    self.autoScrollToBottom = autoScrollToBottom
    self.onLoadOlderMessages = onLoadOlderMessages
  }

  public var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 8) {
          if onLoadOlderMessages != nil {
            Section {
              ForEach(messages) { message in
                content(message)
                  .anchorPreference(
                    key: _VisibleMessagesPreference.self,
                    value: .bounds
                  ) { anchor in
                    [_VisibleMessagePayload(messageId: AnyHashable(message.id), bounds: anchor)]
                  }
              }
            } header: {
              ProgressView()
                .frame(height: 40)
            }
          } else {
            ForEach(messages) { message in
              content(message)
                .anchorPreference(
                  key: _VisibleMessagesPreference.self,
                  value: .bounds
                ) { anchor in
                  [_VisibleMessagePayload(messageId: AnyHashable(message.id), bounds: anchor)]
                }
            }
          }
        }
      }
      .overlayPreferenceValue(_VisibleMessagesPreference.self) { payloads in
        GeometryReader { geometry in
          let sorted = payloads
            .map { payload in
              let rect = geometry[payload.bounds]
              return (id: payload.messageId, y: rect.minY)
            }
            .sorted { $0.y < $1.y }

          VStack(alignment: .leading, spacing: 4) {
            Text("Visible Messages: \(sorted.count)")
              .font(.caption)
              .fontWeight(.bold)

            if let first = sorted.first {
              Text("First: \(String(describing: first.id))")
                .font(.caption2)
              Text("  y=\(String(format: "%.1f", first.y))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if let last = sorted.last {
              Text("Last: \(String(describing: last.id))")
                .font(.caption2)
              Text("  y=\(String(format: "%.1f", last.y))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          .padding(8)
          .background(Color.black.opacity(0.8))
          .foregroundStyle(.white)
          .cornerRadius(8)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .padding()
        }
      }
      .modifier(
        _OlderMessagesLoadingModifier(
          autoScrollToBottom: autoScrollToBottom,
          onLoadOlderMessages: onLoadOlderMessages
        )
      )
    }
  }

}
