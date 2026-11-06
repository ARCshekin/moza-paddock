import Foundation

/// Последовательный порт через POSIX termios.
///
/// Открываем именно `/dev/cu.*`, а не `/dev/tty.*`: на macOS `tty.*` при открытии
/// блокируется в ожидании сигнала DCD, которого у CDC-ACM устройства нет.
public final class SerialPort {
    public enum PortError: Error, CustomStringConvertible {
        case openFailed(path: String, errno: Int32)
        case configureFailed(call: String, errno: Int32)
        case writeFailed(errno: Int32)
        case readFailed(errno: Int32)
        case notOpen

        public var description: String {
            switch self {
            case let .openFailed(path, code):
                return "не удалось открыть \(path): \(String(cString: strerror(code))) (errno \(code))"
            case let .configureFailed(call, code):
                return "\(call) не удался: \(String(cString: strerror(code))) (errno \(code))"
            case let .writeFailed(code):
                return "запись в порт не удалась: \(String(cString: strerror(code)))"
            case let .readFailed(code):
                return "чтение из порта не удалось: \(String(cString: strerror(code)))"
            case .notOpen:
                return "порт не открыт"
            }
        }
    }

    public let path: String
    public let baudRate: speed_t
    private var fd: Int32 = -1

    public var isOpen: Bool { fd >= 0 }

    public init(path: String, baudRate: speed_t = 115_200) {
        self.path = path
        self.baudRate = baudRate
    }

    deinit { closePort() }

    public func openPort() throws {
        guard fd < 0 else { return }

        // O_NONBLOCK: не ждём DCD при открытии; дальше читаем через poll(2).
        // TIOCEXCL специально не ставим — boxflat тоже открывает порт неисключительно,
        // чтобы не конфликтовать с другими читателями.
        let descriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw PortError.openFailed(path: path, errno: errno)
        }

        var settings = termios()
        guard tcgetattr(descriptor, &settings) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw PortError.configureFailed(call: "tcgetattr", errno: code)
        }

        cfmakeraw(&settings)

        // 8N1, без управления потоком, приёмник включён, модемные линии игнорируем.
        let crtscts: tcflag_t = 0x0003_0000   // CCTS_OFLOW | CRTS_IFLOW
        settings.c_cflag |= tcflag_t(CLOCAL) | tcflag_t(CREAD)
        settings.c_cflag &= ~crtscts
        settings.c_cflag &= ~tcflag_t(PARENB)
        settings.c_cflag &= ~tcflag_t(CSTOPB)
        settings.c_cflag = (settings.c_cflag & ~tcflag_t(CSIZE)) | tcflag_t(CS8)
        settings.c_iflag &= ~(tcflag_t(IXON) | tcflag_t(IXOFF) | tcflag_t(IXANY))

        // Полностью неблокирующее чтение: ожиданием управляет poll(2).
        settings.c_cc.16 = 0   // VMIN
        settings.c_cc.17 = 0   // VTIME

        cfsetispeed(&settings, baudRate)
        cfsetospeed(&settings, baudRate)

        guard tcsetattr(descriptor, TCSANOW, &settings) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw PortError.configureFailed(call: "tcsetattr", errno: code)
        }

        fd = descriptor
    }

    public func closePort() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    /// Выбросить всё, что накопилось во входном и выходном буферах.
    public func flush() {
        guard fd >= 0 else { return }
        tcflush(fd, TCIOFLUSH)
    }

    public func write(_ bytes: [UInt8]) throws {
        guard fd >= 0 else { throw PortError.notOpen }

        var offset = 0
        while offset < bytes.count {
            let written: Int = bytes.withUnsafeBytes { raw -> Int in
                Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
            }
            if written < 0 {
                let code = errno
                if code == EINTR { continue }
                if code == EAGAIN {
                    _ = waitFor(events: Int16(POLLOUT), timeoutMs: 200)
                    continue
                }
                throw PortError.writeFailed(errno: code)
            }
            offset += written
        }
        tcdrain(fd)
    }

    /// Прочитать то, что уже пришло, ожидая появления данных не дольше `timeoutMs`.
    /// Пустой массив означает «за отведённое время ничего не пришло».
    public func readAvailable(timeoutMs: Int) throws -> [UInt8] {
        guard fd >= 0 else { throw PortError.notOpen }

        guard waitFor(events: Int16(POLLIN), timeoutMs: timeoutMs) else { return [] }

        var buffer = [UInt8](repeating: 0, count: 256)
        let count: Int = buffer.withUnsafeMutableBytes { raw -> Int in
            Darwin.read(fd, raw.baseAddress!, raw.count)
        }
        if count < 0 {
            let code = errno
            if code == EAGAIN || code == EINTR { return [] }
            throw PortError.readFailed(errno: code)
        }
        return Array(buffer[0..<count])
    }

    private func waitFor(events: Int16, timeoutMs: Int) -> Bool {
        var descriptor = pollfd(fd: fd, events: events, revents: 0)
        let result = poll(&descriptor, 1, Int32(timeoutMs))
        return result > 0 && (descriptor.revents & events) != 0
    }
}
