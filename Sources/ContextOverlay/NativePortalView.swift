// Adapted from FluidInterfaceKit's NativePortalView.swift.
// https://github.com/FluidGroup/FluidInterfaceKit/blob/main/Sources/FluidPortal/NativePortalView.swift
//
// MIT License
// Copyright (c) 2022 Muukii
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import UIKit

#if DEBUG
import SwiftUI
#endif

/// Displays a live copy of a mounted view through UIKit's native portal.
///
/// The source retains its hierarchy, state, and animations. The native backend
/// can resolve portal hits against the original source subtree.
/// This internal renderer uses private API and fails initialization when absent.
@MainActor
final class NativePortalView: UIView {

  private let backingView: UIView

  /// Creates a portal, or returns nil when the native runtime class is missing.
  init?(sourceView: UIView?) {
    guard let portalClass = NSClassFromString("_" + encodeText("VJQpsubmWjfx", -1)) as? UIView.Type else {
      return nil
    }
    backingView = portalClass.init(frame: .zero)
    super.init(frame: .zero)
    backingView.isUserInteractionEnabled = true
    addSubview(backingView)
    self.sourceView = sourceView
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// The original rendering. Reads reflect the native backend's actual binding.
  var sourceView: UIView? {
    get { backingView.value(forKey: "sourceView") as? UIView }
    set {
      backingView.setValue(newValue, forKey: "sourceView")
      invalidateIntrinsicContentSize()
    }
  }

  /// Whether the source's drawing is hidden while this portal mirrors it.
  var hidesSourceView: Bool {
    get { backingView.value(forKey: "hidesSourceView") as? Bool ?? false }
    set { backingView.setValue(newValue, forKey: "hidesSourceView") }
  }

  /// Whether the native portal participates in hit testing.
  var allowsHitTesting: Bool {
    get { backingView.value(forKey: "allowsHitTesting") as? Bool ?? false }
    set { backingView.setValue(newValue, forKey: "allowsHitTesting") }
  }

  /// Whether UIKit resolves portal hits against the source's original subtree.
  var forwardsClientHitTestingToSourceView: Bool {
    get { backingView.value(forKey: "forwardsClientHitTestingToSourceView") as? Bool ?? false }
    set { backingView.setValue(newValue, forKey: "forwardsClientHitTestingToSourceView") }
  }

  /// Whether the source's alpha is applied to the mirrored drawing.
  var matchesAlpha: Bool {
    get { backingView.value(forKey: "matchesAlpha") as? Bool ?? false }
    set { backingView.setValue(newValue, forKey: "matchesAlpha") }
  }

  /// Whether the source's transform is applied to the mirrored drawing.
  var matchesTransform: Bool {
    get { backingView.value(forKey: "matchesTransform") as? Bool ?? false }
    set { backingView.setValue(newValue, forKey: "matchesTransform") }
  }

  /// Whether the mirror follows the source's position instead of its own layout.
  var matchesPosition: Bool {
    get { backingView.value(forKey: "matchesPosition") as? Bool ?? false }
    set { backingView.setValue(newValue, forKey: "matchesPosition") }
  }

  override var intrinsicContentSize: CGSize {
    guard let sourceView else {
      return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
    let size = sourceView.bounds.size
    return size.width > 0 && size.height > 0 ? size : sourceView.intrinsicContentSize
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    backingView.frame = bounds
  }

  /// Returns source hits while allowing inactive and empty regions to pass through.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    // Native forwarding can remain active even when allowsHitTesting is false.
    // Enforce that gate here, including the interval after source disconnection.
    guard allowsHitTesting, sourceView != nil else { return nil }
    let hitView = super.hitTest(point, with: event)
    // The wrapper has no interaction of its own. Preserve native hit handling
    // when client forwarding is disabled, as in the reference implementation.
    return hitView === self ? nil : hitView
  }

  /// Restores the source before removing the native reference.
  func disconnect() {
    hidesSourceView = false
    sourceView = nil
  }
}

/// Shifts fixed runtime identifiers using FluidInterfaceKit's scalar encoding.
private func encodeText(_ string: String, _ key: Int) -> String {
  var result = ""
  for scalar in string.unicodeScalars {
    result.append(Character(UnicodeScalar(UInt32(Int(scalar.value) + key))!))
  }
  return result
}

#if DEBUG

private extension NativePortalView {

  /// Compares real input delivery without overlay transitions or matched geometry.
  struct Preview: View {
    let sourceKind: SourceKind

    @State private var placement: Placement = .samePosition
    @State private var configuration = PortalDestination.Configuration()
    @State private var counters = Counters()

