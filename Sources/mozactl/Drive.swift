import Foundation
import MozaKit

// Мост: телеметрия игры → расчёт силы → база.
//
// Игра отдаёт телеметрию всего ~30 раз в секунду, и если подавать силу с той же
// частотой, руль получает её ступеньками — именно это и ощущается как «грубая»
// отдача. Поэтому подача вынесена в отдельный контур с намного большей частотой:
// он сглаживает силу между пакетами, а не ждёт следующего.

/// Общее состояние между приёмом телеметрии и контуром подачи.
private final class BridgeState {
    private let lock = NSLock()
    private var target: Double = 0
    private var lastFrame: MozaTelemetryFrame?
    private var packets = 0

    func update(target value: Double, frame: MozaTelemetryFrame) {
        lock.lock(); defer { lock.unlock() }
        target = value
        lastFrame = frame
        packets += 1
    }

    func read() -> (target: Double, frame: MozaTelemetryFrame?, packets: Int) {
        lock.lock(); defer { lock.unlock() }
        return (target, lastFrame, packets)
    }
}

func runDrive(_ operands: [String], verbose: Bool) {
    func number(_ flag: String, default value: Double) -> Double {
        guard let position = operands.firstIndex(of: flag),
              position + 1 < operands.count,
              let parsed = Double(operands[position + 1]) else { return value }
        return parsed
    }

    let dryRun = operands.contains("--dry-run")
    let replayPath = operands.firstIndex(of: "--replay").flatMap { position -> String? in
        position + 1 < operands.count ? operands[position + 1] : nil
    }

    // Частота контура подачи и время сглаживания между пакетами телеметрии.
    let rate = max(30, min(1000, number("--rate", default: 400)))
    let tau = max(1, number("--tau", default: 18)) / 1000   // секунды

    var gains = MozaForceModel.Gains()
    gains.master = number("--master", default: gains.master)
    gains.selfAligning = number("--sat", default: gains.selfAligning)
    gains.centering = number("--centering", default: gains.centering)
    gains.bumps = number("--bumps", default: gains.bumps)
    gains.speedRamp = number("--speed-ramp", default: gains.speedRamp)
    // Сглаживание внутри модели больше не нужно: между пакетами сглаживает
    // контур подачи, а фильтр на 30 Гц только добавлял задержку.
    gains.smoothing = number("--smoothing", default: 0)
    var model = MozaForceModel(gains: gains)

    var output: MozaForceOutput?
    var pid: MozaPID?
    if !dryRun {
        let device = MozaPID(verbose: verbose)
        do {
            try device.open()
            let force = MozaForceOutput(pid: device)
            force.deviceGain = Int(number("--gain", default: 255))
            try force.begin()
            output = force
            pid = device
        } catch {
            fail("\(error)")
        }
    }

    let state = BridgeState()
    var forces: [Double] = []
    var steers: [Double] = []
    var standstillForce = 0
    var peak = 0.0
    let statsLock = NSLock()

    func onFrame(_ frame: MozaTelemetryFrame) {
        let force = model.force(for: frame)
        state.update(target: force.total, frame: frame)

        statsLock.lock()
        forces.append(force.total)
        steers.append(Double(frame.steer))
        peak = max(peak, abs(force.total))
        if frame.speed < 1, abs(force.total) > 0.05 { standstillForce += 1 }
        statsLock.unlock()
    }

    // --- Контур подачи: работает на своей частоте, не дожидаясь пакетов ---
    var current = 0.0
    var updates = 0
    let started = Date()
    var running = true

    let loop = Thread {
        let interval = 1.0 / rate
        let alpha = 1 - exp(-interval / tau)
        var deadline = Date().timeIntervalSinceReferenceDate

        while running {
            let (target, _, _) = state.read()
            // Экспоненциальное приближение к цели: сила идёт плавно, а не
            // прыжками по приходу пакета.
            current += (target - current) * alpha
            if let output { try? output.apply(current) }
            updates += 1

            deadline += interval
            let now = Date().timeIntervalSinceReferenceDate
            if deadline > now {
                Thread.sleep(forTimeInterval: deadline - now)
            } else {
                deadline = now   // не копим отставание
            }
        }
    }
    loop.name = "moza.force"
    loop.stackSize = 512 * 1024

    let finish: () -> Void = {
        running = false
        output?.end()
        pid?.close()

        let elapsed = max(Date().timeIntervalSince(started), 0.001)
        print("")
        print("")
        statsLock.lock()
        let count = forces.count
        print("Телеметрия: \(count) пакетов, \(String(format: "%.0f", Double(count) / elapsed)) в секунду")
        print("Подача силы: \(updates) обновлений, "
            + "\(String(format: "%.0f", Double(updates) / elapsed)) в секунду")
        if let output {
            print("  из них отправлено на базу: величина \(output.magnitudeUpdates), "
                + "параметры эффекта \(output.effectUpdates)")
        }

        if count > 50 {
            let magnitudes = forces.map { abs($0) }.sorted()
            func percentile(_ share: Double) -> Double {
                magnitudes[min(magnitudes.count - 1, Int(Double(magnitudes.count) * share))]
            }
            let clipped = magnitudes.filter { $0 >= 0.99 }.count
            let total = Double(count)
            let meanForce = forces.reduce(0, +) / total
            let meanSteer = steers.reduce(0, +) / total
            let covariance = zip(forces, steers).map { ($0 - meanForce) * ($1 - meanSteer) }.reduce(0, +)
            let spreadForce = forces.map { pow($0 - meanForce, 2) }.reduce(0, +).squareRoot()
            let spreadSteer = steers.map { pow($0 - meanSteer, 2) }.reduce(0, +).squareRoot()
            let correlation = (spreadForce > 0 && spreadSteer > 0)
                ? covariance / (spreadForce * spreadSteer) : 0

            print("")
            print("Сила: медиана \(String(format: "%.2f", percentile(0.5))), "
                + "90-й процентиль \(String(format: "%.2f", percentile(0.9))), "
                + "99-й \(String(format: "%.2f", percentile(0.99))), "
                + "максимум \(String(format: "%.2f", peak))")
            print("Упирается в предел: \(clipped) из \(count) "
                + "(\(String(format: "%.1f", Double(clipped) * 100 / total)) %)")
            print("Связь с рулём: r = \(String(format: "%+.2f", correlation)) "
                + (correlation < -0.3 ? "— сила возвращает руль к центру"
                                      : "— ВНИМАНИЕ: сила не возвращает руль"))
            print("Сила на стоящей машине: \(standstillForce) кадров")
        }
        statsLock.unlock()
    }
    signal(SIGINT) { _ in print(""); exit(0) }
    atexit_b { finish() }

    print(dryRun
        ? "Сухой прогон: сила считается и сглаживается, но на руль не подаётся."
        : "Мост запущен. Ctrl-C для выхода.")
    print("Контур подачи: \(Int(rate)) Гц, сглаживание \(Int(tau * 1000)) мс.")
    print("Коэффициенты: общий \(gains.master), возврат \(gains.selfAligning), "
        + "пружина \(gains.centering), кочки \(gains.bumps).")
    print("")

    loop.start()

    if let replayPath {
        replay(path: replayPath, realTime: !operands.contains("--fast"), handle: onFrame)
        return
    }

    let receiver = MozaTelemetryReceiver()
    do {
        try receiver.start { frame in onFrame(frame) }
    } catch {
        fail("\(error)")
    }

    // Строка состояния.
    while true {
        Thread.sleep(forTimeInterval: 0.2)
        let (target, frame, _) = state.read()
        guard let frame else {
            print("\rожидание телеметрии… (начните заезд)   ", terminator: "")
            fflush(stdout)
            continue
        }

        let width = 21
        let middle = width / 2
        var bar = Array(repeating: Character("·"), count: width)
        bar[middle] = "|"
        let position = middle + Int((current * Double(middle)).rounded())
        bar[max(0, min(width - 1, position))] = "#"

        print(String(format: "\r%5.1f км/ч  руль %+5.2f  бок. G %+5.2f   сила %+5.2f %@  ",
                     Double(frame.speedKmh), Double(frame.steer),
                     Double(frame.gForceLateral), target, String(bar)),
              terminator: "")
        fflush(stdout)
    }
}

