# Experimental local SnapDraggingModifier dependency

This package contains the original implementation from
[FluidGroup/swiftui-snap-dragging-modifier](https://github.com/FluidGroup/swiftui-snap-dragging-modifier)
at commit `5ec2f79cac340e91059394f935f5fc973840b7d1` (Add directional snap gesture mode, #16).
The upstream Apache 2.0 license is preserved in `LICENSE`.

This is a reviewable local dependency for the MessagingCell experiment. It is
not an upstream release and does not imply that these API additions have been
published or accepted upstream. Rubber banding, release-velocity normalization,
and spring animation use the upstream implementation.

The local changes are restricted to:

- A directional-mode enabled flag, additional admission closure, and recognizer
  callback. Admission receives local translation, start location, points-per-second
  velocity, and the original package-owned `UIPanGestureRecognizer`. This allows
  a caller to reserve physical right swipes and configure public navigation
  failure relationships without replacing the package delegate.
- Optional `attachmentView` for eager installation on a component-owned UIKit
  host. The mount marker retries after attachment/layout and configures public
  failure relationships before the first touch, covering SwiftUI's lazy creation
  of gesture representables. Both installation paths share the same package
  coordinator, admission, action handling, and terminal-session logic. Eager
  translation/velocity use window coordinates so moving the host does not feed
  back into the drag delta; activation still uses the original local touch.
- An optional `cancelTargetOffset` for directional cancellation. A caller that
  holds an accepted release position for a Portal handoff can reset the hidden
  source's public offset without later cancellation returning to the old held
  target. The default `nil` preserves upstream cancellation behavior.
- Optional release and drawing callbacks exposing a reference capture of the
  actual offset evaluated in `GeometryEffect.effectValue`. SwiftUI effects can move rendering without
  changing a hosting UIView's converted frame. `onEndDraggingWithPresentation`
  receives both model and drawing offsets, and `onPresentingOffsetChange`
  forwards changes directly from actual effect evaluation. Reference storage
  avoids mutating SwiftUI state during layout and lets release read the latest
  evaluated value synchronously. Main rendering notifications run synchronously;
  background evaluation records immediately and delivers its notification on main.
  This allows external rendering metadata to follow the actual drawing offset
  without replacing the package's rubber banding or spring implementation.
  Directional gestures also use this recorded position as their initial offset;
  normal and scroll-interoperable modes retain their original initial tracking. The
  original three-argument release callback remains the default.
- Regression tests for admission ordering, right-swipe policy, and cancellation
  after an accepted handoff and external offset reset, plus release callback
  precedence, mutable-velocity propagation, and actual geometry-effect evaluation
  without `animatableData` setter calls. Upstream tests are retained.

Directional mode requires iOS 18. Existing `.directional` property syntax is
preserved; the hooks use `.directional(isEnabled:attachmentView:shouldBegin:onRecognizer:)`.
The package's normal, high-priority, and simultaneous modes retain their
upstream behavior and availability.

This copy intentionally excludes `.git`, build products, development apps, and
dependency checkouts. It can be replaced with an upstream revision once the
extension is reviewed and published.
