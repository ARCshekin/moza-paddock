import Foundation
import MozaKit

// Локальный веб-интерфейс: живые оси и кнопки по HID, настройки по serial.
// Сервер слушает только 127.0.0.1 — наружу ничего не открывается.

private struct AxisView: Encodable {
    let name: String
    let usage: Int
    let raw: Int
    let percent: Double
}

private struct TemperatureView: Encodable {
    let label: String
    let value: String
}

private struct Snapshot: Encodable {
    var connected = false
    var model = "MOZA"
    var port = ""
    var angleSetting: Int?
    var ffbStrength: Int?
    var torque: Int?
    var steeringRaw: Int?
    var steeringDegrees: Double?
    var axes: [AxisView] = []
    var temperatures: [TemperatureView] = []
    var actuatorsEnabled: Bool?
    var effectPlaying: Bool?
    var pulsing = false
    var forceFeedbackAvailable = false
    var message: String?
}

private final class Store {
    private let lock = NSLock()
    private var snapshot = Snapshot()

    func read() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    func mutate(_ body: (inout Snapshot) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&snapshot)
    }
}

func runWebServer(port: UInt16, verbose: Bool) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    let buildStamp = formatter.string(from: Date())

    let store = Store()
    // Доступ к базе идёт и из таймера, и из обработчика запросов.
    let deviceLock = NSLock()
    var device: MozaDevice?

    func withDevice<T>(_ body: (MozaDevice) throws -> T) -> Result<T, Error> {
        deviceLock.lock(); defer { deviceLock.unlock() }
        guard let device else { return .failure(MozaDevice.DeviceError.notFound) }
        do { return .success(try body(device)) } catch { return .failure(error) }
    }

    // Подключение к базе.
    do {
        let opened = try MozaDevice.discover(verbose: verbose)
        opened.writesEnabled = true      // кнопки интерфейса — это явное действие человека
        device = opened
        store.mutate {
            $0.connected = true
            $0.port = opened.portInfo.calloutPath
            $0.model = opened.portInfo.productID.map { MozaDiscovery.modelName(productID: $0) } ?? "MOZA"
        }
    } catch {
        store.mutate { $0.message = "База не найдена: \(error)" }
    }

    // Оси и кнопки.
    let input = MozaHIDInput()
    try? input.start()

    // Канал отдачи (HID PID). Его трогают и таймер состояния, и тестовый
    // импульс из интерфейса, поэтому доступ — под замком.
    let pid = MozaPID()
    let pidLock = NSLock()
    let pidReady = (try? pid.open()) != nil
    store.mutate { $0.forceFeedbackAvailable = pidReady }

    func withPID<T>(_ body: (MozaPID) throws -> T) -> Result<T, Error> {
        pidLock.lock(); defer { pidLock.unlock() }
        guard pidReady else { return .failure(MozaPID.PIDError.deviceNotFound) }
        do { return .success(try body(pid)) } catch { return .failure(error) }
    }

    // Тестовый импульс: величина ФИКСИРОВАНА, чтобы разницу давала только
    // настройка силы отдачи на базе — иначе сравнивать было бы нечего.
    let pulseQueue = DispatchQueue(label: "house.moza.pulse")
    let pulseMagnitudePercent = 25
    let pulseHalfMilliseconds = 320

    func startTestPulse() -> Bool {
        var alreadyRunning = false
        store.mutate {
            if $0.pulsing { alreadyRunning = true } else { $0.pulsing = true }
        }
        if alreadyRunning { return false }

        let strength = store.read().ffbStrength
        let magnitude = MozaPID.magnitudeMax * pulseMagnitudePercent / 100

        pulseQueue.async {
            var failure: String?
            let outcome = withPID { pid -> Void in
                try pid.reset()
                try pid.setDeviceGain(255)
                let index = try pid.createEffect(.constantForce)
                defer {
                    try? pid.stopEffect(index: index)
                    try? pid.freeEffect(index: index)
                    try? pid.disableActuators()
                }
                // Рывок в одну сторону и обратно: руль примерно возвращается
                // на место, а толчок отчётливо чувствуется.
                for direction in [27000, 9000] {
                    try pid.setEffect(index: index, type: .constantForce,
                                      durationMilliseconds: pulseHalfMilliseconds,
                                      directionCentiDegrees: direction)
                    try pid.setConstantForce(index: index, magnitude: magnitude)
                    try pid.startEffect(index: index)
                    Thread.sleep(forTimeInterval: Double(pulseHalfMilliseconds) / 1000)
                    try pid.stopEffect(index: index)
                }
            }
            if case let .failure(error) = outcome { failure = "\(error)" }

            store.mutate {
                $0.pulsing = false
                if let failure {
                    $0.message = "Импульс не удался: \(failure)"
                } else {
                    $0.message = "Импульс \(pulseMagnitudePercent) % при силе отдачи "
                        + (strength.map { "\($0) %" } ?? "?")
                }
            }
        }
        return true
    }

    // MARK: Обновление снимка

    func refreshFast() {
        let axes = input.axes()
        let steering = input.steering()
        let angle = store.read().angleSetting ?? 900

        store.mutate { snapshot in
            snapshot.steeringRaw = steering?.value
            snapshot.steeringDegrees = steering.map { $0.normalized * Double(angle) / 2 }
            snapshot.axes = axes.map { axis in
                let span = Double(axis.logicalMax - axis.logicalMin)
                let percent = span > 0 ? Double(axis.value - axis.logicalMin) / span * 100 : 0
                return AxisView(name: axis.name, usage: Int(axis.usage), raw: axis.value, percent: percent)
            }
        }
    }

    func refreshSlow() {
        let angle = withDevice { try $0.read("max-angle").humanValue }
        let ffb = withDevice { try $0.read("ffb-strength").humanValue }
        let torque = withDevice { try $0.read("torque").humanValue }
        let temperatures: [TemperatureView] = [("Двигатель", "motor-temp"), ("Транзисторы", "mosfet-temp"), ("Контроллер", "mcu-temp")]
            .compactMap { label, name in
                guard let command = MozaSettings.command(named: name) else { return nil }
                guard case let .success(wire) = withDevice({ try $0.read(command).wireValue }) else { return nil }
                return TemperatureView(label: label, value: command.humanText(fromWire: wire))
            }
        let state = try? withPID { try $0.state() }.get()

        store.mutate { snapshot in
            if case let .success(value) = angle { snapshot.angleSetting = value }
            if case let .success(value) = ffb { snapshot.ffbStrength = value }
            if case let .success(value) = torque { snapshot.torque = value }
            if !temperatures.isEmpty { snapshot.temperatures = temperatures }
            snapshot.actuatorsEnabled = state?.actuatorsEnabled
            snapshot.effectPlaying = state?.effectPlaying
        }
    }

    // MARK: HTTP

    func handle(method: String, path: String, query: [String: String]) -> (status: String, type: String, body: Data) {
        switch (method, path) {
        case ("GET", "/"):
            // Метка сборки видна внизу страницы: по ней сразу понятно,
            // свежая страница у браузера или он показывает кэш.
            let page = webPage.replacingOccurrences(of: "{{BUILD}}", with: buildStamp)
            return ("200 OK", "text/html; charset=utf-8", Data(page.utf8))

        case ("GET", "/api/state"):
            let encoder = JSONEncoder()
            let data = (try? encoder.encode(store.read())) ?? Data("{}".utf8)
            return ("200 OK", "application/json; charset=utf-8", data)

        case ("POST", "/api/calibrate"):
            let result = withDevice { try $0.calibrateCenter() }
            switch result {
            case .success:
                store.mutate { $0.message = "Калибровка отправлена. Руль должен был стоять ровно." }
                return ("200 OK", "application/json", Data(#"{"ok":true}"#.utf8))
            case let .failure(error):
                store.mutate { $0.message = "Калибровка не удалась: \(error)" }
                return ("500 Internal Server Error", "application/json", Data(#"{"ok":false}"#.utf8))
            }

        case ("POST", "/api/angle"):
            guard let text = query["value"], let degrees = Int(text) else {
                return ("400 Bad Request", "application/json", Data(#"{"ok":false}"#.utf8))
            }
            let result = withDevice { try $0.setRotationAngle(degrees: degrees) }
            switch result {
            case .success:
                store.mutate {
                    $0.angleSetting = degrees
                    $0.message = "Угол поворота: \(degrees)°"
                }
                return ("200 OK", "application/json", Data(#"{"ok":true}"#.utf8))
            case let .failure(error):
                store.mutate { $0.message = "\(error)" }
                return ("500 Internal Server Error", "application/json", Data(#"{"ok":false}"#.utf8))
            }

        case ("POST", "/api/ffb"):
            guard let text = query["value"], let percent = Int(text) else {
                return ("400 Bad Request", "application/json", Data(#"{"ok":false}"#.utf8))
            }
            let result = withDevice { try $0.write("ffb-strength", human: percent) }
            switch result {
            case .success:
                store.mutate {
                    $0.ffbStrength = percent
                    $0.message = "Сила отдачи: \(percent) %"
                }
                return ("200 OK", "application/json", Data(#"{"ok":true}"#.utf8))
            case let .failure(error):
                store.mutate { $0.message = "\(error)" }
                return ("500 Internal Server Error", "application/json", Data(#"{"ok":false}"#.utf8))
            }

        case ("POST", "/api/pulse"):
            // Отвечаем сразу: импульс длится доли секунды в фоне, и держать
            // соединение всё это время нельзя — обработчик один, он бы
            // заблокировал опрос состояния.
            let started = startTestPulse()
            return (started ? "200 OK" : "409 Conflict", "application/json",
                    Data((started ? #"{"ok":true}"# : #"{"ok":false,"busy":true}"#).utf8))

        default:
            return ("404 Not Found", "text/plain; charset=utf-8", Data("не найдено".utf8))
        }
    }

    let listener = socket(AF_INET, SOCK_STREAM, 0)
    guard listener >= 0 else {
        fail("не удалось создать сокет")
    }
    var reuse: Int32 = 1
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")   // только локально

    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard bound == 0 else {
        fail("порт \(port) занят — укажите другой: mozactl serve <порт>")
    }
    guard listen(listener, 16) == 0 else {
        fail("listen не удался")
    }

    DispatchQueue.global().async {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 { continue }

            var raw = [UInt8](repeating: 0, count: 8192)
            let count = recv(client, &raw, raw.count, 0)
            guard count > 0, let request = String(bytes: raw[0..<count], encoding: .utf8) else {
                Darwin.close(client); continue
            }

            let firstLine = request.split(separator: "\r\n", maxSplits: 1).first ?? ""
            let parts = firstLine.split(separator: " ")
            let method = parts.count > 0 ? String(parts[0]) : "GET"
            let target = parts.count > 1 ? String(parts[1]) : "/"

            var path = target
            var query: [String: String] = [:]
            if let mark = target.firstIndex(of: "?") {
                path = String(target[target.startIndex..<mark])
                for pair in target[target.index(after: mark)...].split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1)
                    if kv.count == 2 { query[String(kv[0])] = String(kv[1]) }
                }
            }

            let response = handle(method: method, path: path, query: query)
            var head = "HTTP/1.1 \(response.status)\r\n"
            head += "Content-Type: \(response.type)\r\n"
            head += "Content-Length: \(response.body.count)\r\n"
            head += "Cache-Control: no-store\r\n"
            head += "Connection: close\r\n\r\n"

            var out = Data(head.utf8)
            out.append(response.body)
            out.withUnsafeBytes { buffer in
                _ = Darwin.send(client, buffer.baseAddress, buffer.count, 0)
            }
            Darwin.close(client)
        }
    }

    refreshSlow()
    refreshFast()

    print("Интерфейс: http://127.0.0.1:\(port)")
    print("Ctrl-C для выхода.")

    // Оси обновляем часто, настройки и телеметрию — раз в секунду.
    var tick = 0
    let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
        refreshFast()
        tick += 1
        if tick % 20 == 0 { refreshSlow() }
    }
    RunLoop.main.add(timer, forMode: .default)
    RunLoop.main.run()
}
