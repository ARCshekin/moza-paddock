import Foundation
import MozaKit

/// Сколько обновлений величины силы база успевает принять за секунду.
///
/// Эффект намеренно НЕ запускается: репорты уходят, величина меняется, но
/// момента на валу не возникает. Так пропускную способность канала можно
/// измерить, не крутя руль.
func runForceRateTest(verbose: Bool) {
    let pid = MozaPID(verbose: false)
    do { try pid.open() } catch { fail("\(error)") }
    defer { pid.close() }

    print("Измеряю пропускную способность канала отдачи.")
    print("Эффект не запускается — руль двигаться не должен.")
    print("")

    do {
        pid.freeAllEffects()
        let index = try pid.createEffect(.constantForce)
        defer { try? pid.freeEffect(index: index) }

        // Прогрев: первые обращения к устройству всегда медленнее.
        for value in 0..<50 {
            try pid.setConstantForce(index: index, magnitude: value % 2)
        }

        for count in [200, 1000] {
            let started = Date()
            for value in 0..<count {
                try pid.setConstantForce(index: index, magnitude: value % 2)
            }
            let elapsed = Date().timeIntervalSince(started)
            print(String(format: "  %4d обновлений за %.3f с → %.0f в секунду (%.2f мс на репорт)",
                         count, elapsed, Double(count) / elapsed, elapsed * 1000 / Double(count)))
        }

        // Смена стороны стоит дороже: это Set Effect на 22 байта.
        let started = Date()
        for value in 0..<200 {
            try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: 1000,
                              directionCentiDegrees: value % 2 == 0 ? 27000 : 9000)
        }
        let elapsed = Date().timeIntervalSince(started)
        print(String(format: "  смена стороны: %.0f в секунду (%.2f мс на Set Effect)",
                     200 / elapsed, elapsed * 1000 / 200))
    } catch {
        fail("\(error)")
    }
    print("")
    print("Больше этого частоту контура ставить бессмысленно — упрёмся в шину.")
}
