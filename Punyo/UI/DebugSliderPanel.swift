import SwiftUI

struct DebugSliderPanel: View {
    @Bindable var params: PunyoParameters
    @Bindable var settings: PunyoRenderSettings
    let physics: PunyoPhysics
    @Bindable var speaker: PunyoSpeaker
    @Bindable var modelSource: FoundationModelSpeechSource
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
            toonToggleRow
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
            Divider().opacity(0.4)
            personaRow
            temperatureRow
            lengthRow
            descriptorReadout
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Speech debug

    // The whole point of the three-stage pipeline is that a weird utterance
    // is diagnosable from the reading. This block is that diagnosis panel:
    // last descriptor tags, summary, and which source spoke.
    private var descriptorReadout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("直近の一言")
                    .font(.caption.weight(.medium))
                Spacer()
                Text(speaker.line ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            HStack {
                originBadge(speaker.lastOrigin)
                Text(modelSource.isAvailable ? "モデル可" : "モデル不可")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
                    .foregroundStyle(.secondary)
                Spacer()
                if let err = modelSource.lastErrorSummary {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            if let d = speaker.lastDescriptor {
                Text(d.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !d.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(d.tags, id: \.self) { tag in
                                Text(tag.rawValue)
                                    .font(.caption2.monospaced())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            }
                        }
                    }
                }
            } else {
                Text("まだ捕まえていない")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func originBadge(_ origin: PunyoSpeaker.Origin) -> some View {
        let (label, color): (String, Color)
        switch origin {
        case .model:    (label, color) = ("model",    .green)
        case .template: (label, color) = ("template", .blue)
        case .none:     (label, color) = ("—",        .gray)
        }
        return Text(label)
            .font(.caption2.monospaced())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.25)))
            .foregroundStyle(color)
    }

    // Persona picker. Writes through to both the speaker (context.persona)
    // and the model source (which rebuilds its session so the new
    // instructions actually take effect).
    private var personaRow: some View {
        HStack(spacing: 10) {
            Text("性格")
                .font(.caption.weight(.medium))
                .frame(width: 64, alignment: .leading)
            Picker("", selection: Binding(
                get: { speaker.persona.id },
                set: { newId in
                    if let p = PunyoPersona.all.first(where: { $0.id == newId }) {
                        speaker.persona = p
                        modelSource.setPersona(p)
                    }
                }
            )) {
                ForEach(PunyoPersona.all) { p in
                    Text(p.name).tag(p.id)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var temperatureRow: some View {
        HStack(spacing: 10) {
            Text("温度")
                .font(.caption.weight(.medium))
                .frame(width: 64, alignment: .leading)
            Slider(value: $modelSource.temperature, in: 0.0...1.5)
            Text(String(format: "%.2f", modelSource.temperature))
                .font(.caption.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }

    private var lengthRow: some View {
        HStack(spacing: 10) {
            Text("上限")
                .font(.caption.weight(.medium))
                .frame(width: 64, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(modelSource.maxResponseTokens) },
                    set: { modelSource.maxResponseTokens = Int($0) }
                ),
                in: 8...64, step: 1
            )
            Text("\(modelSource.maxResponseTokens)")
                .font(.caption.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
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

    // Top-level style switch: the same material colors, rendered flat/cel-like
    // instead of the default lit surface. Backed by `settings.technique` so the
    // technique picker stays a valid override for anyone poking at bench
    // shaders.
    private var toonToggleRow: some View {
        HStack(spacing: 10) {
            Text("Toon風")
                .font(.caption.weight(.medium))
                .frame(width: 64, alignment: .leading)
            Toggle("", isOn: Binding(
                get: { settings.technique == .toonMaterial },
                set: { settings.technique = $0 ? .toonMaterial : .material }
            ))
            .labelsHidden()
            .disabled(!settings.technique.usesAppearance)
            Spacer()
        }
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
