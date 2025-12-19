# ``MessagingUI``

A SwiftUI framework for building messaging interfaces with smooth bidirectional scrolling.

## Overview

MessagingUI provides components for building chat-like interfaces where content can be added
both at the top (older messages) and bottom (newer messages) while maintaining scroll position.

The core component is ``TiledView``, which uses a virtual content space architecture
to enable prepending items without content offset jumps.

### Quick Start

```swift
import MessagingUI

struct Message: Identifiable, Equatable {
  let id: Int
  var text: String
  var isFromMe: Bool
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
  }
}

struct ChatView: View {
  @State private var dataSource = ListDataSource<Message>()
  @State private var scrollPosition = TiledScrollPosition()

  var body: some View {
    TiledView(
      dataSource: dataSource,
      scrollPosition: $scrollPosition
    ) { message, state in
      MessageBubbleCell(item: message)
    }
    .task {
      let messages = await fetchMessages()
      dataSource.apply(messages)
    }
  }
}
```

## Topics

### Essentials

- ``TiledView``
- ``ListDataSource``
- ``TiledScrollPosition``
- ``TiledCellContent``
- ``CellContext``

### Guides

- <doc:Bidirectional-Loading>
- <doc:Swipe-to-Reveal-Timestamps>

### Architecture

- <doc:TiledView-Architecture>
