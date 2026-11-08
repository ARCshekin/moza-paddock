import SwiftUI
import MozaKit

struct WheelTuningView: View {
    @ObservedObject var model: PaddockController
    private func value(_ key: WritableKeyPath<WheelInputSettings, Double>) -> Binding<Double> {
        Binding(get: { model.configuration.wheelSettings[keyPath: key] }, set: { model.configuration.wheelSettings[keyPath: key] = $0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(text: "Оси и синхронизация")
                Spacer()
                Button("Руль 1:1") {
                    var tuning = model.configuration.wheelSettings
                    tuning.steeringGamma = 1; tuning.steeringDeadzone = 0; tuning.steeringSaturation = 1
                    tuning.steeringScale = 1; tuning.steeringFilter = 0; tuning.speedSensitivity = 0
                    model.configuration.wheelSettings = tuning
                }
            }
            setting("Линейность руля (гамма)", key: \.steeringGamma, range: 0.5...3, step: 0.05)
            Text("1 — линейно; больше 1 — мягче около центра. Для совпадения углов выберите 1:1 и одинаковый угол базы и игры.").font(.caption).foregroundStyle(.secondary)
            SteeringCurve(settings: model.configuration.wheelSettings).frame(height: 90)
            setting("Мёртвая зона руля", key: \.steeringDeadzone, range: 0...0.15, step: 0.005)
            setting("Насыщение руля", key: \.steeringSaturation, range: 0.5...1, step: 0.01)
            setting("Масштаб в игре", key: \.steeringScale, range: 0.5...1.5, step: 0.01)
            setting("Сглаживание руля", key: \.steeringFilter, range: 0...1, step: 0.01)
            Divider()
            setting("Линейность газа", key: \.throttleGamma, range: 0.5...3, step: 0.05)
            setting("Линейность тормоза", key: \.brakeGamma, range: 0.5...4, step: 0.05)
            setting("Отпускание сцепления кнопкой, мс", key: \.clutchReleaseMilliseconds, range: 0...600, step: 10)
            Text("Сцепление выжимается при удержании назначенной кнопки. 0 мс — мгновенное отпускание; при таком назначении автосцепление отключается.").font(.caption).foregroundStyle(.secondary)
        }.font(.system(size: 12)).paddockPanel()
    }
    private func setting(_ title: String, key: WritableKeyPath<WheelInputSettings, Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(spacing: 5) {
            HStack { Text(title); Spacer(); Text(String(format: key == \.clutchReleaseMilliseconds ? "%.0f" : "%.2f", value(key).wrappedValue)).monospacedDigit().foregroundStyle(PaddockStyle.accent) }
            Slider(value: value(key), in: range, step: step)
        }
    }
}

private struct SteeringCurve: View {
    let settings: WheelInputSettings
    var body: some View {
        Canvas { context, size in
            var grid = Path(); grid.move(to: CGPoint(x: 0, y: size.height)); grid.addLine(to: CGPoint(x: size.width, y: 0))
            context.stroke(grid, with: .color(.gray.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4]))
            var curve = Path()
            for i in 0...100 {
                let x = Double(i) / 100
                let point = CGPoint(x: x * size.width, y: (1 - settings.steering(x)) * size.height)
                if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            context.stroke(curve, with: .color(PaddockStyle.accent), lineWidth: 2)
        }.accessibilityLabel("Кривая ввода: горизонталь — положение руля, вертикаль — ввод игры")
    }
}
