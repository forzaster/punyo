import SwiftUI

struct DebugSliderPanel: View {
    @Bindable var params: PunyoParameters
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            handle
            if isExpanded {
                content
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var handle: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "slider.horizontal.3")
                Text(isExpanded ? "閉じる" : "パラメータ")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("リセット") { params.reset() }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .opacity(isExpanded ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var content: some View {
        VStack(spacing: 10) {
            slider("粘度",     value: $params.viscosity,   range: PunyoParameters.viscosityRange,   fmt: "%.2f")
            slider("弾性",     value: $params.elasticity,  range: PunyoParameters.elasticityRange,  fmt: "%.0f")
            slider("減衰",     value: $params.damping,     range: PunyoParameters.dampingRange,     fmt: "%.1f")
            slider("行き過ぎ", value: $params.overshoot,   range: PunyoParameters.overshootRange,   fmt: "%.2f")
            slider("逃げ速度", value: $params.fleeSpeed,   range: PunyoParameters.fleeSpeedRange,   fmt: "%.0f")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func slider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        fmt: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .frame(width: 64, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: fmt, value.wrappedValue))
                .font(.caption.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}
