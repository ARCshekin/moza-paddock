import Foundation
import MozaKit

/// Можно ли задавать сторону силы знаком величины?
///
/// От этого зависит устройство моста телеметрии: при включённом Direction Enable
/// сторону задаёт поле направления, и на каждую смену знака пришлось бы
/// пересылать 21-байтовый Set Effect. Если же знак величины работает сам, хватит
/// трёхбайтового Set Constant Force на обновление — это заметно проще и быстрее.
func runForceSignTest(verbose: Bool) {
    let pid = MozaPID(verbose: verbose)
    do { try pid.open() } catch { fail("\(error)") }
    defer { pid.close() }

    let input = MozaHIDInput()
    try? input.start()
    defer { input.stop() }

    func pump(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.02, true) }
    }

    let magnitude = MozaPID.magnitudeMax * 12 / 100
    let milliseconds = 500

    print("Проверяю, задаёт ли знак величины сторону силы (Direction Enable выключен).")
    print("Два слабых импульса: +\(magnitude) и −\(magnitude).")
    print("")

    pump(0.4)
    var results: [(String, Int)] = []

    do {
        try pid.reset()
        try pid.setDeviceGain(200)
        let index = try pid.createEffect(.constantForce)
        defer {
            try? pid.stopEffect(index: index)
            try? pid.freeEffect(index: index)
            try? pid.disableActuators()
            print("Приводы выключены.")
        }

        // Направление отключено, но ось X включена — иначе в байте флагов не
        // остаётся ничего и играть эффекту нечем.
        try pid.setEffect(index: index, type: .constantForce,
                          durationMilliseconds: milliseconds,
                          enableAxisX: true,
                          directionEnable: false, directionCentiDegrees: 0)

        for (label, sign) in [("плюс", 1), ("минус", -1)] {
            let before = input.steering()?.value ?? 0
            try pid.setConstantForce(index: index, magnitude: sign * magnitude)
            try pid.startEffect(index: index)

            var extreme = 0
            let deadline = Date().addingTimeInterval(Double(milliseconds) / 1000)
            while Date() < deadline {
                CFRunLoopRunInMode(.defaultMode, 0.02, true)
                if let value = input.steering()?.value {
                    let shift = value - before
                    if abs(shift) > abs(extreme) { extreme = shift }
                }
            }
            try pid.stopEffect(index: index)
            results.append((label, extreme))
            print("  величина \(label): смещение оси \(extreme > 0 ? "+" : "")\(extreme)")
            pump(0.7)
        }
    } catch {
        fail("\(error)")
    }

    print("")
    guard results.count == 2 else { return }
    let (first, second) = (results[0].1, results[1].1)
    let moved = abs(first) > 200 && abs(second) > 200

    if moved && (first > 0) != (second > 0) {
        print("ЗНАК РАБОТАЕТ: плюс и минус развели руль в разные стороны.")
        print("Значит для обновления силы хватит Set Constant Force — три байта на кадр.")
    } else if moved {
        print("Оба импульса ушли в одну сторону: знак игнорируется.")
        print("Сторону придётся задавать полем направления, пересылая Set Effect.")
    } else {
        print("Движения не было — руль удержан или сила слишком мала.")
    }
}
