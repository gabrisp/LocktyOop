//
//  SafeAreaBarSfe.swift
//  Lockty
//
//  Created by Gabrisp on 29/08/2026.
//

import SwiftUI

extension View {
    /// iOS 26+ gets the new `.safeAreaBar` (proper Liquid Glass bar styling, scroll-edge-aware,
    /// meant for bottom/top action bars specifically); earlier versions fall back to the plain
    /// `.safeAreaInset` equivalent — same call site either way.
    @ViewBuilder
    func customSafeAreaBar<Content: View>(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: edge, alignment: alignment, spacing: spacing, content: content)
        } else {
            self.safeAreaInset(edge: edge, alignment: alignment, spacing: spacing, content: content)
        }
    }

    @ViewBuilder
    func customSafeAreaBar<Content: View>(
        edge: HorizontalEdge,
        alignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: edge, alignment: alignment, spacing: spacing, content: content)
        } else {
            self.safeAreaInset(edge: edge, alignment: alignment, spacing: spacing, content: content)
        }
    }
}
