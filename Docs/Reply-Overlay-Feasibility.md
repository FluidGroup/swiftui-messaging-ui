# Reply overlay の実現可能性

セルのスワイプから、選択した吹き出しが会話の前面へ移動して見える reply 表示を検討する。現段階では、描画の共有、座標の補間、gesture の引き継ぎを別々に検証する。全体の成立や iMessage と同等の動作はまだ確認していない。

最終表示は、背景の会話を暗くし、選択した吹き出しを reply 入力欄の上へ浮かせる形を仮定する。最初の検証にはキーボード、送信、reply データモデルを含めない。

## 技術上の判断

`_UIPortalView` は元セルの描画をライブで複製する候補になる。`matchedGeometryEffect` はその複製をどこに置き、どう移動させるかを担当する。この二つは独立した問題であり、portal を導入しても座標合わせや再利用の問題は残る。

元セルと overlay で別の SwiftUI view を描画しても、静的な吹き出しを移動して見せる実験はできる。ただし、元の `@State`、task、動画や loading の実体が同じであることは証明できない。「移動が連続する」と「同じ描画が生き続ける」は別の合格条件にする。

## 現在の構造

| 対象 | 現状 | 検証への影響 |
| --- | --- | --- |
| セルの描画 | `TiledViewCell.configure` がセルごとに `UIHostingConfiguration` を作る | 外側の SwiftUI overlay との hosting 境界を跨ぐ |
| スワイプ | collection 全体の左 pan で共通 `CellReveal` を更新する | reply は対象 item ID を固定した個別 offset が必要 |
| セルの生成 | `cellBuilder` は UIKit view 作成時に保持され、更新されない | 変化する selection 値を closure で捕まえず、安定した session 参照を使う |
| サイズ測定 | 表示セルと同じ builder と state で off-window の測定用セルを作る | geometry source や source registry が測定用セルを拾わないことを確認する |
| 座標 | 100,000,000 pt の仮想 content 空間を使う | layout attributes を overlay 座標として使わない |
| 描画範囲 | セルは全幅、吹き出しは spacer と padding の内側 | 移動対象の吹き出しそのものの rect が必要 |
| 再利用 | `prepareForReuse` が hosting 内容を消し、更新も reconfigure する | 強参照だけでは portal の内容や item identity を保持できない |

根拠となるコードは `Sources/MessagingUI/Tiled/TiledViewCell.swift`、`TiledView.swift`、`TiledCollectionViewLayout.swift` と `Dev/MessagingUIDevelopment/Messenger/MessageBubbleView.swift`。

## matchedGeometryEffect の確認範囲

Apple の説明では、同じ ID と namespace の view を同一 transaction 内で取り除き、別の場所へ挿入すると、window 空間の frame を補間する。描画自体は通常の transition が担当し、挿入されている `isSource: true` は一つでなければならない。[Apple documentation](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:))

この説明だけでは、実際の `UIHostingConfiguration` と外側 overlay の間で期待通り動くとは断定できない。既存の navigation demo の `matchedTransitionSource` も、今回の effect の成立を示すものではない。

初期検証では二つの構成を比較した。

1. 一つの SwiftUI host 内の通常の `VStack` と overlay。
2. 実際の `TiledView` セルと、その外側の SwiftUI overlay。

現在の `Reply Geometry Lab` は `TiledView` だけのサンプルに整理し、構成の切り替えと SwiftUI 基準リストを削除した。初期の比較結果は後述の検証記録に残す。spring、overlay の縦 `ScrollView`、セル内の spinner と描画 ID は維持している。

同じ namespace、ID、bubble 内容、固定サイズ、animation を使う。選択した行の高さを残し、source の取り除きと overlay の挿入を一回の `withAnimation` で行う。通常速度と低速で、開始・途中・終了・復帰を観察する。画面外の測定用インスタンスの影響も含め、二つ目は実装が動くという前提を置かない。

cross-host の対応が成立しない場合は、UIKit で測った source rect を **外側 overlay と同じ host 内の geometry node** に渡す。そこで source 位置と destination 位置を `matchedGeometryEffect` で繋ぐ実験を行う。この構成では、portal と geometry node を別々に差し替えられる。

## Portal の確認範囲

WebKit の SPI 宣言には `CAPortalLayer`、weak `sourceLayer`、`matchesPosition`、`matchesTransform` がある。[WebKit source](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/PAL/pal/spi/cocoa/QuartzCoreSPI.h)

Telegram は runtime lookup で private `_UIPortalView` を生成し、weak `sourceView`、`hidesSourceView`、`matchesAlpha`、position、transform などを扱っている。factory は alpha の追従と hit testing を無効にしている。[Telegram declaration](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIKitUtils.h)、[implementation](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIKitUtils.m)

