import SwiftUI

struct WheelView: View {
    @ObservedObject var model: PaddockController
    @ObservedObject private var live: WheelLiveState
    init(model: PaddockController) { self.model = model; live = model.live }
    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                liveInput.frame(width: 255)
                settings.frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionLabel(text: "Назначения кнопок")
                        Text("Нажмите «Назначить», затем кнопку на руле.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.pendingBinding != nil { Button("Отмена") { model.pendingBinding = nil } }
                }
                ForEach(ButtonAction.all) { action in
                    HStack(spacing: 12) {
                        Image(systemName: action.symbol).foregroundStyle(.secondary).frame(width: 22)
                        Text(action.name).font(.system(size: 12))
                        Spacer()
                        if model.pendingBinding == action.id {
                            Text("Нажмите кнопку…").font(.caption).foregroundStyle(PaddockStyle.accent)
                        } else if let button = model.configuration.bindings[action.id] {
                            Text("Кнопка \(button)").font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 9).padding(.vertical, 5).background(model.pressed.contains(button) ? PaddockStyle.accent.opacity(0.25) : Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 6))
                        } else { Text("Не назначено").font(.caption).foregroundStyle(.tertiary) }
                        Button(model.configuration.bindings[action.id] == nil ? "Назначить" : "Изменить") { model.beginBinding(action.id) }
                            .frame(width: 90).disabled(!model.connected)
                        Button { model.unbind(action.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("Снять назначение").disabled(model.configuration.bindings[action.id] == nil)
                    }.padding(.vertical, 6)
                    if action.id != ButtonAction.all.last?.id { Divider().opacity(0.4) }
                }
            }.paddockPanel()
            Text("Новые назначения и угол применяются при запуске следующего заезда. Одна кнопка назначается одному действию; клавиатурные команды игры сохраняются.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var liveInput: some View {
        VStack(spacing: 16) {
            HStack { SectionLabel(text: "Живой ввод"); Spacer(); Circle().fill(model.connected ? .green : .gray).frame(width: 6, height: 6) }
            Image(systemName: "steeringwheel").font(.system(size: 90, weight: .ultraLight))
                .foregroundStyle(model.connected ? Color.white.opacity(0.8) : Color.gray)
                .rotationEffect(.degrees(model.steering * Double(model.configuration.angle) / 2))
                .frame(height: 118)
            Text(String(format: "%+.0f°", model.steering * Double(model.configuration.angle) / 2)).font(.system(size: 24, weight: .light, design: .monospaced))
            pedal("ГАЗ", value: model.throttle, color: .green)
            pedal("ТОРМОЗ", value: model.brake, color: PaddockStyle.accent)
            HStack { Text("Кнопки").foregroundStyle(.secondary); Spacer(); Text(model.pressed.isEmpty ? "—" : model.pressed.sorted().map(String.init).joined(separator: ", ")).monospacedDigit() }.font(.caption)
        }.paddockPanel()
    }
    private func pedal(_ name: String, value: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack { Text(name).font(.system(size: 9, weight: .medium)).tracking(1); Spacer(); Text("\(Int(value * 100))%").font(.system(size: 10, design: .monospaced)) }.foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) { Capsule().fill(Color.white.opacity(0.06)); Capsule().fill(color).frame(width: max(0, geometry.size.width * value)) }
            }.frame(height: 5)
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "Настройки базы и игры")
            HStack { Text("Угол поворота").fontWeight(.medium); Spacer(); Text("\(model.configuration.angle)°").monospacedDigit().foregroundStyle(PaddockStyle.accent) }
            Slider(value: Binding(get: { Double(model.configuration.angle) }, set: { model.configuration.angle = Int($0) }), in: 90...2700, step: 10)
            HStack(spacing: 8) {
                ForEach([360, 540, 900, 1080], id: \.self) { angle in
                    Button("\(angle)°") { model.configuration.angle = angle }.buttonStyle(.bordered).tint(model.configuration.angle == angle ? PaddockStyle.accent : .gray)
                }
            }
            Divider()
            HStack { Text("Сила отдачи").fontWeight(.medium); Spacer(); Text("\(Int(model.configuration.gain * 100))%").monospacedDigit().foregroundStyle(PaddockStyle.accent) }
            Slider(value: $model.configuration.gain, in: 0...1, step: 0.01)
            Text("Усиление игровых эффектов. База и игра получают одинаковый угол поворота; он сохраняется в пресете.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Применить настройки") { model.applyWheel() }.disabled(model.gameRunning || model.operation != nil || !model.connected)
                Spacer()
                if model.gameRunning { Text("После завершения заезда").font(.caption2).foregroundStyle(.secondary) }
            }
        }.font(.system(size: 12)).paddockPanel()
    }
}
