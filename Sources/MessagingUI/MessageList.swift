//
//  MessageList.swift
//  swiftui-messaging-ui
//
//  Created by Hiroshi Kimura on 2025/10/23.
//

import SwiftUI
import SwiftUIIntrospect
import Combine

/// Change type for MessageList to track prepend/append operations.
public enum ListDataSourceChangeType: Equatable, Sendable {
  case setItems
  case prepend
  case append
  case update
  case remove
}

/// # Spec
///
/// - `MessageList` is a generic, scrollable message list component that displays messages using a custom view builder.
/// - Keeps short lists anchored to the bottom of the scroll view.
/// - Supports loading older messages by scrolling up, with an optional loading indicator at the top.
///
/// ## Usage
///
/// ```swift
/// @State private var dataSource = ListDataSource<ChatMessage>(items: messages)
///
/// MessageList(dataSource: dataSource) { message in
///   Text(message.text)
///     .padding(12)
///     .background(Color.blue.opacity(0.1))
///     .cornerRadius(8)
/// }
/// ```
public struct MessageList<Message: Identifiable & Equatable, Content: View>: View {

  private let dataSource: ListDataSource<Message>
  private let content: (Message) -> Content
  private let autoScrollToBottom: Binding<Bool>?

  private var lastChangeType: ListDataSourceChangeType? {
    dataSource.pendingChanges.last.map { change in
      switch change {
      case .setItems: return .setItems
      case .prepend: return .prepend
      case .append: return .append
      case .update: return .update
      case .remove: return .remove
      }
    }
  }

  /// Creates a message list using a ListDataSource for change tracking.
  ///
  /// This initializer automatically detects prepend/append operations from the
  /// data source's change history, enabling proper scroll position preservation.
  ///
  /// - Parameters:
  ///   - dataSource: A ListDataSource that tracks changes for efficient updates.
  ///   - autoScrollToBottom: Optional binding that controls automatic scrolling to bottom when new messages are added.
  ///   - content: A view builder that creates the view for each message.
  public init(
    dataSource: ListDataSource<Message>,
    autoScrollToBottom: Binding<Bool>? = nil,
    @ViewBuilder content: @escaping (Message) -> Content
  ) {
    self.dataSource = dataSource
    self.content = content
    self.autoScrollToBottom = autoScrollToBottom
  }

  public var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(dataSource.items) { message in
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
          onLoadOlderMessages: nil,
          lastChangeType: lastChangeType
        )
      )
    }
  }

}
