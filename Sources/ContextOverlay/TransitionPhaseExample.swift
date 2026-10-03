import SwiftUI

#if DEBUG

/// Demonstrates children responding independently to their parent's transition.
///
/// The parent only inserts or removes the content. Its transition publishes a
/// phase through the environment, and each child derives its own visual effect.
/// This example does not use the UIKit portal or mutate a child's local state.
struct TransitionPhaseExample: View {

  @State private var isVisible = false
  @State private var isSlow = true

  var body: some View {
    VStack(spacing: 24) {
      Text("Transition → Environment → Children")
        .font(.headline)

      Toggle("Slow animation", isOn: $isSlow)

      ZStack {
        RoundedRectangle(cornerRadius: 24)
          .strokeBorder(.secondary.opacity(0.3), style: StrokeStyle(dash: [6]))

        if isVisible {
          PhaseExampleContent()
            .transition(ChildPhaseTransition())
            // Keep outgoing content above the canvas during removal.
            .zIndex(1)
        }
      }
      .frame(height: 280)

      Text(isVisible ? "isVisible = true" : "isVisible = false")
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)

      Button(isVisible ? "Remove" : "Insert") {
        // The same transaction animates the descendant modifiers that change
        // when ChildPhaseTransition publishes its new phase.
        withAnimation(.smooth(duration: isSlow ? 3 : 0.45)) {
          isVisible.toggle()
        }
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("transition-phase-toggle")
    }
    .padding(24)
    .frame(maxWidth: 420)
  }
}

extension EnvironmentValues {
  /// The nearest example transition's phase; ordinary content rests at identity.
  @Entry fileprivate var exampleTransitionPhase: TransitionPhase = .identity
}

/// Publishes a phase without applying a visual effect to the whole container.
///
/// Children must explicitly read `exampleTransitionPhase` to participate.
/// The content's identity stays stable throughout insertion and removal.
private struct ChildPhaseTransition: Transition {

  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .environment(\.exampleTransitionPhase, phase)
  }
}

/// Composes independent children under one insertion and removal boundary.
private struct PhaseExampleContent: View {

  var body: some View {
    ZStack {
      PhaseExampleBackdrop()

      VStack(spacing: 24) {
        PhaseExampleCard()
        PhaseExampleMenu()
      }
      .padding(24)
    }
  }
}

/// Fades the background while the foreground children move separately.
private struct PhaseExampleBackdrop: View {

  @Environment(\.exampleTransitionPhase) private var phase

  var body: some View {
    RoundedRectangle(cornerRadius: 24)
      .fill(.indigo.opacity(0.12))
      .opacity(phase.isIdentity ? 1 : 0)
  }
}

/// Enters from the left and exits to the right using the inherited phase.
private struct PhaseExampleCard: View {

  @Environment(\.exampleTransitionPhase) private var phase

  var body: some View {
    Label("Card", systemImage: "rectangle.on.rectangle")
      .font(.title2.bold())
      .frame(maxWidth: .infinity)
      .padding(24)
      .foregroundStyle(.white)
      .background(.indigo, in: RoundedRectangle(cornerRadius: 16))
      .offset(x: phase.value * 90)
      .opacity(phase.isIdentity ? 1 : 0)
  }
}

/// Shrinks and moves downward independently from the card and background.
private struct PhaseExampleMenu: View {

  @Environment(\.exampleTransitionPhase) private var phase

  var body: some View {
    Label("Menu", systemImage: "ellipsis")
      .font(.headline)
      .frame(maxWidth: .infinity)
      .padding(16)
      .foregroundStyle(.white)
      .background(.teal, in: RoundedRectangle(cornerRadius: 12))
      .scaleEffect(phase.isIdentity ? 1 : 0.65)
      .offset(y: phase.isIdentity ? 0 : 36)
      .opacity(phase.isIdentity ? 1 : 0)
  }
}

#Preview("Child transition phases") {
  TransitionPhaseExample()
}

#endif
