//
//  TiledSelfSizing.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/20.
//

import SwiftUI

extension EnvironmentValues {

  /// An action that asks the hosting collection view cell to re-measure its intrinsic content size.
  ///
  /// Call this from hosted TiledView content when a state change affects height and UIKit does not
  /// automatically re-query the preferred layout attributes.
  @Entry var updateSelfSizing: () -> Void = {}
}
