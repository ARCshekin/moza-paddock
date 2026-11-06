import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var controller: MozaController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            steeringIndicator
            angleControl
            calibrationControl
            Divider()
            forceControls
            if !controller.temperatures.isEmpty {
                Divider()
                temperatures
            }
            if let message = controller.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
        .task { controller.start() }
    }

    // MARK: - Заголовок

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(controller.isConnected ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.isConnected ? controller.modelName : "MOZA")
                    .font(.system(size: 13, weight: .semibold))
                Text(controller.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if controller.isBusy {
                ProgressView().controlSize(.small)
            } else if !controller.isConnected {
                Button("Искать") { controller.connect() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Индикатор руля

    private var steeringIndicator: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Положение руля")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(controller.steeringDegrees.map { String(format: "%+.0f°", $0) } ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let fraction = ((controller.steeringDegrees ?? 0) / max(controller.angle / 2, 1) + 1) / 2
                let clamped = min(max(fraction, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    // Отметка центра.
                    Rectangle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 1)
                        .offset(x: geometry.size.width / 2)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: clamped * (geometry.size.width - 10))
                }
            }
            .frame(height: 10)
        }
    }

    // MARK: - Угол поворота

    private var angleControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Угол поворота")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(controller.angle))°")
                    .font(.system(size: 11, design: .monospaced))
            }
            Slider(
                value: $controller.angle,
                in: MozaController.angleRange,
                step: MozaController.angleStep,
                onEditingChanged: { editing in
                    // Пишем только когда ползунок отпущен, чтобы не засыпать базу командами.
                    if !editing { controller.applyAngle() }
                }
            )
            .disabled(!controller.isConnected)
        }
    }

    private var calibrationControl: some View {
        Button {
            controller.calibrateCenter()
        } label: {
            Text("Калибровать центр").frame(maxWidth: .infinity)
        }
        .disabled(!controller.isConnected || controller.isBusy)
        .help("Выставьте руль ровно по центру, затем нажмите")
    }

    // MARK: - Отдача

    private var forceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRow(
                title: "Сила отдачи",
                value: $controller.ffbStrength,
                range: 0...100,
                suffix: "%",
                onCommit: controller.applyFFBStrength
            )
            sliderRow(
                title: "Лимит момента",
                value: $controller.torque,
                range: 50...100,
                suffix: "%",
                onCommit: controller.applyTorque
            )
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(suffix)")
                    .font(.system(size: 11, design: .monospaced))
            }
            Slider(value: value, in: range, step: 1, onEditingChanged: { editing in
                if !editing { onCommit() }
            })
            .disabled(!controller.isConnected)
        }
    }

    // MARK: - Температуры и подвал

    private var temperatures: some View {
        HStack(spacing: 12) {
            ForEach(controller.temperatures, id: \.label) { entry in
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(entry.value)
                        .font(.system(size: 11, design: .monospaced))
                }
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Button("Обновить") { controller.connect() }
                .controlSize(.small)
            Spacer()
            Button("Выйти") {
                controller.stop()
                NSApplication.shared.terminate(nil)
            }
            .controlSize(.small)
        }
    }
}
