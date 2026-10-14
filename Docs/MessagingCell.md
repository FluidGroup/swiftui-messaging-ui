# MessagingCell

`MessagingCell` は、SwiftUI のセル内容を一つの UIKit 描画 view に保持し、右スワイプから reply を要求する Swift Package product / target。`MessageCell` は SnapDraggingModifier directional API の availability に合わせて **iOS 18 以降**。Cell では UIKit host に recognizer を先に取り付ける経路を使い、dependency の `UIGestureRecognizerRepresentable` 経路も保持する。package 全体、`MessagingUI` と `ContextOverlay` の iOS 17 対応とは分けて扱う。`MessagingCell` は `MessagingUI` や `TiledView` に依存せず、`ContextOverlay` と local dependency の `SwiftUISnapDraggingModifier` に依存する。

`MessageCell` は SwiftUI `View` で、子の `UIViewRepresentable` が `UIHostingConfiguration.makeContentView()` を一つ所有する。描画 subtree に upstream の `SnapDraggingModifier` を適用し、その外側の background に静止した UIKit marker を置く。`CellSource` は `ContextOverlaySource` の typealias で、描画 view と静止 marker の weak reference を提供する。`CellSource()` は引き続き使えるが、release callback は現在 `(CellSource, CellReplyRelease) -> Bool` になった。overlay の表示方法と reply の状態は呼び出し側が所有する。

`MessagingCell` 自体は private Portal setter を呼ばない。`ContextOverlay` の production adapter は Aeastr の `UIPortalBridge` 1.0.0 の typed UIKit wrapper を使う。この依存先は private `_UIPortalView` を使う実験 backend を含み、公開 Apple API への移行を意味しない。

汎用の destination、phase と UIKit source の contract は [ContextOverlay](ContextOverlay.md) に記す。message を持たない通常の UIKit view では、`MessagingCell` を介さず `ContextOverlaySource` を直接使う。

## 使用例

`CellSource` を行の `@State` に一つ保持する。`phase`、reply の受理、source の監視は会話画面の session から渡す。

```swift
import MessagingCell
import SwiftUI

@available(iOS 18.0, *)
struct ReplyableBubble: View {
  let text: String
  let phase: CellReplyPhase
  let isReplyEnabled: Bool
  let acceptReply: (CellSource, CellReplyRelease) -> Bool
  let sourceDidChange: (CellSource, Bool) -> Void

  @State private var source = CellSource()

  var body: some View {
    MessageCell(
      source: source,
      isReplyEnabled: isReplyEnabled,
      replyPhase: phase,
      onReply: acceptReply,
      onSourceChange: sourceDidChange
    ) {
      Text(text)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.blue, in: RoundedRectangle(cornerRadius: 18))
    }
  }
}
```

同じ `CellSource` を複数の生きているセルで共有しない。セルの構造を選択時に別の View へ置き換えず、overlay 表示中も描画元を mount したまま保つ。`TiledView` で使う場合も、この module は `TiledCellContent` や collection cell の ancestor lookup を必要としない。development app の adapter は `ReplyGeometryCell` にある。

描画 view の所有と source 参照だけが必要なら、`MessageCell(source: source) { content }` として `onReply` を省略できる。既定値は `nil` で、この場合は reply pan を有効にしない。

## source と handoff

| API | 意味 |
| --- | --- |
| `CellSource.view` | セル自身が所有する既存の hosting content view。進行中の animation もここで描画する |
| `isAttachedToWindow` | 描画 view と container が同じ window に付いているか |
| `frame(in:)` | UIKit 変換に含まれない GeometryEffect の追加 translation も反映した、現在の描画 frame |
| `restingFrame(in:)` | modifier の外にある静止 marker の frame。overlay から戻す位置 |
| `onSourceChange` | attachment・layout・dismantle の同期通知。Bool は attachment の状態 |

`frame(in:)` と `restingFrame(in:)` は同じ window 内の座標 view を要求し、未接続や別 window の場合は `nil` を返す。座標変換先には、その `UIWindow` 自身も渡せる。source 自体は描画 view を retain しない。外部の表示 consumer は通知に応じて source identity と geometry を確認する。

