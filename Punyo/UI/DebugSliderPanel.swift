import SwiftUI

struct DebugSliderPanel: View {
    @Bindable var params: PunyoParameters
    @Bindable var settings: PunyoRenderSettings
    let physics: PunyoPhysics
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
                Button("リセット") { params.reset(to: settings.material.physics) }
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
            materialRow
            techniquePicker
            Divider().opacity(0.4)
            slider("粘度",     value: $params.viscosity,   range: PunyoParameters.viscosityRange,   fmt: "%.2f")
            slider("弾性",     value: $params.elasticity,  range: PunyoParameters.elasticityRange,  fmt: "%.0f")
            slider("減衰",     value: $params.damping,     range: PunyoParameters.dampingRange,     fmt: "%.1f")
            slider("行き過ぎ", value: $params.overshoot,   range: PunyoParameters.overshootRange,   fmt: "%.2f")
            slider("逃げ速度", value: $params.fleeSpeed,   range: PunyoParameters.fleeSpeedRange,   fmt: "%.0f")
            slider("疲労",     value: $params.fatigue,     range: PunyoParameters.fatigueRange,     fmt: "%.2f")
            slider("好奇心",   value: $params.curiosity,   range: PunyoParameters.curiosityRange,   fmt: "%.2f")
            Divider().opacity(0.4)
            staminaReadout
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // Live stamina is the one thing you can't tune by feel alone — seeing the
    // bar drain is what makes the fatigue slider adjustable.
    private var staminaReadout: some View {
        HStack(spacing: 10) {
            Text("体力")
                .font(.caption.weight(.medium))
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(physics.isCaptured ? Color.orange : Color.green)
                        .frame(width: geo.size.width * CGFloat(physics.stamina))
                }
            }
            .frame(height: 6)
            Text(physics.isCaptured ? "捕獲中" : String(format: "%.2f", physics.stamina))
                .font(.caption.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }

    // Selecting a material writes its physics preset into the live parameters,
    // so the sliders below immediately show what that substance is made of and
    // stay editable from there.
    private var materialRow: some View {
        HStack(spacing: 10) {
            Text("素材")
                .font(.caption.weight(.medium))
                .frame(width: 64, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PunyoMaterialLibrary.all) { material in
                        chip(material.name,
                             selected: settings.material.id == material.id) {
                            settings.material = material
                        }
                    }
                    chip("日替わり", selected: false) {
                        settings.material = PunyoMaterialLibrary.daily()
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(_ title: String,
                      selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected
                                   ? Color.accentColor
                                   : Color.primary.opacity(0.12))
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var techniquePicker: some View {
        HStack(spacing: 10) {
            Text("技法")
                .font(.caption.weight(.medium))
                .frame(width: 64, alignment: .leading)
            Picker("", selection: $settings.technique) {
                ForEach(PunyoTechnique.allCases) { tech in
                    Text(tech.rawValue).tag(tech)
                }
            }
            .pickerStyle(.segmented)
        }
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