/// Прогон записи заезда: пакеты идут с теми же интервалами, что и в жизни.
private func replay(path: String, realTime: Bool, handle: (MozaTelemetryFrame) -> Void) {
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("не удалось прочитать \(path)")
    }
    print("Прогон записи: \(path)")

    var offset = 0
    var previousTimestamp: Double?
    let bytes = [UInt8](data)

    while offset + 12 <= bytes.count {
        var timestamp: Double = 0
        var length: UInt32 = 0
        withUnsafeMutableBytes(of: &timestamp) { target in
            for byte in 0..<8 { target[byte] = bytes[offset + byte] }
        }
        withUnsafeMutableBytes(of: &length) { target in
            for byte in 0..<4 { target[byte] = bytes[offset + 8 + byte] }
        }
        offset += 12
        let size = Int(length)
        guard offset + size <= bytes.count, size % 4 == 0 else { break }

        var values = [Float](repeating: 0, count: size / 4)
        for index in 0..<(size / 4) {
            var bits: UInt32 = 0
            for byte in 0..<4 {
                bits |= UInt32(bytes[offset + index * 4 + byte]) << (8 * UInt32(byte))
            }
            values[index] = Float(bitPattern: bits)
        }
        offset += size

        if realTime, let previous = previousTimestamp {
            let wait = timestamp - previous
            if wait > 0, wait < 1 { Thread.sleep(forTimeInterval: wait) }
        }
        previousTimestamp = timestamp

        if let frame = MozaTelemetryFrame(values) { handle(frame) }
    }
}
