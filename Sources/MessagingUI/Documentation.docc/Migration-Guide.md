# Migration Guide

Migrate from the old `ListDataSource`-based API to the new snapshot-based
`TiledView(items:scrollPosition:...)` API.

## Overview

`TiledView` no longer accepts `ListDataSource` as public API. Keep your list
state as a plain `[Item]` and pass that array directly to `TiledView`.

Internally, `TiledView` compares the currently displayed items with the latest
snapshot and applies collection view operations such as prepend, append, insert,
remove, update, or replace.

## Basic Migration

Before:

```swift
@State private var dataSource = ListDataSource<Message>()
@State private var scrollPosition = TiledScrollPosition()

var body: some View {
  TiledView(
    dataSource: dataSource,
    scrollPosition: $scrollPosition
  ) { message in
    MessageBubbleCell(item: message)
  }
  .task {
    let messages = await fetchMessages()
    dataSource.apply(messages)
  }
}
```

After:

```swift
@State private var messages: [Message] = []
@State private var scrollPosition = TiledScrollPosition()

var body: some View {
  TiledView(
    items: messages,
    scrollPosition: $scrollPosition
  ) { message in
    MessageBubbleCell(item: message)
  }
  .task {
    messages = await fetchMessages()
  }
}
```

## Operation Mapping

Replace each `ListDataSource` mutation with an equivalent array update.

| Old API | New API |
| --- | --- |
| `dataSource.apply(newMessages)` | `messages = newMessages` |
| `dataSource.replace(with: newMessages)` | `messages = newMessages` |
| `dataSource.prepend(olderMessages)` | `messages.insert(contentsOf: olderMessages, at: 0)` |
| `dataSource.append(newMessages)` | `messages.append(contentsOf: newMessages)` |
| `dataSource.insert(items, at: index)` | `messages.insert(contentsOf: items, at: index)` |
| `dataSource.updateExisting(updatedItems)` | Replace matching elements in `messages` |
| `dataSource.remove(ids: ids)` | `messages.removeAll { ids.contains($0.id) }` |

For updates:

```swift
for updatedItem in updatedItems {
  guard let index = messages.firstIndex(where: { $0.id == updatedItem.id }) else {
    continue
  }
  messages[index] = updatedItem
}
```

## Loading Older Messages

Before:

```swift
.prependLoader(.loader(perform: {
  let olderMessages = await fetchOlderMessages()
  dataSource.prepend(olderMessages)
}) {
  ProgressView()
})
```

After:

```swift
.prependLoader(.loader(perform: {
  let olderMessages = await fetchOlderMessages()
  messages.insert(contentsOf: olderMessages, at: 0)
}) {
  ProgressView()
})
```

## Loading Newer Messages

Before:

```swift
.appendLoader(.loader(perform: {
  let newerMessages = await fetchNewerMessages()
  dataSource.append(newerMessages)
}) {
  ProgressView()
})
```

After:

```swift
.appendLoader(.loader(perform: {
  let newerMessages = await fetchNewerMessages()
  messages.append(contentsOf: newerMessages)
}) {
  ProgressView()
})
```

## Keep a Display Window

The new API intentionally makes the caller's source of truth explicit. Pass only
the items you want `TiledView` to display.

If your app stores a full message history, keep a separate display window:

```swift
@State private var displayedMessages: [Message] = []

func loadInitialPage() async {
  displayedMessages = await fetchLatestMessages(limit: 50)
}

func loadOlderMessages() async {
  let olderMessages = await fetchOlderMessages(before: displayedMessages.first)
  displayedMessages.insert(contentsOf: olderMessages, at: 0)
}
```

Avoid passing an entire persisted history unless the UI is intended to render the
entire history.

## Identity Requirements

Each item must have a stable, unique `id`.

```swift
struct Message: Identifiable, Equatable {
  let id: MessageID
  var text: String
}
```

Changing an existing item's `id` is treated as removing one item and inserting a
different item. For message edits or delivery state changes, keep the same `id`
and update the item's other properties.

## Breaking Changes

- `TiledView(dataSource:scrollPosition:...)` has been removed.
- `ListDataSource` is no longer public API.
- `TiledDataSource` compatibility alias has been removed.
- Callers should own list state as `[Item]`.
- `TiledView` now derives collection view changes internally from item snapshots.
