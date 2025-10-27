# swiftui-messaging-ui

A SwiftUI component for building messaging interfaces with support for loading older messages and automatic scroll management.

## Features

- **Message List**: Generic, scrollable message list component
- **Automatic Scroll Management**: Handles scroll position when loading older messages
- **Auto Scroll to Bottom**: Optional automatic scrolling to bottom for new messages
- **Loading State Management**: Internal loading state management with async/await support

## Requirements

- iOS 17.0+
- Swift 6.0+
- Xcode 16.0+

**Note**: This package is iOS-only and requires building with Xcode or xcodebuild.

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
  .package(url: "https://github.com/FluidGroup/swiftui-messaging-ui", from: "1.0.0")
]
```

Or add it through Xcode:
1. File > Add Package Dependencies
2. Enter the repository URL: `https://github.com/FluidGroup/swiftui-messaging-ui`

## Usage

### Basic Example

```swift
import MessagingUI
import SwiftUI

struct Message: Identifiable {
  let id: UUID
  let text: String
}

struct ChatView: View {
  @State private var messages: [Message] = []

  var body: some View {
    MessageList(
      messages: messages,
      onLoadOlderMessages: {
        // Load older messages asynchronously
        let olderMessages = await loadOlderMessages()
        messages.insert(contentsOf: olderMessages, at: 0)
      }
    ) { message in
      Text(message.text)
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
  }

  func loadOlderMessages() async -> [Message] {
    // Your loading logic here
    []
  }
}
```

### With Auto Scroll to Bottom

```swift
MessageList(
  messages: messages,
  autoScrollToBottom: $autoScrollToBottom,
  onLoadOlderMessages: {
    await loadOlderMessages()
  }
) { message in
  MessageView(message: message)
}
```

## API

### MessageList

A generic message list component that displays messages using a custom view builder.

#### Initializers

```swift
// Simple message list without older message loading
init(
  messages: [Message],
  @ViewBuilder content: @escaping (Message) -> Content
)

// Message list with older message loading support
init(
  messages: [Message],
  autoScrollToBottom: Binding<Bool>? = nil,
  onLoadOlderMessages: @escaping @MainActor () async -> Void,
  @ViewBuilder content: @escaping (Message) -> Content
)
```

#### Parameters

- `messages`: Array of messages to display. Must conform to `Identifiable`.
- `autoScrollToBottom`: Optional binding that controls automatic scrolling to bottom when new messages are added.
- `onLoadOlderMessages`: Async closure called when user scrolls up to trigger loading older messages.
- `content`: A view builder that creates the view for each message.

## How It Works

### Scroll Position Management

The component intelligently manages scroll position based on the current state:

1. **Loading Older Messages** (highest priority): When loading older messages, the scroll position is preserved by adjusting the content offset.
2. **Auto Scroll to Bottom**: When enabled, automatically scrolls to the bottom when new messages are added.
3. **Normal Operation**: No scroll adjustment, maintaining the user's current scroll position.

### Loading State

The loading state is managed internally using async/await. When the user scrolls up to the trigger point:

1. The component sets the internal loading flag
2. Calls your `onLoadOlderMessages` closure
3. Automatically adjusts scroll position to maintain the user's viewing context
4. Clears the loading flag after completion

## License

MIT License - See LICENSE file for details

## Author

FluidGroup
