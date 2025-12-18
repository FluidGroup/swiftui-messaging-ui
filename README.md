# swiftui-messaging-ui

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FFluidGroup%2Fswiftui-messaging-ui%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/FluidGroup/swiftui-messaging-ui)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FFluidGroup%2Fswiftui-messaging-ui%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/FluidGroup/swiftui-messaging-ui)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/FluidGroup/swiftui-messaging-ui)

A SwiftUI list component with **stable prepending** - no scroll jumps when loading older messages.

| Auto Scrolling | Prepending without jumps |
| :--- | :--- |
| ![video2](https://github.com/user-attachments/assets/e21ff76e-5b39-45b2-b13b-c608d15414e7)| ![video1](https://github.com/user-attachments/assets/5325bbd0-38bc-4504-868d-e379b2ba3f2f) |

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

## Requirements

- iOS 17.0+
- Swift 6.0+
- Xcode 26.0+

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

struct Message: Identifiable, Equatable {
  let id: Int
  var text: String
}

struct ChatView: View {
  @State private var dataSource = ListDataSource<Message>()
  @State private var scrollPosition = TiledScrollPosition()

  var body: some View {
    TiledView(
      dataSource: dataSource,
      scrollPosition: $scrollPosition,
      cellBuilder: { message, _ in
        MessageBubble(message: message)
      }
    )
    .onAppear {
      dataSource.replace(with: initialMessages)
    }
  }
}
```

### Loading Older Messages (Prepend)

```swift
TiledView(
  dataSource: dataSource,
  scrollPosition: $scrollPosition,
  onPrepend: {
    // Called when user scrolls near the top
    let olderMessages = await loadOlderMessages()
    dataSource.prepend(olderMessages)
  },
  cellBuilder: { message, _ in
    MessageBubble(message: message)
  }
)
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

### Using CellState

CellState allows you to manage per-cell UI state (like expansion, selection) separately from your data model.

```swift
// 1. Define a state key
enum IsExpandedKey: CustomStateKey {
  typealias Value = Bool
  static var defaultValue: Bool { false }
}

// 2. Add convenience accessor
extension CellState {
  var isExpanded: Bool {
    get { self[IsExpandedKey.self] }
    set { self[IsExpandedKey.self] = newValue }
  }
}

// 3. Use in cell builder
TiledView(
  dataSource: dataSource,
  scrollPosition: $scrollPosition,
  cellBuilder: { message, state in
    MessageBubble(
      message: message,
      isExpanded: state.isExpanded
    )
  }
)
```

### ListDataSource Operations

**Recommended:** Use `apply(_:)` for most cases. It automatically detects the appropriate operation (replace, prepend, append, insert, update, remove).

```swift
var dataSource = ListDataSource<Message>()

// Recommended: Auto-detect changes from new array
dataSource.apply(newMessagesArray)

// Manual operations (when you know the exact change type)
dataSource.replace(with: messages)       // Replace all items
dataSource.prepend(olderMessages)        // Add to beginning
dataSource.append(newMessages)           // Add to end
dataSource.insert(messages, at: 5)       // Insert at position
dataSource.updateExisting([updated])     // Update existing items
dataSource.remove(id: messageId)         // Remove by ID
dataSource.remove(ids: [id1, id2, id3])  // Remove multiple
```