    var body: some View {
      ScrollView {
        VStack(spacing: 16) {
          Picker("Placement", selection: $placement) {
            ForEach(Placement.allCases) { placement in
              Text(placement.rawValue).tag(placement)
            }
          }
          .pickerStyle(.segmented)

          Canvas(
            sourceKind: sourceKind,
            placement: placement,
            configuration: configuration,
            counters: counters
          )
          .frame(height: 400)

          Text("Button: \(counters.button) · Gesture: \(counters.gesture) · Background: \(counters.background)")
            .font(.system(.caption, design: .monospaced))
          Button("Reset counts") {
            counters.button = 0
            counters.gesture = 0
            counters.background = 0
          }

          DisclosureGroup("Native options") {
            Toggle("matchesAlpha", isOn: $configuration.matchesAlpha)
            Toggle("matchesTransform", isOn: $configuration.matchesTransform)
            Toggle("matchesPosition", isOn: $configuration.matchesPosition)
            Toggle("allowsHitTesting", isOn: $configuration.allowsHitTesting)
            Toggle(
              "forwardsClientHitTestingToSourceView",
              isOn: $configuration.forwardsClientHitTestingToSourceView
            )
            Toggle("hidesSourceView", isOn: $configuration.hidesSourceView)
          }
          .font(.caption)

          Text("Portal modes block direct source input. Frames show the wrapper; native matchesPosition may change where the mirror draws.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
      }
    }
  }

  /// Selects the framework whose source owns the interactive controls.
  enum SourceKind {
    case uiKit
    case swiftUI
  }

  /// Changes only the portal's frame, preserving the mounted source's identity.
  enum Placement: String, CaseIterable, Identifiable {
    case original = "Source only"
    case samePosition = "Same position"
    case differentPosition = "Different position"

    var id: Self { self }
  }

  /// Counts actual control and gesture callbacks, independently of hit-test lookup.
  @MainActor
  @Observable
  final class Counters {
    var button = 0
    var gesture = 0
    var background = 0
  }

  /// Keeps one source controller mounted while passing live options to the canvas.
  struct Canvas: UIViewControllerRepresentable {
    let sourceKind: SourceKind
    let placement: Placement
    let configuration: PortalDestination.Configuration
    let counters: Counters

    func makeUIViewController(context: Context) -> CanvasController {
      let controller = CanvasController(sourceKind: sourceKind, counters: counters)
      controller.loadViewIfNeeded()
      controller.update(placement: placement, configuration: configuration)
      return controller
    }

    func updateUIViewController(_ controller: CanvasController, context: Context) {
      controller.update(placement: placement, configuration: configuration)
    }

    static func dismantleUIViewController(_ controller: CanvasController, coordinator: ()) {
      controller.disconnect()
    }
  }

  /// Owns the source, its containment, and a single portal in a shared coordinate space.
  @MainActor
  final class CanvasController: UIViewController {
    private let sourceController: UIViewController
    private let sourceKind: SourceKind
    private let counters: Counters
    private let backgroundButton = UIButton()
    private let sourceInputShield = UIView()
    private let sourceOutline = UIView()
    private let portalOutline = UIView()
    private let geometryLabel = UILabel()
    private let portal: NativePortalView
    private var placement: Placement = .original
    private var configuration = PortalDestination.Configuration()
    private var isAppeared = false

    init(sourceKind: SourceKind, counters: Counters) {
      self.sourceKind = sourceKind
      self.counters = counters
      switch sourceKind {
      case .uiKit:
        sourceController = UIViewController()
      case .swiftUI:
        let hostingController = UIHostingController(rootView: SwiftUISource(counters: counters))
        hostingController.safeAreaRegions = []
        sourceController = hostingController
      }
      guard let portal = NativePortalView(sourceView: nil) else {
        preconditionFailure("Native portal is unavailable on this runtime")
      }
      self.portal = portal
      super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .secondarySystemBackground
      backgroundButton.addAction(UIAction { [counters] _ in
        counters.background += 1
      }, for: .touchUpInside)
      view.addSubview(backgroundButton)

      addChild(sourceController)
      view.addSubview(sourceController.view)
      sourceController.didMove(toParent: self)
      switch sourceKind {
      case .uiKit:
        sourceController.view.backgroundColor = .systemTeal.withAlphaComponent(0.2)
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = "UIKit Button"
        let button = UIButton(configuration: buttonConfiguration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [counters] _ in
          counters.button += 1
        }, for: .touchUpInside)
        sourceController.view.addSubview(button)
        NSLayoutConstraint.activate([
          button.centerXAnchor.constraint(equalTo: sourceController.view.centerXAnchor),
          button.centerYAnchor.constraint(equalTo: sourceController.view.centerYAnchor),
        ])
      case .swiftUI:
        sourceController.view.backgroundColor = .clear
      }

      // A transparent sibling prevents a nil portal hit from reaching the original
      // source in the aligned case. Forwarded hits can still resolve that source.
      sourceInputShield.backgroundColor = .clear
      view.addSubview(sourceInputShield)
      view.addSubview(portal)
      sourceOutline.layer.borderColor = UIColor.systemTeal.cgColor
      portalOutline.layer.borderColor = UIColor.systemOrange.cgColor
      for outline in [sourceOutline, portalOutline] {
        outline.layer.borderWidth = 2
        outline.isUserInteractionEnabled = false
        view.addSubview(outline)
      }
      geometryLabel.numberOfLines = 0
      geometryLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
      geometryLabel.textColor = .secondaryLabel
      view.addSubview(geometryLabel)
    }

    /// Applies every option without recreating the source or its SwiftUI state.
    func update(placement: Placement, configuration: PortalDestination.Configuration) {
      self.placement = placement
      self.configuration = configuration
      switch placement {
      case .original:
        portal.disconnect()
        portal.isHidden = true
        sourceInputShield.isHidden = true
      case .samePosition, .differentPosition:
        portal.matchesAlpha = configuration.matchesAlpha
        portal.matchesTransform = configuration.matchesTransform
        portal.matchesPosition = configuration.matchesPosition
        portal.allowsHitTesting = configuration.allowsHitTesting
        portal.forwardsClientHitTestingToSourceView = configuration.forwardsClientHitTestingToSourceView
        // makeUIViewController runs before window attachment. Bind after both
        // branches are mounted so the native renderer has a live source layer.
        if isAppeared,
          let window = view.window,
          sourceController.view.window === window,
          portal.window === window,
          portal.sourceView !== sourceController.view
        {
          portal.sourceView = sourceController.view
        }
        if portal.sourceView != nil {
          portal.hidesSourceView = configuration.hidesSourceView
        }
        portal.isHidden = false
        sourceInputShield.isHidden = false
      }
      view.setNeedsLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      view.layoutIfNeeded()
      sourceController.view.layoutIfNeeded()
      isAppeared = true
      update(placement: placement, configuration: configuration)
    }

    override func viewWillDisappear(_ animated: Bool) {
      isAppeared = false
      portal.disconnect()
      super.viewWillDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      let width = max(0, min(view.bounds.width - 32, 300))
      let sourceFrame = CGRect(x: (view.bounds.width - width) / 2, y: 24, width: width, height: 140)
      backgroundButton.frame = view.bounds
      sourceController.view.frame = sourceFrame
      sourceInputShield.frame = sourceFrame
      sourceOutline.frame = sourceFrame
      switch placement {
      case .original, .samePosition:
        portal.frame = sourceFrame
      case .differentPosition:
        portal.frame = sourceFrame.offsetBy(dx: 0, dy: 170)
      }
      portalOutline.frame = portal.frame
      portalOutline.isHidden = placement == .original
      portal.layoutIfNeeded()
      geometryLabel.frame = CGRect(x: 16, y: 342, width: width, height: 52)
      if let window = view.window {
        let sourceRect = sourceController.view.convert(sourceController.view.bounds, to: window)
        let portalRect = portal.convert(portal.bounds, to: window)
        geometryLabel.text = "Source (teal): \(NSCoder.string(for: sourceRect))\nPortal (orange): \(NSCoder.string(for: portalRect))\nΔ: (\(Int(portalRect.minX - sourceRect.minX)), \(Int(portalRect.minY - sourceRect.minY))) pt"
      }
    }

    /// Restores the source before the preview releases its controller hierarchy.
    func disconnect() {
      portal.disconnect()
    }
  }

  /// Supplies SwiftUI controls whose original hosting view remains mounted.
  struct SwiftUISource: View {
    let counters: Counters

    var body: some View {
      VStack(spacing: 12) {
        Button("SwiftUI Button") { counters.button += 1 }
          .buttonStyle(.borderedProminent)
        Text("SwiftUI tap gesture")
          .padding(12)
          .background(.orange.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
          .onTapGesture { counters.gesture += 1 }
          .accessibilityAddTraits(.isButton)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.teal.opacity(0.2))
    }
  }
}

#Preview("UIKit forwarding") {
  NativePortalView.Preview(sourceKind: .uiKit)
}

#Preview("SwiftUI forwarding") {
  NativePortalView.Preview(sourceKind: .swiftUI)
}

#endif
