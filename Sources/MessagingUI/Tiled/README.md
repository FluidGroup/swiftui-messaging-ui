# TiledView

双方向スクロール（上下両方向への無限スクロール）を実現するUICollectionViewベースのフレームワーク。チャットUIなど、上方向へのアイテム追加が必要なユースケースに最適。

## 特徴

- **contentOffset調整なし**: 巨大な仮想コンテンツ領域（100,000,000px）を使用し、prepend時にcontentOffsetを調整する必要がない
- **SwiftUIセル対応**: `UIHostingConfiguration`を使用してSwiftUI Viewをセルとして表示
- **ジェネリクス対応**: 任意の`Identifiable`アイテムとSwiftUI Viewを使用可能
- **動的セル高さ**: セルの高さを動的に計算・更新可能

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│                  Virtual Content Space                   │
│                   (100,000,000px)                        │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │              Anchor Point (50,000,000)           │   │
│  │                      ↓                           │   │
│  │  ┌───────────────────────────────────────────┐  │   │
│  │  │  Prepended Items (negative Y direction)   │  │   │
│  │  ├───────────────────────────────────────────┤  │   │
│  │  │  Initial Items                            │  │   │
│  │  ├───────────────────────────────────────────┤  │   │
│  │  │  Appended Items (positive Y direction)    │  │   │
│  │  └───────────────────────────────────────────┘  │   │
│  │                                                 │   │
│  │  contentInset: 負の値でバウンス領域を制限       │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 仕組み

1. **巨大な仮想コンテンツ**: `contentSize`を100,000,000pxに設定
2. **アンカーポイント**: 最初のアイテムを中央（50,000,000px）付近に配置
3. **Prepend**: アンカーより上（負の方向）にアイテムを追加
4. **Append**: 最後のアイテムより下（正の方向）にアイテムを追加
5. **負のcontentInset**: 実際のコンテンツ領域外でバウンスするように調整

## ファイル構成

```
TiledView/
├── TiledCollectionViewLayout.swift   # カスタムUICollectionViewLayout
├── TiledView.swift                   # Cell, ViewController, SwiftUI Representable
├── Demo/
│   └── TiledViewDemo.swift           # デモ用Preview
└── README.md                         # このファイル
```

## クラス説明

### TiledCollectionViewLayout

`UICollectionViewLayout`のサブクラス。アイテムのY座標と高さを管理。

```swift
public final class TiledCollectionViewLayout: UICollectionViewLayout {
  // アイテム追加
  func appendItems(heights: [CGFloat])
  func prependItems(heights: [CGFloat])

  // 高さ更新
  func updateItemHeight(at index: Int, newHeight: CGFloat)

  // contentInset計算
  func calculateContentInset() -> UIEdgeInsets
}
```

### TiledViewCell

SwiftUI Viewを表示する`UICollectionViewCell`。

```swift
public final class TiledViewCell: UICollectionViewCell {
  func configure<Content: View>(with content: Content)
}
```

### TiledViewController

ジェネリクス対応のViewController。

```swift
public final class TiledViewController<Item: Identifiable, Cell: View>: UIViewController {
  // アイテム設定
  func setItems(_ newItems: [Item])
  func prependItems(_ newItems: [Item])
  func appendItems(_ newItems: [Item])

  // 高さ更新
  func updateItemHeight(at index: Int, newHeight: CGFloat)
}
```

### TiledViewRepresentable

SwiftUI用ラッパー。

```swift
public struct TiledViewRepresentable<Item: Identifiable, Cell: View>: UIViewControllerRepresentable {
  init(
    viewController: Binding<TiledViewController<Item, Cell>?>,
    items: [Item],
    @ViewBuilder cellBuilder: @escaping (Item) -> Cell,
    heightCalculator: @escaping (Item, CGFloat) -> CGFloat
  )
}
```

## 使用例

```swift
import TiledView
import SwiftUI

struct Message: Identifiable {
  let id: Int
  let text: String
}

struct MessageBubble: View {
  let message: Message

  var body: some View {
    Text(message.text)
      .padding()
      .background(Color.gray.opacity(0.2))
      .cornerRadius(12)
  }
}

struct ChatView: View {
  @State private var viewController: TiledViewController<Message, MessageBubble>?

  var body: some View {
    TiledViewRepresentable(
      viewController: $viewController,
      items: [],
      cellBuilder: { message in
        MessageBubble(message: message)
      },
      heightCalculator: { message, width in
        // セルの高さを計算
        calculateHeight(for: message, width: width)
      }
    )
    .onAppear {
      // 初期データ設定
      viewController?.setItems(initialMessages)
    }
  }

  func loadMoreOlder() {
    viewController?.prependItems(olderMessages)
  }

  func loadMoreNewer() {
    viewController?.appendItems(newerMessages)
  }
}
```

## 開発経緯

### PoC実装（BookBidirectionalVerticalScrollView.swift）

2つの方式を比較検討：

| 方式 | 実装 | 結果 |
|------|------|------|
| A | CATiledLayer + UIView Cell | タイル描画は動作するが、チャットUIには不向き |
| B | UICollectionView + Custom Layout | ✅ 採用 |

### 方式Bを選択した理由

1. **UICollectionViewの再利用**: セルの再利用が自動的に行われる
2. **UIHostingConfiguration**: SwiftUI Viewを簡単に統合可能
3. **レイアウト制御**: カスタムLayoutで完全なY座標制御が可能
4. **パフォーマンス**: 可視セルのみ描画される

## 今後の改善案

- [ ] 選択状態のサポート
- [ ] スクロール位置のコールバック
- [ ] 自動ページング（上端/下端到達時のロード）
- [ ] アニメーション付きのアイテム追加/削除
- [ ] セクションサポート

## 参考

- 元PoC: `Book2025-iOS26/BookBidirectionalVerticalScrollView.swift`
- 方式A（CATiledLayer）は参考実装として上記ファイルに残存
