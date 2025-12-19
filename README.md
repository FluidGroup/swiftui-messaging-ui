# swiftui-messaging-ui

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FFluidGroup%2Fswiftui-messaging-ui%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/FluidGroup/swiftui-messaging-ui)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FFluidGroup%2Fswiftui-messaging-ui%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/FluidGroup/swiftui-messaging-ui)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/FluidGroup/swiftui-messaging-ui)

A primitive component to make Chat-UI with **stable prepending** - no scroll jumps when loading older messages.

| Auto Scrolling | Prepending without jumps | Revealing Info |
| :--- | :--- | :-- |
| ![video2](https://github.com/user-attachments/assets/e21ff76e-5b39-45b2-b13b-c608d15414e7)| ![video1](https://github.com/user-attachments/assets/5325bbd0-38bc-4504-868d-e379b2ba3f2f) | ![Simulator Screen Recording - iPhone 17 Pro - 2025-12-19 at 15 45 00](https://github.com/user-attachments/assets/fa654218-9104-4737-ba23-8677c0955fc1)
 |

## The Prepending Problem

Standard SwiftUI `List` and `ScrollView` cause **scroll position jumps** when prepending items. In chat apps, loading older messages creates jarring visual shifts as content is inserted above the current view.

### contentOffset Adjustment is Fragile

A common workaround is adjusting `contentOffset` after prepending. However, this requires:
- Precise timing of when prepend operations complete
- Exact knowledge of inserted content height before layout
- Careful handling when multiple operations occur together (prepend + update + remove)

In practice, this approach breaks easily with complex data flows.

### The Virtual Layout Solution

This library takes a different approach: a **virtual content layout** with a 100-million-point content space where items are anchored at the center. Prepending simply extends content upward without ever changing `contentOffset`, eliminating the timing and coordination problems entirely.

## Key Features

- **Smooth Prepend/Append** - No scroll jumps when loading older or newer messages
- **Change Tracking** - Efficient incremental updates without full reloads
- **UICollectionView Performance** - Native recycling with SwiftUI cell rendering
- **Self-Sizing Cells** - Automatic height calculation for variable content
- **Per-Cell State** - Manage UI state (expansion, selection) separately from data
- **Keyboard & Safe Area Handling** - Automatic content inset adjustment for keyboard and safe areas

## Requirements

- iOS 17.0+
- Swift 6.0+
- Xcode 26.0+

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

struct Message: Identifiable, Equatable {
  let id: Int
  var text: String
  var isFromMe: Bool
  var timestamp: Date
}

// Define your cell using TiledCellContent protocol
struct MessageBubbleCell: TiledCellContent {
  let item: Message

  func body(context: CellContext) -> some View {
    HStack {
      if item.isFromMe { Spacer() }
      Text(item.text)
        .padding(12)
        .background(item.isFromMe ? Color.blue : Color.gray.opacity(0.3))
        .foregroundStyle(item.isFromMe ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
      if !item.isFromMe { Spacer() }
    }
    .padding(.horizontal)
  }
}

struct ChatView: View {
  @State private var dataSource = ListDataSource<Message>()
  @State private var scrollPosition = TiledScrollPosition()

  var body: some View {
    TiledView(
      dataSource: dataSource,
      scrollPosition: $scrollPosition
    ) { message, _ in
      MessageBubbleCell(item: message)
    }
    .task {
      dataSource.apply(initialMessages)
    }
  }
}
```

### Loading Older Messages

```swift
TiledView(
  dataSource: dataSource,
  scrollPosition: $scrollPosition,
  onPrepend: {
    // Called when user scrolls near the top
    let olderMessages = await fetchOlderMessages()
    dataSource.prepend(olderMessages)

    // Or if you have the complete list, use apply() - it auto-detects changes
    // let allMessages = await fetchAllMessages()
    // dataSource.apply(allMessages)
  }
) { message, _ in
  MessageBubbleCell(item: message)
}
```

### Programmatic Scrolling

```swift
@State private var scrollPosition = TiledScrollPosition()

// Scroll to bottom
Button("Scroll to Bottom") {
  scrollPosition.scrollTo(edge: .bottom)
}

// Scroll to top
Button("Scroll to Top") {
  scrollPosition.scrollTo(edge: .top, animated: false)
}
```

### Swipe to Reveal Timestamps

iMessage-style horizontal swipe gesture to reveal timestamps. Use `CellContext` to access the reveal offset:

```swift
struct MessageBubbleCell: TiledCellContent {
  let item: Message

  func body(context: CellContext) -> some View {
    // Get the reveal offset with rubber band effect
    let offset = context.cellReveal?.rubberbandedOffset(max: 60) ?? 0

    HStack(alignment: .bottom, spacing: 8) {
      if item.isFromMe {
        Spacer()
        // Timestamp fades in as user swipes
        Text(item.timestamp, style: .time)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .opacity(offset / 40)

        MessageBubble(message: item)
          .offset(x: -offset)  // Slide left to reveal
      } else {
        MessageBubble(message: item)
          .offset(x: -offset)

        Text(item.timestamp, style: .time)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .opacity(offset / 40)
        Spacer()
      }
    }
  }
}
```

To disable the reveal gesture:

```swift
TiledView(...)
  .revealConfiguration(.disabled)
```
