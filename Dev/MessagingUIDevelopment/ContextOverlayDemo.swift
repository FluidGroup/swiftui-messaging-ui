import ContextOverlay
import SwiftUI
import UIKit

/// Presents an ordinary project card through a live, message-independent overlay.
///
/// The source is one UIKit view retained by SwiftUI. Its spinner, render ID, and
/// elapsed counter belong to that view, so recreating the destination would be
/// visible even if a second card had the same title.
struct ContextOverlayDemo: View {
  @State private var state = ContextOverlayState<String>()
  @State private var source = ContextOverlaySource()
  @State private var isSlow = false
  @State private var isPinned = false

  var body: some View {
    VStack(spacing: 0) {
      Toggle("Slow animation", isOn: $isSlow)
        .disabled(state.presentation != nil)
        .padding(16)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("Project context")
            .font(.title2.bold())

          Text("Tap the card to move its live rendering into an overlay. The destination can contain any controls.")
            .foregroundStyle(.secondary)

          ContextProbeCard(
            source: source,
            title: "Weekend project",
            onSourceChange: { [weak state] source, attached in
              state?.sourceDidChange(source, attached: attached)
            }
          )
          .frame(height: 148)
          .onTapGesture {
            isPinned = false
            state.present("Weekend project", from: source)
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Open Weekend project context")
          .accessibilityAddTraits(.isButton)
          .accessibilityIdentifier("context-overlay-source")

          Text("This screen uses a plain SwiftUI ScrollView. The source does not use a message cell or TiledView.")
            .font(.footnote)
            .foregroundStyle(.secondary)

          ForEach(0..<6) { index in
            Label("Project note \(index + 1)", systemImage: "note.text")
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(16)
              .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
          }
        }
        .padding(20)
      }
      .allowsHitTesting(state.presentation == nil)
      .overlay {
        ContextOverlay(state: state) { presentation in
          VStack(spacing: 20) {
            Text(presentation.context)
              .font(.title2.bold())

            presentation.sourcePlaceholder

            Text(isPinned ? "Saved for later" : "Choose an action for this project.")
              .foregroundStyle(.secondary)

            HStack(spacing: 12) {
              Button(isPinned ? "Saved" : "Keep for later", systemImage: "pin") {
                isPinned = true
              }
              .buttonStyle(.bordered)
              .disabled(isPinned || state.isDismissing)

              Button("Close") { state.dismiss() }
                .buttonStyle(.borderedProminent)
                .disabled(state.isDismissing)
                .accessibilityIdentifier("context-overlay-close")
            }
          }
          .padding(20)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color(.systemBackground).opacity(0.94))
          .opacity(state.isPresented ? 1 : 0)
          .allowsHitTesting(state.isPresented)
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 4) {
        Text(state.status)
        Text("The render ID and elapsed counter should continue through presentation and return.")
          .foregroundStyle(.secondary)
      }
      .font(.caption)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
    }
    .navigationTitle("Context Overlay")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: isSlow) { _, isSlow in
      state.animation = .spring(response: isSlow ? 3 : 0.45, dampingFraction: 0.82)
    }
    .onDisappear { state.cancel() }
  }
}

/// Adapts a caller-owned UIKit rendering view to the generic source contract.
///
/// ContextOverlay needs only a rendering reference and its resting container;
/// this card supplies both without depending on any cell implementation.
@MainActor
private struct ContextProbeCard: UIViewRepresentable {
  let source: ContextOverlaySource
  let title: String
  let onSourceChange: (ContextOverlaySource, Bool) -> Void

  func makeUIView(context: Context) -> ContextProbeCardView {
    ContextProbeCardView(source: source, title: title, onSourceChange: onSourceChange)
  }

  func updateUIView(_ view: ContextProbeCardView, context: Context) {
    view.titleLabel.text = title
    view.onSourceChange = onSourceChange
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: ContextProbeCardView, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? 320, height: 148)
  }

  static func dismantleUIView(_ view: ContextProbeCardView, coordinator: ()) {
    view.disconnect()
  }
}

/// Owns independent UIKit animation and counter state for live-portal verification.
///
/// The timer runs only while this exact view is attached to a window. Hiding its
/// source through a portal keeps it attached, so the elapsed counter continues.
@MainActor
private final class ContextProbeCardView: UIView {
  let titleLabel = UILabel()
  var onSourceChange: (ContextOverlaySource, Bool) -> Void

  private let source: ContextOverlaySource
  private let renderID = UUID()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let counterLabel = UILabel()
  private var timer: Timer?
  private var elapsedTicks = 0
  private var isConnected = true

  init(source: ContextOverlaySource, title: String, onSourceChange: @escaping (ContextOverlaySource, Bool) -> Void) {
    self.source = source
    self.onSourceChange = onSourceChange
    super.init(frame: .zero)

    backgroundColor = UIColor.systemTeal.withAlphaComponent(0.15)
    layer.cornerRadius = 20
    clipsToBounds = true

    titleLabel.text = title
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.adjustsFontForContentSizeCategory = true

    let identityLabel = UILabel()
    identityLabel.text = "Render ID: \(String(renderID.uuidString.prefix(6)))"
    identityLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    identityLabel.textColor = .secondaryLabel

    counterLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
    counterLabel.textColor = .secondaryLabel
    updateCounter()

    spinner.color = .systemTeal
    spinner.hidesWhenStopped = false
    let probeRow = UIStackView(arrangedSubviews: [spinner, counterLabel])
    probeRow.axis = .horizontal
    probeRow.alignment = .center
    probeRow.spacing = 10

    let stack = UIStackView(arrangedSubviews: [titleLabel, identityLabel, probeRow])
    stack.axis = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    // This source has no swipe transform, so its drawing and resting geometry
    // share the same view. A caller with a gesture can supply distinct views.
    source.bind(renderingView: self, containerView: self)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard isConnected else { return }

    let attached = window != nil
    if attached {
      spinner.startAnimating()
      startTimerIfNeeded()
    } else {
      spinner.stopAnimating()
      stopTimer()
    }
    onSourceChange(source, attached)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if isConnected, window != nil { onSourceChange(source, true) }
  }

  /// Stops the probe and releases its source binding before SwiftUI removes it.
  func disconnect() {
    guard isConnected else { return }
    isConnected = false
    stopTimer()
    spinner.stopAnimating()
    onSourceChange(source, false)
    source.unbind(from: self)
  }

  private func startTimerIfNeeded() {
    guard timer == nil else { return }
    let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.elapsedTicks += 1
        self.updateCounter()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func updateCounter() {
    counterLabel.text = String(format: "Elapsed: %.1f s", Double(elapsedTicks) / 10)
  }
}

#Preview {
  NavigationStack {
    ContextOverlayDemo()
  }
}
