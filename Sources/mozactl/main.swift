import Foundation
import MozaKit

let usage = """
mozactl — конфигурация базы руля MOZA на macOS

Чтение (ничего не меняет):
  mozactl selftest            офлайн-проверка кадрирования протокола (железо не нужно)
  mozactl list                найти базу: serial-порт и HID-интерфейс
  mozactl get --all           прочитать все доступные настройки и телеметрию
  mozactl get <настройка>     прочитать одну настройку
  mozactl settings            показать таблицу известных команд
  mozactl monitor [сек]       живые оси и кнопки через HID
  mozactl serve [порт]        веб-интерфейс на localhost (по умолчанию 8765)
  mozactl telemetry [порт]    приём UDP-телеметрии игры (по умолчанию 20777)
  mozactl drive --dry-run     расчёт силы из телеметрии без подачи на руль
  mozactl drive               мост: телеметрия игры → отдача на руле
  mozactl bind                лепестки переключают рабочие столы
  mozactl ffb-probe           видит ли macOS отдачу этой базы (силу не подаёт)
  mozactl ffb-test            прямой импульс отдачи через HID PID
  mozactl ffb-sweep           перебор трактовок PID, если отдача молчит

Запись (требует --yes):
  mozactl angle               показать текущий угол поворота руля
  mozactl angle <градусы>     задать угол поворота (90…2700, чётное)
  mozactl ffb [<проценты>]    общая сила отдачи (0…100)
  mozactl torque [<проценты>] аппаратный лимит момента (50…100)
  mozactl calibrate           калибровка центра руля

Флаги:
  -v, --verbose               печатать hex отправленных и принятых кадров
  -y, --yes                   разрешить запись в базу

Настройки: \(MozaSettings.readable.map(\.name).joined(separator: ", "))
"""

func pad(_ text: String, _ width: Int) -> String {
    let length = text.count
    return length >= width ? text : text + String(repeating: " ", count: width - length)
}

