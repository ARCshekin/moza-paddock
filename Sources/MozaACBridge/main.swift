import Foundation
import Darwin
import MozaKit

// One native writer, one game process. All HID I/O stays on this thread.
let arguments = Array(CommandLine.arguments.dropFirst())
func option(_ flag: String, fallback: Double) -> Double {
    guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count,
          let number = Double(arguments[i + 1]), number.isFinite else { return fallback }
    return number
}
if arguments.contains("--help") {
    print("moza-ac-bridge [--dry-run] [--gain 0.25] [--reverse] [--seconds N]")
    print("Input and real DirectInput FFB for Assetto Corsa. Gain range 0...1, default 0.25.")
    exit(0)
}
let dryRun = arguments.contains("--dry-run")
let gain = max(0, min(1, option("--gain", fallback: 0.25)))
let duration = max(0, option("--seconds", fallback: 0))
setbuf(stdout, nil)

final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func stop() { lock.lock(); stopped = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

func run() throws {
    let bridge = try SharedBridge()
    let lockFD = open(SharedBridge.defaultPath + ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard lockFD >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { close(lockFD) }
    guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
        throw NSError(domain: "MOZA bridge already running", code: 1)
    }
    let stop = StopFlag()
    var signals: [DispatchSourceSignal] = []
    for number in [SIGINT, SIGTERM, SIGHUP] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { stop.stop() }
        source.resume()
        signals.append(source)
    }
    defer { signals.forEach { $0.cancel() } }
    let input = MozaHIDInput()
    try input.start(productID: 4)
    defer { input.stop() }
    defer { bridge.publish(BridgeInput()) }
    let pid = MozaPID()
    var output: MozaForceOutput?
    defer { output?.end(); pid.close() }
    if !dryRun {
        try pid.open()
        // Finite hardware effect also expires if the process crashes or is killed.
        let force = MozaForceOutput(pid: pid, durationMilliseconds: 1000)
        force.directionHysteresis = 0.002
        output = force
        try force.begin()
        try force.apply(0)
    }
    let engine = EffectEngine()
    engine.reverseDirectional = arguments.contains("--reverse")
    var lastTime = ProcessInfo.processInfo.systemUptime
    let began = lastTime
    var lastPosition = input.steering()?.normalized ?? 0
    var velocity = 0.0, lastVelocity = 0.0
    var lastPrint = 0.0, lastPresenceCheck = 0.0
    var gamePID: UInt32 = 0
    var peak = 0.0, frames = 0
    print("MOZA R5 → Assetto Corsa. \(dryRun ? "DRY RUN, no motor output" : "FFB cap: \(Int(gain * 100))%"), data timeout 250 ms, hardware timeout 1000 ms.")
    print("Shared memory: \(SharedBridge.defaultPath). Stop: Ctrl-C.")
    while !stop.value {
        CFRunLoopRunInMode(.defaultMode, 0.004, false)
        let now = ProcessInfo.processInfo.systemUptime
        if duration > 0 && now - began >= duration { break }
        if now - lastPresenceCheck >= 0.1 {
            guard input.isConnected() else {
                print("R5 disconnected; stopping.")
                break
            }
            lastPresenceCheck = now
        }
        let axes = input.axes()
        func axis(_ usage: UInt32, fallback: UInt32) -> UInt32 {
            guard let value = axes.first(where: { $0.usage == usage }), value.logicalMax > value.logicalMin else { return fallback }
            return UInt32(max(0, min(65535, ((value.normalized + 1) * 32767.5).rounded())))
        }
        var snapshot = BridgeInput()
        snapshot.connected = input.steering() != nil
        snapshot.steering = axis(0x30, fallback: 32768)
        // R5 SR-P Lite: Z accelerator, Rz brake. DLL presents Y and Rz.
        snapshot.throttle = axis(0x32, fallback: 65535)
        snapshot.brake = axis(0x35, fallback: 65535)
        snapshot.clutch = axis(0x36, fallback: 65535)
        for button in input.buttons() where (1...25).contains(button) {
            snapshot.buttons |= 1 << UInt32(button - 1)
        }
        if let hat = axes.first(where: { $0.usage == 0x39 }) {
            let position = hat.value - hat.logicalMin
            snapshot.hat = (0...7).contains(position) ? UInt32(position) : 8
        }
        bridge.publish(snapshot)
        let position = Double(snapshot.steering) / 32767.5 - 1
        let dt = max(0.001, now - lastTime)
        velocity += ((position - lastPosition) / dt - velocity) * min(1, dt / 0.02)
        let acceleration = (velocity - lastVelocity) / dt
        lastTime = now; lastPosition = position; lastVelocity = velocity
        var force = 0.0
        let state = bridge.readForce()
        let stamp = SharedBridge.nowMilliseconds()
        if let state, state.processID != 0, state.heartbeatMilliseconds <= stamp,
           stamp - state.heartbeatMilliseconds < 250, state.acquired,
           !state.paused, !state.actuatorsOff, snapshot.connected {
            if gamePID != state.processID { engine.reset(); gamePID = state.processID }
            force = engine.force(state, wheel: .init(position: position, velocity: velocity, acceleration: acceleration), now: now) * gain
        } else {
            engine.reset()
        }
        // Smooth startup even when attaching to a game already in a corner.
        force *= min(1, max(0, (now - began) / 2))
        if !force.isFinite { force = 0 }
        try output?.apply(force)
        peak = max(peak, abs(force)); frames += 1
        if now - lastPrint >= 1 {
            let effects = state?.effects.filter { $0.playing }.count ?? 0
            print(String(format: "X=%5u gas=%5u brake=%5u buttons=%08x game=%u acquired=%d effects=%d force=%+.3f peak=%.3f rate=%.0fHz",
                         snapshot.steering, snapshot.throttle, snapshot.brake, snapshot.buttons,
                         state?.processID ?? 0, state?.acquired == true ? 1 : 0, effects, force, peak,
                         Double(frames) / max(0.001, now - began)))
            lastPrint = now
        }
    }
    print("Stopped. Motor effects released.")
}
do { try run() } catch {
    fputs("MOZA bridge error: \(error)\n", stderr)
    exit(1)
}
