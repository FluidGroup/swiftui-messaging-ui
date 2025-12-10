# TiledView Architecture Document

## Overview

TiledViewは、双方向無限スクロールを実現するためのUICollectionViewベースのコンポーネントです。
チャットUIのように、上方向（過去のメッセージ）と下方向（新しいメッセージ）の両方にコンテンツを追加できます。

## Core Concept: Virtual Content Space

### 基本設計

```
┌─────────────────────────────────────┐
│                                     │
│     Virtual Content Space           │
│     (100,000,000 pixels)            │
│                                     │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │  Prepend Area               │    │
│  │  (items added to top)       │    │
│  │                             │    │
│  ├─────────────────────────────┤    │  ← anchorY (50,000,000)
│  │                             │    │
│  │  Initial Items              │    │
│  │                             │    │
│  ├─────────────────────────────┤    │
│  │                             │    │
│  │  Append Area                │    │
│  │  (items added to bottom)    │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

### なぜこの設計か

通常のUICollectionViewでは、先頭にアイテムを追加すると`contentOffset`がずれてしまい、
ユーザーの見ている位置がジャンプしてしまいます。

従来の解決策は、prepend後に`contentOffset`を調整することですが、
これには以下の問題があります：

1. 視覚的なジャンプやちらつきが発生する可能性
2. アニメーション中の調整が困難
3. タイミングによっては競合状態が発生

**Virtual Content Space設計**では、`contentOffset`を一切変更しません。
代わりに、巨大な仮想空間（1億ピクセル）の中央（5千万ピクセル）をアンカーポイントとして、
アイテムのY位置自体を調整します。

### Prepend時の動作

```
Before:                          After:
┌──────────┐                     ┌──────────┐
│ Item 0   │ y=50000000          │ New Item │ y=49999900 (= 50000000 - 100)
├──────────┤                     ├──────────┤
│ Item 1   │ y=50000100          │ Item 0   │ y=50000000 (unchanged)
├──────────┤                     ├──────────┤
│ Item 2   │ y=50000200          │ Item 1   │ y=50000100 (unchanged)
└──────────┘                     ├──────────┤
                                 │ Item 2   │ y=50000200 (unchanged)
                                 └──────────┘