func fail(_ message: String) -> Never {
    fflush(stdout)   // чтобы уже напечатанное не оказалось после сообщения об ошибке
    FileHandle.standardError.write(Data("Ошибка: \(message)\n".utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
let verbose = arguments.contains { $0 == "-v" || $0 == "--verbose" }
let allowWrites = arguments.contains { $0 == "-y" || $0 == "--yes" }
arguments.removeAll { ["-v", "--verbose", "-y", "--yes"].contains($0) }

guard let subcommand = arguments.first else {
    print(usage)
    exit(0)
}
let operands = Array(arguments.dropFirst())

func connect() -> MozaDevice {
    do {
        let device = try MozaDevice.discover(verbose: verbose)
        device.writesEnabled = allowWrites
        return device
    } catch {
        fail("\(error)")
    }
}

// MARK: - Чтение

func describe(_ result: MozaReadResult) -> String {
    let command = result.command
    var line = pad(command.name, 16)
        + pad("\(result.wireValue)", 11)
        + pad(command.humanText(fromWire: result.wireValue), 11)

    switch result.checksumMatches {
    case .some(true): line += "checksum ✓"
    case .some(false): line += "checksum ✗"
    case .none: line += "checksum отсутствует"
    }

    if let range = command.humanRange, !range.contains(result.humanValue) {
        line += "  ⚠︎ вне ожидаемого диапазона \(range.lowerBound)…\(range.upperBound)"
    }
    if result.attempts > 1 {
        line += "  (со \(result.attempts)-й попытки)"
    }
    return line
}

let tableHeader = pad("настройка", 16) + pad("на проводе", 11) + pad("значение", 11) + "проверка"

func runSelfTest() {
    let checks = MozaSelfTest.run()
    for check in checks {
        print("\(check.passed ? "✓" : "✗")  \(pad(check.name, 42)) \(check.detail)")
    }
    print("")

    let failed = checks.filter { !$0.passed }
    if failed.isEmpty {
        print("Все проверки пройдены (\(checks.count)). Кадрирование совпадает с эталонными байтами.")
    } else {
        print("Не пройдено: \(failed.count) из \(checks.count).")
        exit(1)
    }
}

func runList() {
    let ports = MozaDiscovery.mozaSerialPorts()
    let hidDevices = MozaDiscovery.mozaHIDDevices()

    if ports.isEmpty && hidDevices.isEmpty {
        fail("устройств MOZA не найдено (искали VID 0x\(String(format: "%04X", MozaDiscovery.vendorID)))")
    }

    print("Serial-порты (канал настроек):")
    if ports.isEmpty { print("  — не найдено") }
    for port in ports {
        print("  \(pad(port.calloutPath, 28))\(port.productName ?? "?")")
        if let vid = port.vendorID, let pid = port.productID {
            print("  \(pad("", 28))VID 0x\(String(format: "%04X", vid)), PID 0x\(String(format: "%04X", pid)) — \(MozaDiscovery.modelName(productID: pid))")
        }
    }

    print("")
    print("HID-интерфейсы (оси и кнопки, обслуживаются macOS штатно):")
    if hidDevices.isEmpty { print("  — не найдено") }
    for device in hidDevices {
        let usageText = "usage page \(device.primaryUsagePage.map(String.init) ?? "?")"
            + " / usage \(device.primaryUsage.map(String.init) ?? "?")"
        let joystick = (device.primaryUsagePage == 1 && device.primaryUsage == 4) ? " (джойстик)" : ""
        print("  \(pad(device.productName ?? "?", 28))\(usageText)\(joystick), transport \(device.transport ?? "?")")
    }
}

func runSettings() {
    print(pad("настройка", 16) + pad("чтение", 8) + pad("запись", 8) + pad("id", 8)
        + pad("байт", 6) + pad("масштаб", 9) + "примечание")
    for command in MozaSettings.all {
        let scale = command.isScaled ? "×\(command.scaleNumerator)/\(command.scaleDenominator)" : "1:1"
        print(pad(command.name, 16)
            + pad(command.readGroup.map { "\($0)" } ?? "—", 8)
            + pad(command.writeGroup.map { "\($0)" } ?? "—", 8)
            + pad(command.id.map(String.init).joined(separator: ","), 8)
            + pad("\(command.byteCount)", 6)
            + pad(scale, 9)
            + command.note)
    }
}

func runGet(_ operands: [String]) {
    let device = connect()
    defer { device.close() }

    print("Порт: \(device.portInfo.calloutPath)")
    if let pid = device.portInfo.productID {
        print("Модель: \(MozaDiscovery.modelName(productID: pid))")
    }
    print("")
    print(tableHeader)

    let names = operands.filter { $0 != "--all" }
    if names.isEmpty {
        var failures = 0
        for entry in device.readAll() {
            switch entry.result {
            case let .success(result):
                print(describe(result))
            case let .failure(error):
                failures += 1
                print("\(pad(entry.command.name, 16))— \(error)")
            }
        }
        if failures > 0 {
            print("")
            print("Не удалось прочитать: \(failures) из \(MozaSettings.readable.count).")
        }
    } else {
        for name in names {
            do { print(describe(try device.read(name))) } catch { fail("\(error)") }
        }
    }
}

// MARK: - Запись

func report(_ result: MozaWriteResult) {
    let command = result.command
    var line = "  \(pad(command.name, 16))→ \(pad(command.humanText(fromWire: result.requestedWire), 10))"
    line += "(на проводе \(result.requestedWire))  "

    switch result.verified {
    case .some(true):
        line += "✓ подтверждено чтением"
    case .some(false):
        let actual = result.readBack.map { command.humanText(fromWire: $0.wireValue) } ?? "?"
        line += "✗ база вернула \(actual)"
    case .none:
        line += "проверить чтением нельзя (команда только на запись)"
    }
    print(line)
}

func requireWrites(_ what: String) {
    guard allowWrites else {
        fail("\(what) изменяет настройки базы. Повторите с флагом --yes, если согласны.")
    }
}

func runAngle(_ operands: [String]) {
    let device = connect()
    defer { device.close() }

    guard let argument = operands.first else {
        do {
            let current = try device.rotationAngle()
            print("Угол поворота руля: \(current.maxAngle)°"
                + (current.limit == current.maxAngle ? "" : "  ⚠︎ limit = \(current.limit)°, значения расходятся"))
        } catch { fail("\(error)") }
        return
    }

    guard let degrees = Int(argument) else {
        fail("«\(argument)» — не число градусов")
    }
    requireWrites("Установка угла поворота")

    do {
        let before = try device.rotationAngle()
        print("Было: \(before.maxAngle)°")
        for result in try device.setRotationAngle(degrees: degrees) {
            report(result)
        }
        let after = try device.rotationAngle()
        print("Стало: \(after.maxAngle)°")
        if after.maxAngle != degrees {
            fail("база не приняла значение: осталось \(after.maxAngle)°")
        }
        print("")
        print("Проверьте физически: mozactl monitor — ось руля должна доходить до края")
        print("шкалы примерно на ±\(degrees / 2)°.")
    } catch { fail("\(error)") }
}

func runScalar(_ name: String, label: String, operands: [String]) {
    let device = connect()
    defer { device.close() }

    guard let command = MozaSettings.command(named: name) else {
        fail("неизвестная команда «\(name)»")
    }

    guard let argument = operands.first else {
        do {
            let result = try device.read(command)
            print("\(label): \(command.humanText(fromWire: result.wireValue))")
        } catch { fail("\(error)") }
        return
    }

    guard let value = Int(argument) else {
        fail("«\(argument)» — не число")
    }
    requireWrites("Изменение «\(label)»")

    do {
        let before = try device.read(command)
        print("Было: \(command.humanText(fromWire: before.wireValue))")
        report(try device.write(command, human: value))
    } catch { fail("\(error)") }
}

func runCalibrate() {
    requireWrites("Калибровка центра")

    let device = connect()
    defer { device.close() }

    print("Калибровка центра руля.")
    print("Убедитесь, что руль физически стоит ровно по центру, и не трогайте его.")

    do {
        report(try device.calibrateCenter())
        print("")
        print("Команда отправлена. Ответа на неё протокол не предполагает, поэтому")
        print("результат проверяется физически: mozactl monitor — в центральном положении")
        print("ось руля должна показывать примерно середину шкалы.")
    } catch { fail("\(error)") }
}

// MARK: - Диагностика отдачи

func runForceFeedbackProbe() {
    let probes = MozaForceFeedback.probe()
    guard !probes.isEmpty else {
        fail("HID-интерфейс MOZA не найден")
    }

    for probe in probes {
        print("Устройство: \(probe.productName ?? "?")"
            + " (usage page \(probe.primaryUsagePage.map(String.init) ?? "?")"
            + " / usage \(probe.primaryUsage.map(String.init) ?? "?"))")
        print("  FFIsForceFeedback: \(MozaForceFeedback.describe(status: probe.isForceFeedbackStatus))")

        if let create = probe.createStatus {
            print("  FFCreateDevice:    \(MozaForceFeedback.describe(status: create))")
        }
        if let axes = probe.axisCount {
            print("  осей отдачи:       \(axes)")
        }
        if !probe.supportedEffects.isEmpty {
            print("  эффекты:           \(probe.supportedEffects.joined(separator: ", "))")
        }
        if !probe.emulatedEffects.isEmpty {
            print("  эмулируются:       \(probe.emulatedEffects.joined(separator: ", "))")
        }
        print("")
    }

    if probes.allSatisfy({ !$0.supported }) {
        print("Подсистема Force Feedback macOS не берётся управлять этой базой.")
        print("Значит игра не сможет получить отдачу через штатный путь macOS,")
        print("даже если сама её поддерживает.")
    }
}

// MARK: - Прямая проверка отдачи через HID PID

func runForceFeedbackTest(_ operands: [String]) {
    func number(_ flag: String, default defaultValue: Int) -> Int {
        guard let position = operands.firstIndex(of: flag),
              position + 1 < operands.count,
              let value = Int(operands[position + 1]) else { return defaultValue }
        return value
    }

    let percent = min(max(number("--magnitude", default: 10), 1), 25)
    let milliseconds = min(max(number("--ms", default: 600), 50), 2000)
    let gain = min(max(number("--gain", default: 128), 1), 255)
    let magnitude = MozaPID.magnitudeMax * percent / 100

    let pid = MozaPID(verbose: verbose)
    do {
        try pid.open()
    } catch {
        fail("\(error)")
    }
    defer { pid.close() }

    // Связь с PID-блоком проверяем до всякой силы: если база отвечает на
    // feature-репорт, значит канал живой.
    do {
        let pool = try pid.pool()
        var line = "PID-блок отвечает: память эффектов \(pool.ramPoolSize) байт, "
            + "одновременных эффектов \(pool.simultaneousEffects)"
        if let power = pool.actuatorPower {
            line += ", питание привода: \(power ? "включено" : "выключено")"
        }
        print(line)
    } catch {
        print("Не удалось прочитать PID Pool: \(error)")
        print("Это уже плохой знак, но продолжаю — запись репортов может работать.")
    }

    // Ось руля читаем сами — тогда результат теста не зависит от того,
    // смотрит ли кто-то на руль.
    let input = MozaHIDInput()
    try? input.start()
    defer { input.stop() }

    func sampleSteering(seconds: Double) -> [Int] {
        var samples: [Int] = []
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, true)
            if let value = input.steering()?.value { samples.append(value) }
        }
        return samples
    }

    // Освобождаем блоки, оставшиеся от прерванных сеансов.
    pid.freeAllEffects()

    print("")
    print("Два импульса по \(milliseconds) мс: сначала влево, затем вправо.")
    print("Сила \(percent) % (величина \(magnitude) из \(MozaPID.magnitudeMax)), усиление \(gain)/255.")
    print("Руль можно не держать — я измерю его ось сам.")
    print("")

    var effectIndex: UInt8?
    defer {
        if let index = effectIndex {
            try? pid.stopEffect(index: index)
            try? pid.freeEffect(index: index)
        }
        try? pid.disableActuators()
        print("Приводы выключены.")
    }

    do {
        let baseline = sampleSteering(seconds: 0.4)
        guard let start = baseline.last else {
            print("Ось руля не читается — измерить смещение не смогу.")
            return
        }
        print("Исходное положение оси: \(start)")

        func printState(_ label: String) {
            guard let state = try? pid.state() else {
                print("  состояние \(label): прочитать не удалось")
                return
            }
            print("  состояние \(label): приводы \(state.actuatorsEnabled ? "ВКЛ" : "выкл")"
                + ", пауза \(state.devicePaused ? "да" : "нет")"
                + ", защита \(state.safetySwitch ? "да" : "нет")"
                + ", эффект играет \(state.effectPlaying ? "ДА" : "нет")"
                + ", блок \(state.effectIndex)")
        }

        printState("до включения")
        try pid.reset()
        try pid.setDeviceGain(gain)
        printState("после включения")

        let index = try pid.createEffect(.constantForce)
        effectIndex = index
        print("Блок эффекта: индекс \(index)")
        try pid.setEffect(index: index, type: .constantForce, durationMilliseconds: milliseconds)

        var maximumShift = 0
        // При включённом Direction Enable сторону задаёт поле направления,
        // а не знак величины. Проверено на железе: 270° крутит ось в плюс
        // (вправо), 90° — в минус (влево).
        for (label, direction) in [("вправо", 27000), ("влево", 9000)] {
            // Замеряем от положения непосредственно перед импульсом, иначе
            // сдвиг от предыдущего импульса засчитается второй раз.
            let before = input.steering()?.value ?? start

            try pid.setEffect(index: index, type: .constantForce,
                              durationMilliseconds: milliseconds,
                              directionCentiDegrees: direction)
            try pid.setConstantForce(index: index, magnitude: magnitude)
            try pid.startEffect(index: index)

            let samples = sampleSteering(seconds: Double(milliseconds) / 1000)
            try pid.stopEffect(index: index)

            let shift = samples.map { $0 - before }.max(by: { abs($0) < abs($1) }) ?? 0
            maximumShift = max(maximumShift, abs(shift))
            print("  импульс \(label) (направление \(direction / 100)°): "
                + "смещение оси \(shift > 0 ? "+" : "")\(shift)")

            _ = sampleSteering(seconds: 0.6)   // пауза между импульсами
        }

        print("")
        // Шум покоя у этой базы — единицы; сотни единиц это уже реальное движение.
        if maximumShift >= 200 {
            print("Руль ФИЗИЧЕСКИ двигался: максимальное смещение \(maximumShift) единиц оси.")
            print("Значит свой force feedback работает, и дальше это вопрос расчёта силы.")
        } else {
            print("Ось почти не изменилась (максимум \(maximumShift) единиц) — момента не было")
            print("либо руль был чем-то удержан. Повторить сильнее: --magnitude 25 --gain 255.")
        }
    } catch {
        fail("\(error)")
    }
}

// MARK: - Монитор HID

func runMonitor(_ operands: [String]) {
    let seconds = operands.first.flatMap(Double.init) ?? 30
    var maxAngle: Int?
    var productID: Int?

    // Угол нужен, чтобы перевести положение оси в градусы; без него просто не показываем.
    if let info = MozaDiscovery.mozaSerialPorts().first {
        productID = info.productID
        let device = MozaDevice(portInfo: info, verbose: false)
        if let _ = try? device.open() {
            maxAngle = try? device.rotationAngle().maxAngle
            device.close()
        }
    }

    let input = MozaHIDInput()
    do {
        try input.start(productID: productID)
    } catch { fail("\(error)") }
    defer { input.stop() }

    print("Монитор HID (\(Int(seconds)) с, Ctrl-C для выхода)."
        + (maxAngle.map { " Угол поворота: \($0)°." } ?? ""))
    print("Поверните руль и нажмите кнопки — значения обновляются ниже.")
    print("")

    let deadline = Date().addingTimeInterval(seconds)
    let interactive = isatty(fileno(stdout)) != 0
    var lastLineLength = 0
    var lastLine = ""

    while Date() < deadline {
        CFRunLoopRunInMode(.defaultMode, 0.1, true)

        var parts: [String] = []
        if let steering = input.steering() {
            var text = "руль \(pad("\(steering.value)", 6))"
            if let maxAngle {
                let degrees = steering.normalized * Double(maxAngle) / 2
                text += String(format: "(%+7.1f°)", degrees)
            }
            parts.append(text)
        }
        for axis in input.axes() where axis.usage != UInt32(kHIDUsage_GD_X) {
            parts.append("\(axis.name) \(axis.value)")
        }
        let buttons = input.buttons()
        if !buttons.isEmpty {
            parts.append("кнопки: " + buttons.map(String.init).joined(separator: ","))
        }

        let line = parts.isEmpty
            ? "ожидание событий… (пошевелите рулём)"
            : parts.joined(separator: "   ")

        if interactive {
            // Живая строка на месте: дополняем пробелами, чтобы стереть остаток прошлой.
            var painted = line
            if painted.count < lastLineLength {
                painted += String(repeating: " ", count: lastLineLength - painted.count)
            }
            lastLineLength = painted.count
            FileHandle.standardOutput.write(Data(("\r" + painted).utf8))
        } else if line != lastLine {
            // В файл или конвейер — только изменения, отдельными строками.
            print(line)
            lastLine = line
        }
    }

    print("")
    if input.receivedEvents() == 0 {
        print("Событий не получено. Если руль точно шевелился, проверьте разрешение в")
        print("«Системные настройки → Конфиденциальность и безопасность → Мониторинг ввода».")
    } else {
        print("Получено событий: \(input.receivedEvents()).")
    }
}

// MARK: -

switch subcommand {
case "selftest": runSelfTest()
case "list": runList()
case "settings": runSettings()
case "get": runGet(operands)
case "angle": runAngle(operands)
case "ffb": runScalar("ffb-strength", label: "Сила отдачи", operands: operands)
case "torque": runScalar("torque", label: "Лимит момента", operands: operands)
case "calibrate": runCalibrate()
case "monitor": runMonitor(operands)
case "ffb-probe": runForceFeedbackProbe()
case "ffb-test": runForceFeedbackTest(operands)
case "bind": runBind(operands, verbose: verbose)
case "drive": runDrive(operands, verbose: verbose)
case "telemetry":
    runTelemetry(port: UInt16(operands.first.flatMap(Int.init) ?? 20777),
                 dumpAll: operands.contains("--all"))
case "serve":
    runWebServer(port: UInt16(operands.first.flatMap(Int.init) ?? 8765), verbose: verbose)
case "ffb-rate": runForceRateTest(verbose: verbose)
case "ffb-sign": runForceSignTest(verbose: verbose)
case "ffb-sweep":
    runForceFeedbackSweep(verbose: verbose, magnitudePercent: 12, deviceGain: 160, milliseconds: 500)
case "help", "-h", "--help": print(usage)
default: fail("неизвестная команда «\(subcommand)». Запустите mozactl help.")
}