SwiftUI の GeometryEffect は描画を動かしても hosting UIView の座標変換へその全移動を反映しない場合がある。local modifier は `GeometryEffect.effectValue` で評価した drawing offset を、modifier ごとの plain reference に直接記録する。release は後の async State 更新を待たずこの値を読み、Cell は UIKit 変換がすでに含む移動を差し引いた remainder だけを `source.setDrawingTranslation(_:)` に渡す。描画 offset 全体を無条件に加算して二重計上しない。

`onReply(source, release)` は指を離した時、描画元がまだドラッグ位置にある状態で呼ばれる。`CellReplyRelease.offset` は rubber band 後の **model target** で、interactive spring の途中では実際の drawing offset と異なり得る。`velocity` は spring 用の正規化前の物理速度 `CGVector`（pt/s）。現在の drawing offset は local modifier の四引数 callback が Cell の内部へ別に渡し、`source.frame(in:)` がそれを反映する。受け入れる場合はその描画 frame と resting frame を同時に捕捉し、呼び出し側の状態を `.preparing` にして `true` を返す。

受理後は raw velocity を overlay に渡し済みのため、Cell は package の戻り値を現在の drawing offset にし、local spring 用の velocity を zero にする。model target へ描画元が移動を続けることを止め、Portal の hidden acknowledgement まで実際の描画位置を保持する。`false`、distance と projected velocity の条件を満たさない release、gesture cancel は modifier が source を spring で静止位置へ戻す。

| `CellReplyPhase` | 呼び出し側の責任 | セルの動作 |
| --- | --- | --- |
| `.idle` | 新しい reply を許可する | 右スワイプを受け付ける |
| `.preparing` | overlay の用意を進める | release 時の translation を保持し、新しい swipe を止める |
| `.presented` | overlay が描画元を隠したことを確認して設定する | 隠れた描画元の translation を animation なしで zero に戻す |

復帰 animation がある場合は終了まで source を保ち、consumer を解除して元表示を戻した後に `.idle` へ戻す。接続失敗や中断も `.idle` に戻す。source の detach 通知では外部 consumer を同期的に切断し、SwiftUI の状態変更は次の main run loop へ送る。layout 通知だけで親 scroll のあらゆる変化を観測できるとは限らないため、継続表示する consumer の監視方針は別に決める。

`ContextOverlayState` と組み合わせる場合は次のように release の物理速度を渡す。tap は velocity を省略でき、その既定値は zero。

```swift
onReply: { source, release in
  state.present(context, from: source, velocity: release.velocity)
},
onSourceChange: { source, attached in
  state.sourceDidChange(source, attached: attached)
}
```

選択された行の `CellReplyPhase` は `state.isSourceHidden ? .presented : .preparing`、それ以外は `.idle` とする。汎用 state は `.idle → .preparing → .presenting → .active → .dismissing → .idle` を持ち、Cell の三つの phase へ投影する。

## gesture

`CellReplyConfiguration()` の既定値は activation distance `64 pt`、rubber band の extent を表す band length `64 pt`、velocity projection duration `0.12 s`。値は immutable で、変更する場合は initializer で新しい configuration を作る。受理条件は、正の model offset があり、`offset.width + max(0, velocity.dx) * velocityProjectionDuration >= activationDistance`。model の距離を満たした release と短い右 flick を同じ callback へ渡す。左速度は右方向の投影へ加算しない。

gesture の実体は vendored upstream `SwiftUISnapDraggingModifier` の `.directional(isEnabled:attachmentView:shouldBegin:onRecognizer:)`。directional mode が水平優位を判定し、Cell の admission closure が物理的な右方向と window attachment、左端 back 領域を確認する。`attachmentView` が Cell の UIKit host を渡し、`onRecognizer` が package 所有の pan を受け取り、最寄りの `UIScrollView` の pan に先に failure relationship を設定する。delegate や package の gesture tracking は置き換えない。左・縦方向では reply pan が失敗し、親へ操作を渡す。