contentOffset: unchanged (user's view position stays the same)
```

新しいアイテムは既存アイテムの**上**に配置され、既存アイテムのY位置は変わりません。
`contentOffset`も変わらないため、ユーザーの見ている位置は完全に維持されます。

### Append時の動作

```
Before:                          After:
┌──────────┐                     ┌──────────┐
│ Item 0   │ y=50000000          │ Item 0   │ y=50000000 (unchanged)
├──────────┤                     ├──────────┤
│ Item 1   │ y=50000100          │ Item 1   │ y=50000100 (unchanged)
├──────────┤                     ├──────────┤
│ Item 2   │ y=50000200          │ Item 2   │ y=50000200 (unchanged)
└──────────┘                     ├──────────┤
                                 │ New Item │ y=50000300 (= 50000200 + 100)
                                 └──────────┘
```

---

## Current Implementation (Imperative API)

### 構成要素

```
┌─────────────────────────────────────────────────────────────┐
│ TiledViewRepresentable (SwiftUI Bridge)                     │
│   - @Binding var tiledView: TiledView?                      │
│   - Exposes TiledView reference for imperative operations   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ TiledView<Item, Cell> (UIView)                              │
│   - items: [Item]                                           │
│   - cellBuilder: (Item) -> Cell                             │
│   - sizingHostingController: UIHostingController<Cell?>     │
│                                                             │
│   Public Methods:                                           │
│   - setItems(_ newItems: [Item])                            │
│   - prependItems(_ newItems: [Item])                        │
│   - appendItems(_ newItems: [Item])                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ TiledCollectionViewLayout (UICollectionViewLayout)          │
│   - itemYPositions: [CGFloat]                               │
│   - itemHeights: [CGFloat]                                  │
│   - itemSizeProvider: ((Int, CGFloat) -> CGSize?)?          │
│                                                             │
│   Methods:                                                  │
│   - appendItems(count:startingIndex:)                       │
│   - prependItems(count:)                                    │
│   - updateItemHeight(at:newHeight:)                         │
└─────────────────────────────────────────────────────────────┘
```

### 使用例

```swift
struct ChatView: View {
  @State private var tiledView: TiledView<ChatMessage, ChatBubbleView>?

  var body: some View {
    VStack {
      Button("Load Older") {
        let olderMessages = fetchOlderMessages()
        tiledView?.prependItems(olderMessages)  // Imperative call
      }

      TiledViewRepresentable(
        tiledView: $tiledView,
        items: [],
        cellBuilder: { ChatBubbleView(message: $0) }
      )
      .onAppear {
        let initialMessages = fetchInitialMessages()
        tiledView?.setItems(initialMessages)  // Imperative call
      }
    }
  }
}
```

### itemSizeProvider による事前サイズ計測

セルが表示される前に正確なサイズを取得するため、`itemSizeProvider`クロージャを使用します。

```swift
// TiledView内での設定
tiledLayout.itemSizeProvider = { [weak self] index, width in
  self?.measureSize(at: index, width: width)
}

// サイズ計測（UIHostingControllerを再利用）
private func measureSize(at index: Int, width: CGFloat) -> CGSize? {
  guard index < items.count else { return nil }
  let item = items[index]
  sizingHostingController.rootView = cellBuilder(item)
  sizingHostingController.view.layoutIfNeeded()

  return sizingHostingController.view.systemLayoutSizeFitting(
    CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
    withHorizontalFittingPriority: .required,
    verticalFittingPriority: .fittingSizeLevel
  )
}
```

**重要**: `UIHostingController`のインスタンスを毎回生成するのはコストが高いため、
1つのインスタンスを保持して`rootView`を差し替えることで再利用しています。

---

## Challenges: Declarative API

### 目標

```swift
// 理想的な宣言的API
struct ChatView: View {
  @State private var messages: [ChatMessage] = []

  var body: some View {
    TiledViewRepresentable(
      items: messages,  // State binding only
      cellBuilder: { ChatBubbleView(message: $0) }
    )
  }

  func loadOlder() {
    messages.insert(contentsOf: olderMessages, at: 0)  // Just modify state
  }

  func loadNewer() {
    messages.append(contentsOf: newerMessages)  // Just modify state
  }
}
```

### 根本的な問題

SwiftUIの宣言的APIでは「現在の状態」しか渡されません。
しかし、TiledCollectionViewLayoutは「prepend vs append」を知る必要があります。

```
SwiftUI World:                    Layout World:
─────────────────                 ─────────────────
"Here are the items"              "Where did the new items go?"
[A, B, C, D, E]                   - Prepend? → Y positions shift up
                                  - Append? → Y positions extend down
                                  - Insert in middle? → ???
```

### 試みたアプローチと失敗理由

#### 1. DiffableDataSource + prepare()自動検出

**アプローチ:**
- `UICollectionViewDiffableDataSource`でデータ管理
- `prepare()`内で`numberOfItems(inSection:)`から自動的にアイテム数を検出
- 配列サイズが増えたら自動的に拡張

**失敗理由:**
- `prepare()`での自動拡張と明示的な`prependItems()`呼び出しが競合
- アイテムが重複して追加される
- タイミングの制御が困難

```swift
// prepare()内
while itemHeights.count < itemCount {
  // ここで追加されるが...
}

// 外部から
tiledView.prependItems(newItems)  // ここでも追加 → 重複
```

#### 2. Prepend検出 + prependItems呼び出し

**アプローチ:**
- 新旧アイテムを比較してprepend数を検出
- 検出結果に基づいて`prependItems()`を呼び出し

**失敗理由:**
- 検出タイミングと`prepare()`のタイミングが競合
- 自動拡張との整合性が取れない

#### 3. Anchor-based contentOffset調整

**アプローチ:**
- 更新前に可視アイテムのスクリーン位置を記録
- スナップショット適用後、アンカーアイテムが同じスクリーン位置に来るように`contentOffset`を調整

**失敗理由:**
- **却下** - Virtual Content Spaceのコンセプトに反する
- `contentOffset`を変更すると、このアーキテクチャを採用する意味がなくなる
- 「それをするなら最初から巨大なcontentSizeをとっておく必要がない」

#### 4. 手動diff + batch updates

**アプローチ:**
- `Collection.difference(from:)`でdiffを計算
- `UICollectionView.performBatchUpdates`で手動でinsert/delete
- Layoutに`applyDiff`メソッドを追加

**失敗理由:**
- UIが完全に崩壊
- diffの適用順序とLayoutの状態管理の整合性が取れない
- 複雑すぎて保守困難

---

## Current Constraints

### 絶対的な制約

1. **contentOffsetは変更しない**
   - Virtual Content Spaceアーキテクチャの根幹
   - これを変更するとアーキテクチャ全体を再設計する必要がある

2. **Layoutはprepend/appendを明示的に知る必要がある**
   - Y位置の計算方向が異なる
   - Prepend: 既存アイテムの上に配置（Y位置が減少）
   - Append: 既存アイテムの下に配置（Y位置が増加）

### 実装上の制約

1. **items配列とLayout配列の同期**
   - `TiledView.items`と`TiledCollectionViewLayout.itemYPositions/itemHeights`は常に同期している必要がある
   - 順序: items配列を先に更新 → Layoutを更新

2. **サイズ計測のタイミング**
   - `itemSizeProvider`はitems配列が更新された後に呼ばれる
   - `measureSize`はitems配列にアクセスするため、順序が重要

---

## Future Considerations

### 宣言的APIを実現するための可能なアプローチ

#### Option A: ID-based Positioning

アイテムのIDに基づいてprepend/appendを判断する。

```swift
// Item.IDがComparableの場合
if newItems.first?.id < existingItems.first?.id {
  // Prepend
} else if newItems.last?.id > existingItems.last?.id {
  // Append
}
```

**制約:**
- `Item.ID: Comparable`が必要
- IDが順序を表す前提（連番など）

#### Option B: Anchor-based Layout (Different Architecture)

完全に異なるアーキテクチャで、アンカーアイテムを基準にレイアウトを構築。

**検討事項:**
- Virtual Content Spaceを維持しつつ実現可能か
- パフォーマンスへの影響

#### Option C: Hybrid API

宣言的な部分と命令的な部分を組み合わせる。

```swift
TiledViewRepresentable(
  items: messages,
  changeHint: .prepend(count: 5),  // 変更のヒントを提供
  cellBuilder: { ... }
)
```

**課題:**
- SwiftUIの`updateUIView`で前回の状態を保持する必要
- Coordinatorパターンの活用

---

## File Structure

```
Sources/MessagingUI/Tiled/
├── TiledView.swift
│   ├── TiledViewCell          - UICollectionViewCell with UIHostingConfiguration
│   ├── TiledView              - Main UIView component
│   └── TiledViewRepresentable - SwiftUI bridge
│
└── TiledCollectionViewLayout.swift
    └── TiledCollectionViewLayout - Custom layout with virtual content space
```

---

## References

- [UICollectionViewDiffableDataSource](https://developer.apple.com/documentation/uikit/uicollectionviewdiffabledatasource)
- [UIHostingConfiguration](https://developer.apple.com/documentation/swiftui/uihostingconfiguration)
- [Collection.difference(from:)](https://developer.apple.com/documentation/swift/collection/difference(from:))
