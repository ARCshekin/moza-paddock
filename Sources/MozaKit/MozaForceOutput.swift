import Foundation

/// Непрерывная подача силы на базу через HID PID.
///
/// Сторону силы база берёт только из поля направления (знак величины она
/// игнорирует — проверено), поэтому при смене знака пересылается Set Effect.
/// Величина же обновляется коротким Set Constant Force, его можно шлём часто.
///
/// Эффект намеренно имеет конечную длительность и продлевается на ходу: если
/// процесс умрёт, сила пропадёт сама в течение секунды, а не останется на валу.
public final class MozaForceOutput {
    /// Направление в сотых долях градуса. Проверено на железе: 270° крутит ось
    /// в плюс (вправо), 90° — в минус (влево).
    private static let directionRight = 27000
    private static let directionLeft = 9000

    private let durationMilliseconds: Int
    private let refreshInterval: TimeInterval

    private let pid: MozaPID
    private var index: UInt8?
    private var lastRight: Bool?
    private var lastRefresh = Date.distantPast
    private var lastMagnitude = -1

    public var deviceGain: Int = 255

    /// Порог смены стороны. У нуля знак силы дребезжит, а смена стороны стоит
    /// пересылки 22-байтового Set Effect — без порога он летел бы сотни раз в
    /// секунду на ровной дороге.
    public var directionHysteresis: Double = 0.02

    /// Сколько раз отправлена величина и сколько раз — параметры эффекта.
    /// Нужно, чтобы видеть настоящую частоту подачи, а не расчётную.
    public private(set) var magnitudeUpdates = 0
    public private(set) var effectUpdates = 0

    public init(pid: MozaPID, durationMilliseconds: Int = 1000) {
        self.pid = pid
        self.durationMilliseconds = max(50, min(1000, durationMilliseconds))
        self.refreshInterval = Double(self.durationMilliseconds) / 3000
    }

    public func begin() throws {
        try pid.reset()
        try pid.setDeviceGain(deviceGain)
        pid.freeAllEffects()
        index = try pid.createEffect(.constantForce)
        lastRight = nil
        lastRefresh = .distantPast
        lastMagnitude = -1
    }

    /// Задать силу: −1 (полностью влево) … +1 (полностью вправо).
    public func apply(_ force: Double) throws {
        guard let index else { return }

        let clamped = force.isFinite ? max(-1, min(1, force)) : 0
        let magnitude = Int((abs(clamped) * Double(MozaPID.magnitudeMax)).rounded())

        // Сторону меняем только при уверенном переходе, иначе держим прежнюю.
        let right: Bool
        if let lastRight {
            if lastRight && clamped < -directionHysteresis { right = false }
            else if !lastRight && clamped > directionHysteresis { right = true }
            else { right = lastRight }
        } else {
            right = clamped >= 0
        }

        // Upload magnitude before Start (the order used by hid-pidff). Starting
        // with a zero/old magnitude can trigger the firmware's force ramp again.
        let restart = lastRight != right || Date().timeIntervalSince(lastRefresh) > refreshInterval
        if restart {
            // Do not momentarily apply the old magnitude in a new direction.
            if lastRight != nil && lastRight != right {
                try pid.setConstantForce(index: index, magnitude: 0)
                lastMagnitude = 0
            }
            try pid.setEffect(
                index: index,
                type: .constantForce,
                durationMilliseconds: durationMilliseconds,
                directionEnable: true,
                directionCentiDegrees: right ? MozaForceOutput.directionRight : MozaForceOutput.directionLeft
            )
            lastRight = right
            effectUpdates += 1
        }

        // Незачем гонять по шине одно и то же значение.
        if magnitude != lastMagnitude {
            try pid.setConstantForce(index: index, magnitude: magnitude)
            lastMagnitude = magnitude
            magnitudeUpdates += 1
        }
        if restart {
            try pid.startEffect(index: index)
            lastRefresh = Date()
        }
    }

    public func end() {
        if let index {
            try? pid.stopEffect(index: index)
            try? pid.freeEffect(index: index)
        }
        try? pid.disableActuators()
        index = nil
    }
}
