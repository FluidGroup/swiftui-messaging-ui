# swiftui-messaging-ui

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/FluidGroup/swiftui-messaging-ui)

A high-performance SwiftUI list component built on UICollectionView, designed for messaging interfaces and infinite scrolling lists.

## Features

- **TiledView**: High-performance list view using UICollectionView with custom layout
- **ListDataSource**: Change-tracking data source with efficient diff detection
- **CellState**: Type-safe per-cell state management
- **Scroll Position Control**: Programmatic scrolling with SwiftUI-like API
- **Prepend Support**: Maintains scroll position when loading older content
- **Self-Sizing Cells**: Automatic cell height calculation

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
      dataSource.setItems(initialMessages)
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

```swift
var dataSource = ListDataSource<Message>()

// Initial load
dataSource.setItems(messages)

// Add to beginning (older messages)
dataSource.prepend(olderMessages)

// Add to end (new messages)
dataSource.append(newMessages)

// Insert at specific position
dataSource.insert(messages, at: 5)

// Update existing items
dataSource.update([updatedMessage])

// Remove items
dataSource.remove(id: messageId)
dataSource.remove(ids: [id1, id2, id3])

// Auto-detect changes from new array
dataSource.applyDiff(from: newMessagesArray)
```

## API Reference

### TiledView

A SwiftUI view that wraps UICollectionView for high-performance list rendering.

```swift
public struct TiledView<Item: Identifiable & Equatable, Cell: View>: UIViewRepresentable {
  public init(
    dataSource: ListDataSource<Item>,
    scrollPosition: Binding<TiledScrollPosition>,
    cellStates: [Item.ID: CellState]? = nil,
    onPrepend: (@MainActor () async throws -> Void)? = nil,
    @ViewBuilder cellBuilder: @escaping (Item, CellState) -> Cell
  )
}
```

### ListDataSource

A change-tracking data source that enables efficient list updates.

```swift
public struct ListDataSource<Item: Identifiable & Equatable> {
  public var items: Deque<Item> { get }
  public var changeCounter: Int { get }

  public mutating func setItems(_ items: [Item])
  public mutating func prepend(_ items: [Item])
  public mutating func append(_ items: [Item])
  public mutating func insert(_ items: [Item], at index: Int)
  public mutating func update(_ items: [Item])
  public mutating func remove(id: Item.ID)
  public mutating func remove(ids: [Item.ID])
  public mutating func applyDiff(from newItems: [Item])
}
```

### TiledScrollPosition

A struct for programmatic scroll control, similar to SwiftUI's `ScrollPosition`.

```swift
public struct TiledScrollPosition {
  public enum Edge {
    case top
    case bottom
  }

  public mutating func scrollTo(edge: Edge, animated: Bool = true)
}
```

### CellState

Type-safe per-cell state storage.

```swift
public protocol CustomStateKey {
  associatedtype Value
  static var defaultValue: Value { get }
}

public struct CellState {
  public static var empty: CellState { get }
  public subscript<T: CustomStateKey>(key: T.Type) -> T.Value { get set }
}
```

## How It Works

### Virtual Content Layout

TiledView uses a custom UICollectionViewLayout with virtual content height. This enables:
- Efficient prepend operations without scroll jumps
- Smooth bidirectional scrolling
- Minimal memory footprint

### Change Tracking

ListDataSource tracks every mutation as a `Change` enum:
- `.setItems` - Complete replacement
- `.prepend([ID])` - Items added to beginning
- `.append([ID])` - Items added to end
- `.insert(at:, ids:)` - Items inserted at index
- `.update([ID])` - Existing items modified
- `.remove([ID])` - Items removed

TiledView applies only new changes since its last update, ensuring optimal performance.

## License

MIT License - See LICENSE file for details

## Author

FluidGroup
