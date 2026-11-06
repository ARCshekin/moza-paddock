import Foundation
import MozaKit

/// Перебор трактовок PID-протокола: база принимает все репорты, но не поднимает
/// бит Effect Playing. Здесь по очереди пробуются варианты формирования команд,
/// и для каждого измеряется ось руля и флаг «эффект играет».
///
/// Все импульсы короткие и слабые — задача не «покрутить руль», а найти вариант,
/// на котором прошивка вообще признаёт эффект запущенным.
func runForceFeedbackSweep(verbose: Bool, magnitudePercent: Int, deviceGain: Int, milliseconds: Int) {
    let magnitude = MozaPID.magnitudeMax * magnitudePercent / 100

    /// Один вариант: настраивает эффект и запускает его, возвращая индекс блока.
    struct Variant {
        let name: String
        let run: (MozaPID, Int, Int) throws -> UInt8
    }

    let variants: [Variant] = [
        Variant(name: "базовый (Set Effect → сила → старт)") { pid, magnitude, ms in
            let index = try pid.createEffect(.constantForce)
            try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: ms)
            try pid.setConstantForce(index: index, magnitude: magnitude)
            try pid.sendEffectOperation(index: index, operation: 1, loops: 1)
            return index
        },
        Variant(name: "старт Solo (операция 2)") { pid, magnitude, ms in
            let index = try pid.createEffect(.constantForce)
            try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: ms)
            try pid.setConstantForce(index: index, magnitude: magnitude)
            try pid.sendEffectOperation(index: index, operation: 2, loops: 1)
            return index
        },
        Variant(name: "бесконечная длительность (duration 0)") { pid, magnitude, _ in
            let index = try pid.createEffect(.constantForce)
            try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: 0)
            try pid.setConstantForce(index: index, magnitude: magnitude)
            try pid.sendEffectOperation(index: index, operation: 1, loops: 1)
            return index
        },
        Variant(name: "сила до параметров") { pid, magnitude, ms in
            let index = try pid.createEffect(.constantForce)
            try pid.setConstantForce(index: index, magnitude: magnitude)
            try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: ms)
            try pid.sendEffectOperation(index: index, operation: 1, loops: 1)
            return index
        },
        Variant(name: "без Direction Enable") { pid, magnitude, ms in
            let index = try pid.createEffect(.constantForce)
            try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: ms,
                              directionEnable: false, directionCentiDegrees: 0)
            try pid.setConstantForce(index: index, magnitude: magnitude)
            try pid.sendEffectOperation(index: index, operation: 1, loops: 1)
            return index
        },
        Variant(name: "направление 0° вместо 90°") { pid, magnitude, ms in
            let index = try pid.createEffect(.constantForce)
            try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: ms,
                              directionEnable: true, directionCentiDegrees: 0)
            try pid.setConstantForce(index: index, magnitude: magnitude)
            try pid.sendEffectOperation(index: index, operation: 1, loops: 1)
            return index
        },
        Variant(name: "loop count 255") { pid, magnitude, ms in
            let index = try pid.createEffect(.constantForce)
            try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: ms)
            try pid.setConstantForce(index: index, magnitude: magnitude)
            try pid.sendEffectOperation(index: index, operation: 1, loops: 255)
            return index
        },
        Variant(name: "Device Reset как массив (4), затем базовый") { pid, magnitude, ms in
            try pid.sendDeviceControl(raw: 4, name: "сброс (массив)")
            try pid.setDeviceGain(deviceGain)
            try pid.enableActuators()
            let index = try pid.createEffect(.constantForce)
            try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: ms)
            try pid.setConstantForce(index: index, magnitude: magnitude)
            try pid.sendEffectOperation(index: index, operation: 1, loops: 1)
            return index
        },
        Variant(name: "Device Reset как маска (8), затем базовый") { pid, magnitude, ms in
            try pid.sendDeviceControl(raw: 8, name: "сброс (маска)")
            try pid.setDeviceGain(deviceGain)
            try pid.enableActuators()
            let index = try pid.createEffect(.constantForce)
            try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: ms)
            try pid.setConstantForce(index: index, magnitude: magnitude)
            try pid.sendEffectOperation(index: index, operation: 1, loops: 1)
            return index
        },
        Variant(name: "приводы через маску (0x01) + Continue (0x20)") { pid, magnitude, ms in
            try pid.sendDeviceControl(raw: 0x20, name: "continue (маска)")
            let index = try pid.createEffect(.constantForce)
            try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: ms)
            try pid.setConstantForce(index: index, magnitude: magnitude)
            try pid.sendEffectOperation(index: index, operation: 1, loops: 1)
            return index
        },
    ]

    let pid = MozaPID(verbose: verbose)
    do {
        try pid.open()
    } catch {
        FileHandle.standardError.write(Data("Ошибка: \(error)\n".utf8))
        exit(1)
    }
    defer { pid.close() }

    let input = MozaHIDInput()
    try? input.start()
    defer { input.stop() }

    func pump(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, true)
        }
    }

    print("Перебор вариантов запуска эффекта.")
    print("Сила \(magnitudePercent) % (\(magnitude)), усиление \(deviceGain)/255, импульс \(milliseconds) мс.")
    print("Для каждого варианта смотрю флаг «эффект играет» и смещение оси руля.")
    print("")

    pump(0.4)

    var successes: [String] = []

    for variant in variants {
        pid.freeAllEffects()
        try? pid.setDeviceGain(deviceGain)
        try? pid.enableActuators()
        pump(0.15)

        let start = input.steering()?.value
        var playingSeen = false
        var maximumShift = 0
        var index: UInt8?
        var failure: String?

        do {
            index = try variant.run(pid, magnitude, milliseconds)

            // Пока эффект должен играть, следим за флагом и осью.
            let deadline = Date().addingTimeInterval(Double(milliseconds) / 1000)
            while Date() < deadline {
                CFRunLoopRunInMode(.defaultMode, 0.02, true)
                if let state = try? pid.state(), state.effectPlaying { playingSeen = true }
                if let start, let value = input.steering()?.value {
                    let shift = value - start
                    if abs(shift) > abs(maximumShift) { maximumShift = shift }
                }
            }
        } catch {
            failure = "\(error)"
        }

        if let index {
            try? pid.stopEffect(index: index)
            try? pid.freeEffect(index: index)
        }
        pump(0.35)

        let verdict: String
        if let failure {
            verdict = "ошибка: \(failure)"
        } else if playingSeen {
            verdict = "ЭФФЕКТ ИГРАЕТ, смещение \(maximumShift)"
            successes.append(variant.name)
        } else if abs(maximumShift) >= 200 {
            verdict = "флага нет, но ось сдвинулась на \(maximumShift)"
            successes.append(variant.name)
        } else {
            verdict = "нет (смещение \(maximumShift))"
        }

        print("  \(variant.name): \(verdict)")
    }

    try? pid.disableActuators()
    print("")
    if successes.isEmpty {
        print("Ни один вариант не заставил прошивку признать эффект запущенным.")
        print("Значит дело не в раскладке репортов, а в самом канале или в том,")
        print("что базу нужно отдельно перевести в режим отдачи.")
    } else {
        print("Сработало: \(successes.joined(separator: "; "))")
    }
    print("Приводы выключены.")
}