最初の実験では、overlay が位置を所有するため `matchesPosition` と `matchesTransform` を false にし、`matchesAlpha` も false を起点にする。これは二重の位置制御を避けるための設計仮説であり、現在の OS 上の動作は未確認。source の alpha、hidden、ancestor の clipping と `hidesSourceView` の各組み合わせを実測する。

公開 UIKit API としての `UIPortalView` は確認できない。App Review 2.5.1 は public API の使用を要求しているため、開発用の技術検証が成立することと、配布するライブラリに採用できることは別に判断する。[Apple guidelines](https://developer.apple.com/app-store/review/guidelines/#software-requirements)

### 描画 source と座標 marker

空の `UIViewRepresentable` を吹き出しの background に置くと、その UIView で座標を測れる。しかし、その UIView は SwiftUI の吹き出しを描画する subtree を所有していない。marker を portal の source に渡すだけでは、内容が映る証明にならない。

最初は既に所有している `cell.contentView` 全体を source にする。これには余白や timestamp も含まれる。ライブ描画を確認した後、測った bubble rect に合わせて overlay 側で crop できるか調べる。必要なら bubble 専用の app-owned UIKit host を検討するが、その追加の hosting 境界とサイズ測定への影響は別に確認する。

### 元セルの寿命

source を強参照しても、セルが別 item に再利用されると異なる message が映るおそれがある。item ID と source の generation を持ち、configuration 更新、削除、再利用、view の detach を検知できる設計が必要。

presentation 中にスクロールを一時的に止めることは初期実験の条件として使える。しかし、append、prepend、selected item の更新や削除まで安全になるわけではない。元セルを offscreen に維持する、所有する描画 host を分離する、更新時に session を終了する、といった方針は、必要な製品動作を踏まえて決める。

## 座標と animation の引き継ぎ

同じ `UIWindow` 内で、実際の bubble の bounds を overlay host へ `UIView.convert(_:to:)` で変換する。source rect には現在の swipe offset を含める。gesture 終了でセルを一度 snap back させ、その後 overlay を出すと、連続性を失う。[Apple coordinate conversion](https://developer.apple.com/documentation/uikit/uiview/convert(_:to:)-2kf3d)

初期実験では source と同じ幅・高さのまま移動する。portal の frame を変えることは、元 SwiftUI view を新しい幅で再レイアウトすることと同じではない。長文の改行や destination での縮小は後の段階へ分ける。

採用する構成によっては UIKit property の更新も SwiftUI transaction に合わせる必要がある。`UIViewRepresentableContext.animate` の利用可能性は deployment target と SDK で確認してから扱う。[Apple animation bridge](https://developer.apple.com/documentation/swiftui/uiviewrepresentablecontext/animate(changes:completion:))

## 描画方法の比較

| 方法 | 強み | 成立を確認する点 |
| --- | --- | --- |
| SwiftUI を再描画 | public API で model や明示的 state を共有できる | local state と task の二重化、environment、テキストの再レイアウト |
| `snapshotView` | 既存の見た目を捕捉できる | 静止画像なので更新や進行中の animation は追わない |
| `_UIPortalView` | 元の描画をライブで複製する実装例がある | private API、source の寿命、非表示化、mask、動画 surface |
| 所有する UIView を移動 | 一つの描画実体を保つ設計候補 | セルの placeholder、host の所有権、復帰、サイズ測定 |

snapshot は比較用の基準にする。未描画の source では内容がなく、snapshot 後の animation 更新も反映しないため、ライブ描画の最終条件とは区別する。[Apple snapshot documentation](https://developer.apple.com/documentation/uikit/uiview/snapshotview(afterscreenupdates:))

### セル内の animation probe

検証画面の各 bubble に、1.2秒で回転する spinner と、描画インスタンスごとの6文字の ID を付けた。回転はそれぞれの View で開始し、session の時計や角度を共有しない。非表示 placeholder と off-window の測定用セルは同じ寸法を保持し、回転を開始しない。

元セルと overlay で ID と回転位相が一致し、表示中も回転が続くことをライブ複製の確認条件にする。snapshot なら回転が止まり、独立した SwiftUI 再描画なら ID が変わる。spinner が動くだけでは portal の証拠にしない。portal のクラスと source 接続も別途確認する。

現在の geometry lab は overlay に新しい bubble を生成するため、ID が変わるのが正しい。この点を画面にも明示した。portal の段階では元の描画インスタンスを生かしたまま複製し、現在の source を取り除く分岐も変更する必要がある。

iPhone 18 Pro Simulator / iOS 27.0 で、SwiftUI と実 `TiledView` の両方のセルで回転を確認した。同一セルでは ID が維持され、SwiftUI の overlay へ移動すると ID が変わることも確認した。spinner を含めた development app の `xcodebuild` は成功。portal によるライブ複製はまだ未検証。

## 段階と合格条件

| 段階 | 検証 | 次へ進む条件 |
| --- | --- | --- |
| 1 | 同一 host と実 `TiledView` の geometry 比較 | 一定サイズで往復でき、開始位置の飛び、二重表示、source の消失を評価できる |
| 2 | bubble の UIKit 座標と同一 overlay host 内の geometry node | source outline が上下端、スクロール後、safe area で一致する |
| 3 | 単独 portal と実セルの live mirror | 内容と animation が更新され、元表示を隠しても replica が残る。detach と解除が安全 |
| 4 | 対象を固定した swipe と overlay への引き継ぎ | 左 swipe の timestamp と縦 scroll を壊さず、現在位置から連続して浮く。cancel と再入力で破綻しない |
| 5 | reply 入力、keyboard、復帰 | keyboard 中の resize と auto-scroll を含めて移動先を保持し、現在の source へ復帰できる |
| 6 | 更新と再利用、実コンテンツ、実機 | 削除、更新、append、prepend、offscreen、回転、長文、写真、Dynamic Type の結果を確認する。動画は独立検証 |

一つの段階で不成立なら、その原因と変更する設計を記録してから次へ進む。スクリーンショットの終点が合っているだけでは、途中の animation やライブ描画の合格としない。

## 状態の所有

reply 対象の message ID は会話画面側に持つ。可視化の session は安定した参照で保持し、`idle → swiping → presenting → active → dismissing` の phase、対象 ID、source generation と geometry を扱う。reply の意味上の状態と、途中の gesture・animation 状態を分ける。

dismiss 時は現在の item ID で source を再取得する。元の index path を保持して戻さない。source が消えた、画面外、内容のサイズが変わった場合の表示は明示的に決める必要があり、古い rect へ戻る動作を成功と扱わない。

## 今回の検証記録

2026年10月1日。段階1の検証画面 `Reply Geometry Lab` を development app の既存リストに追加した。`xcodebuild` で development app の Debug / iOS Simulator ビルドが成功した。iPhone 18 Pro / iOS 27.0 Simulator で短文の受信 bubble をタップし、通常速度と3秒の低速で表示・復帰を観察した。低速の結果は動画を記録し、フレームを抽出して確認した。

| 構成 | 確認した結果 | 判定 |
| --- | --- | --- |
| 同一 SwiftUI host と `.identity` transition | source が消え、destination へ位置が飛ぶ | この比較画面では不成立 |
| 同一 SwiftUI host と `.opacity` transition | source 位置から destination まで3秒で移動する。復帰も補間する | 静的な短文について geometry の基準を確認 |
| `TiledView` と外側 overlay の直接 matching | 移動が見える。ただし `.identity`、`.opacity` 両方で source 重複の runtime 警告。途中で他セルの描画と重なる | 見た目の移動は確認。本採用の合格条件は満たさない |

同一 host の `.identity` から `.opacity` への変更は、source bubble、destination bubble、条件付き overlay の三か所だけに行った。この比較では rendering の寿命が geometry の補間に影響した。あらゆる `.identity` transition が失敗するという結論ではない。

`TiledView` の警告は `Multiple inserted views in matched geometry group ... have isSource: true, results are undefined.`。off-window の測定用セルは window attachment probe で matching から除外している。それでも警告が出るため、次は host を跨ぐ挿入・除去のタイミングが原因になっているか調べる。これは原因の仮説であり、警告の発生そのものは実行ログで確認した。

`.opacity` の録画では、移動途中の source bubble の文字や背景が他セルの描画と重なるフレームも確認した。geometry が対応しても描画をセル階層から前面へ移す保証にはならない。clipping、重なり順、source と destination の rendering のどれがこの見え方に影響しているかは未切り分け。

次の実験では、同じ overlay host 内に source と destination の geometry node を置き、実セルから変換した rect を渡す。これにより geometry の source を一つの SwiftUI hierarchy で制御できるか確認する。その合格後に描画 payload を portal に差し替え、ライブ同一性の検証へ進む。

検証コードは library の公開 API を変更せず、development app に限定した。最終の `.opacity` 構成で通常速度、長文・送信側、animation 中断、スクロール・再利用の組み合わせを網羅したわけではない。今回の結果からそれらの成立は推定しない。

2026年10月2日追記。表示・復帰を `spring(response:dampingFraction:)` に変更した。response は通常 `0.45`、Slow animation では `3`、dampingFraction は `0.82`。overlay の内容を縦 `ScrollView` に載せ、短いセルでもドラッグできるよう `.scrollBounceBehavior(.always)` を適用した。viewport の高さを最低高とし、静止時の下寄せを維持している。短いセルのドラッグはバウンスで、指を離すと定位置へ戻る。

iPhone 18 Pro / iOS 27.0 Simulator で、SwiftUI・実 `TiledView` の短い受信セルについて、通常速度の表示、overlay の縦ドラッグとバウンス復帰、Close による元セルへの復帰を確認した。`xcodebuild` は成功。既存の matched geometry source 重複警告への対応は後の検討に残した。

段階2以降、実際の portal、swipe、keyboard、reply 送信、実機のライブ描画は未検証。
