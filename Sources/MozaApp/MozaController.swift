import Combine
import Foundation
import MozaKit

/// Состояние приложения: владеет serial-каналом настроек и HID-каналом ввода.
///
/// `MozaDevice` не потокобезопасен, поэтому обращение к нему замкнуто на очереди
/// `queue`, а публикуемые свойства меняются только на главном потоке.
final class MozaController: ObservableObject {
    /// Один экземпляр на приложение: содержимое `MenuBarExtra` создаётся лишь при
    /// первом клике по иконке, а подключаться и читать телеметрию нужно с запуска.
    static let shared = MozaController()

    @Published var isConnected = false
    @Published var statusText = "Поиск базы…"
    @Published var modelName = "MOZA"

    @Published var angle: Double = 900
    @Published var ffbStrength: Double = 100
    @Published var torque: Double = 100

    @Published var temperatures: [Temperature] = []
    @Published var steeringDegrees: Double?

    @Published var message: String?
    @Published var isBusy = false

    struct Temperature: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// Шаг ползунка угла. Кратность 10 гарантирует чётность: на провод уходит
    /// половина градусов, нечётные значения передать точно нельзя.
    static let angleStep: Double = 10
    static let angleRange: ClosedRange<Double> = 90...2700

    private let queue = DispatchQueue(label: "house.moza.serial")
    /// Доступ только с `queue`.
    private var device: MozaDevice?
    private let hid = MozaHIDInput()
    private var hidTimer: Timer?
    private var telemetryTimer: Timer?
    private var started = false

    // MARK: - Жизненный цикл

    func start() {
        guard !started else { return }
        started = true

        startHID()
        connect()

        hidTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.refreshSteering()
        }
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshTelemetry()
        }
    }

    func stop() {
        hidTimer?.invalidate()
        telemetryTimer?.invalidate()
        hid.stop()
        queue.async { [self] in
            device?.close()
            device = nil
        }
    }

    // MARK: - Подключение и чтение

    func connect() {
        isBusy = true
        statusText = "Поиск базы…"

        queue.async { [weak self] in
            guard let self else { return }

            self.device?.close()
            self.device = nil

            do {
                let device = try MozaDevice.discover()
                device.writesEnabled = true
                self.device = device

                let angle = try device.read("max-angle").humanValue
                let ffb = try device.read("ffb-strength").humanValue
                let torque = try device.read("torque").humanValue
                let temperatures = self.readTemperatures(device)
                let model = device.portInfo.productID
                    .map { MozaDiscovery.modelName(productID: $0) } ?? "MOZA"
                let port = device.portInfo.calloutPath

                self.publish {
                    self.isBusy = false
                    self.isConnected = true
                    self.modelName = model
                    self.statusText = "подключена · \(port)"
                    self.angle = Double(angle)
                    self.ffbStrength = Double(ffb)
                    self.torque = Double(torque)
                    self.temperatures = temperatures
                    self.message = nil
                }
            } catch {
                let text = "\(error)"
                self.device?.close()
                self.device = nil
                self.publish {
                    self.isBusy = false
                    self.isConnected = false
                    self.statusText = "База не найдена"
                    self.message = text
                }
            }
        }
    }

    /// Вызывается только с `queue`.
    private func readTemperatures(_ device: MozaDevice) -> [Temperature] {
        let wanted = [
            ("Двигатель", "motor-temp"),
            ("Транзисторы", "mosfet-temp"),
            ("Контроллер", "mcu-temp"),
        ]
        return wanted.compactMap { label, name in
            guard let command = MozaSettings.command(named: name),
                  let result = try? device.read(command) else { return nil }
            return Temperature(label: label, value: command.humanText(fromWire: result.wireValue))
        }
    }

    private func refreshTelemetry() {
        guard isConnected, !isBusy else { return }
        queue.async { [weak self] in
            guard let self, let device = self.device else { return }
            let temperatures = self.readTemperatures(device)
            self.publish { self.temperatures = temperatures }
        }
    }

    // MARK: - Запись

    /// Угол пишется парой `limit` + `max-angle` — только тогда база применяет предел.
    func applyAngle() {
        guard isConnected else { return }
        let degrees = Int(angle.rounded())

        isBusy = true
        message = nil

        queue.async { [weak self] in
            guard let self, let device = self.device else { return }

            do {
                _ = try device.setRotationAngle(degrees: degrees)
                let applied = try device.rotationAngle().maxAngle
                let text = applied == degrees
                    ? "Угол поворота: \(applied)°"
                    : "База вернула \(applied)° вместо \(degrees)°"
                self.publish {
                    self.isBusy = false
                    self.angle = Double(applied)
                    self.message = text
                }
            } catch {
                let text = "\(error)"
                self.publish {
                    self.isBusy = false
                    self.message = text
                }
            }
        }
    }

    func applyFFBStrength() {
        applyScalar(named: "ffb-strength", value: Int(ffbStrength.rounded()), label: "Сила отдачи")
    }

    func applyTorque() {
        applyScalar(named: "torque", value: Int(torque.rounded()), label: "Лимит момента")
    }

    private func applyScalar(named name: String, value: Int, label: String) {
        guard isConnected else { return }

        isBusy = true
        message = nil

        queue.async { [weak self] in
            guard let self, let device = self.device else { return }

            do {
                let result = try device.write(name, human: value)
                let applied = result.readBack?.humanValue ?? value
                let text = result.verified == false
                    ? "\(label): база вернула \(applied) вместо \(value)"
                    : "\(label): \(value) %"
                self.publish {
                    self.isBusy = false
                    if name == "ffb-strength" { self.ffbStrength = Double(applied) }
                    if name == "torque" { self.torque = Double(applied) }
                    self.message = text
                }
            } catch {
                let text = "\(error)"
                self.publish {
                    self.isBusy = false
                    self.message = text
                }
            }
        }
    }

    func calibrateCenter() {
        guard isConnected else { return }

        isBusy = true
        message = nil

        queue.async { [weak self] in
            guard let self, let device = self.device else { return }

            let text: String
            do {
                _ = try device.calibrateCenter()
                text = "Команда калибровки отправлена — проверьте центр по индикатору"
            } catch {
                text = "\(error)"
            }
            self.publish {
                self.isBusy = false
                self.message = text
            }
        }
    }

    // MARK: - HID

    private func startHID() {
        // Подписка вешается на run loop текущего потока, поэтому только с главного.
        do {
            try hid.start()
        } catch {
            message = "Ввод недоступен: \(error)"
        }
    }

    private func refreshSteering() {
        guard let steering = hid.steering() else {
            steeringDegrees = nil
            return
        }
        steeringDegrees = steering.normalized * angle / 2
    }

    private func publish(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
