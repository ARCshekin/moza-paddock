import Foundation
import MozaKit

// Лепестки передач переключают рабочие столы macOS.
//
//   лепесток 13 → стол влево
//   лепесток 14 → стол вправо
//
// Почему не через нажатие Ctrl+← / Ctrl+→, как было бы очевидно: эти сочетания
// обрабатывает WindowServer, и синтетические события он для них игнорирует —
// проверено на этой машине обоими способами (CGEvent и System Events). Событие
// доходит до активного приложения как обычная стрелка, но стол не меняется.
// Поэтому стол переключается напрямую через SkyLight — тем же путём, каким это
// делают Hammerspoon и подобные утилиты.
//
// Это приватный интерфейс системы: он может измениться в новой версии macOS.

private typealias ConnectionID = Int32

private struct SkyLight {
    let connection: ConnectionID
    let copySpaces: @convention(c) (ConnectionID) -> CFArray?
    let setCurrentSpace: @convention(c) (ConnectionID, CFString, UInt64) -> Void
    let activeSpace: @convention(c) (ConnectionID) -> UInt64

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainSymbol = dlsym(handle, "CGSMainConnectionID"),
              let copySymbol = dlsym(handle, "CGSCopyManagedDisplaySpaces"),
              let setSymbol = dlsym(handle, "CGSManagedDisplaySetCurrentSpace"),
              let activeSymbol = dlsym(handle, "CGSGetActiveSpace") else { return nil }

        let mainConnection = unsafeBitCast(mainSymbol, to: (@convention(c) () -> ConnectionID).self)
        connection = mainConnection()
        copySpaces = unsafeBitCast(copySymbol, to: (@convention(c) (ConnectionID) -> CFArray?).self)
        setCurrentSpace = unsafeBitCast(setSymbol, to: (@convention(c) (ConnectionID, CFString, UInt64) -> Void).self)
        activeSpace = unsafeBitCast(activeSymbol, to: (@convention(c) (ConnectionID) -> UInt64).self)
    }

    /// Переключить стол на мониторе, где сейчас фокус.
    /// Возвращает описание перехода или причину, по которой он не состоялся.
    func switchSpace(left: Bool) -> String {
        let active = activeSpace(connection)
        guard let displays = copySpaces(connection) as? [[String: Any]] else {
            return "не удалось прочитать список столов"
        }

        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let ids = spaces.compactMap { $0["ManagedSpaceID"] as? Int }
            guard let index = ids.firstIndex(of: Int(active)) else { continue }

            let target = left ? index - 1 : index + 1
            guard target >= 0, target < ids.count else {
                // Как и в самой системе, по краям не заворачиваем.
                return "край: \(index + 1) из \(ids.count)"
            }
            setCurrentSpace(connection, identifier as CFString, UInt64(ids[target]))
            return "\(index + 1) → \(target + 1) из \(ids.count)"
        }
        return "активный стол не найден ни на одном мониторе"
    }
}

func runBind(_ operands: [String], verbose: Bool) {
    func integer(_ flag: String) -> Int? {
        guard let position = operands.firstIndex(of: flag),
              position + 1 < operands.count else { return nil }
        return Int(operands[position + 1])
    }

    guard let skyLight = SkyLight() else {
        fail("не удалось получить доступ к переключению столов (SkyLight)")
    }

    // Разовая проверка без руля.
    if operands.contains("--test-left") || operands.contains("--test-right") {
        let left = operands.contains("--test-left")
        print(skyLight.switchSpace(left: left))
        return
    }

    let leftButton = integer("--left") ?? 13
    let rightButton = integer("--right") ?? 14

    let input = MozaHIDInput()
    do { try input.start() } catch { fail("\(error)") }
    defer { input.stop() }

    if operands.contains("--learn") {
        print("Нажимайте кнопки руля — покажу номера. Ctrl-C для выхода.")
        print("")
        var seen = Set<Int>()
        while true {
            CFRunLoopRunInMode(.defaultMode, 0.05, true)
            for button in input.buttons() where !seen.contains(button) {
                seen.insert(button)
                print("кнопка \(button)")
            }
        }
    }

    print("Лепестки переключают рабочие столы.")
    print("  лепесток \(leftButton) → влево      лепесток \(rightButton) → вправо")
    print("Ctrl-C для выхода.")
    print("")

    var pressedBefore = Set<Int>()
    var lastNote = ""

    while true {
        CFRunLoopRunInMode(.defaultMode, 0.02, true)

        let pressed = Set(input.buttons())
        for button in pressed.subtracting(pressedBefore) {
            if button == leftButton {
                lastNote = "влево: " + skyLight.switchSpace(left: true)
            } else if button == rightButton {
                lastNote = "вправо: " + skyLight.switchSpace(left: false)
            }
        }
        pressedBefore = pressed

        print("\r\u{1B}[Kожидание лепестков"
            + (lastNote.isEmpty ? "" : "   последнее — \(lastNote)"),
              terminator: "")
        fflush(stdout)
    }
}
