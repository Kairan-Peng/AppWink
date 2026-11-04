import SwiftUI

/// 为禁用态或信息较长的控件提供“延迟出现”的悬停提示，避免界面长期堆满说明文字。
private struct DelayedHoverTooltipModifier: ViewModifier {
    let tooltip: String?
    let delay: TimeInterval
    let maxWidth: CGFloat

    @State private var isHovering = false
    @State private var isTooltipVisible = false
    @State private var revealWorkItem: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if let tooltip, isTooltipVisible {
                    tooltipBubble(tooltip)
                        .offset(y: 14)
                        .transition(.opacity)
                }
            }
            .onHover(perform: updateHoverState)
            .onDisappear {
                cancelPendingReveal()
                isTooltipVisible = false
            }
            .animation(.easeInOut(duration: 0.18), value: isTooltipVisible)
    }

    /// 悬停时延迟展示，移出时立即收起，避免 tooltip 闪烁。
    private func updateHoverState(_ hovering: Bool) {
        guard let tooltip, !tooltip.isEmpty else {
            return
        }

        isHovering = hovering
        cancelPendingReveal()

        guard hovering else {
            isTooltipVisible = false
            return
        }

        let workItem = DispatchWorkItem {
            guard isHovering else {
                return
            }

            isTooltipVisible = true
        }

        revealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingReveal() {
        revealWorkItem?.cancel()
        revealWorkItem = nil
    }

    private func tooltipBubble(_ tooltip: String) -> some View {
        Text(tooltip)
            .font(.caption)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 16, y: 10)
            .allowsHitTesting(false)
    }
}

extension View {
    /// 统一暴露给 SwiftUI 视图的便捷 API。
    func delayedHoverTooltip(
        _ tooltip: String?,
        delay: TimeInterval = 1.5,
        maxWidth: CGFloat = 280
    ) -> some View {
        modifier(DelayedHoverTooltipModifier(tooltip: tooltip, delay: delay, maxWidth: maxWidth))
    }
}