navigation controller 内では window attachment・layout 時に、touch が始まる前に public recognizer 間の関係を登録する。セルの pan は `interactivePopGestureRecognizer` の失敗を待ち、iOS 26 以降の `interactiveContentPopGestureRecognizer` はセルの pan の失敗を待つ。左端の safe area + `20 pt` から始まる gesture は reply から除外する。edge back の識別は navigation controller の公開 property の identity で行い、recognizer の具象 class を仮定しない。親 recognizer の delegate は差し替えない。

`TiledView` 側の timestamp reveal は左方向の横 pan のみ開始する。development app は「右 = 個別 reply、左 = 会話全体の timestamp、縦 = list scroll」として組み合わせている。`isReplyEnabled` と SwiftUI の `.disabled` は新しい gesture を止めるために使う。

local dependency は upstream commit `5ec2f79cac340e91059394f935f5fc973840b7d1` を基にする。local patch は directional enabled・admission・recognizer hook、`cancelTargetOffset`、drawing offset の直接 capture と release / drawing callback、その regression test を加える。rubber band、release velocity の正規化と spring は upstream 実装を使い、directional drag の初期値は capture した描画位置から始める。従来の三引数 release callback と他の gesture mode の tracking は保持する。Cell は `cancelTargetOffset: .zero` を渡し、handoff 後に public offset を reset しても、後の cancel が以前の held offset へ戻さないようにする。出所と差分は [Vendor README](../Vendor/swiftui-snap-dragging-modifier/README.md) に記す。upstream へ公開・採用済みの API とは扱わない。

解体された、または同じ source 参照が新しい rendering へ置換された後の Cell host は、遅れた描画・layout・detach 通知で新しい binding を取り戻したり、その translation を変えたりしない。source の所有を確認してから描画 metadata を更新する。

`UIHostingConfiguration` に入れる内容は UIView の構成で保つ。この実装は `UIViewControllerRepresentable` を内包しない。`UIHostingConfiguration` の content に View Controller を含められない制約は [WWDC22: Use SwiftUI with UIKit](https://developer.apple.com/videos/play/wwdc2022/10072/) で説明されている。

現在の実行確認と未検証範囲は [Reply overlay の実現可能性](Reply-Overlay-Feasibility.md) に記録する。

2026年10月2日の汎用抽出時点では、旧 gesture / own Portal backend で `MessagingCellTests` 6件と `ContextOverlayTests` 10件の計16件、development app build、短文受信・送信の往復、左 reveal と縦 scroll を確認した。この結果は今回の SnapDraggingModifier / UIPortalBridge 移行前の記録として [実現可能性の検証記録](Reply-Overlay-Feasibility.md) に残す。

2026年10月2日、iPhone 17e / iOS 27.0 Simulator で ContextOverlay / Cell の関連30件と Vendor の25件が成功した。最終 development app の incremental build は19:23:06 JSTに成功した。初回の右 swipe、同じ spinner ID を保った復帰と再入力、短い flick の受理、縦 scroll、左端 back を確認した。今回の移行後の左 reveal の一時的な描画、実機、keyboard は未検証。独立した二軸の velocity 継続は未実装。

Cell は `.directional(attachmentView: …)` で自身の UIKit host へ package の pan を最初の touch 前に取り付ける。既存の coordinator・admission・end/cancel 処理を共有し、元の SwiftUI gesture 経路は attachmentView がない場合に使う。これは初回 touch まで recognizer を作らない SwiftUI 経路で、iOS 27 の content back が先に始まる問題への対応である。

Cell が使う drawing capture は release 時の四引数 callback だけで、継続的な `onPresentingOffsetChange` は使わない。UIKit の座標へすでに含まれる移動量を引いた残差を source へ設定し、Portal がその frame と元の物理 velocity を捕捉した後、ローカル spring の velocity を zero にして実描画位置を保持する。拒否時・hidden reset・idle 復帰時には残差を解除する。
