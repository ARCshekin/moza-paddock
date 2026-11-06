// Adapted from crossover-ffb (MIT), see Bridge/LICENSE and Bridge/UPSTREAM.md.
import Foundation

/// Wheel motion in normalized units: position −1 (full left) … +1 (full right).
public struct WheelKinematics: Sendable {
    public var position: Double
    public var velocity: Double     // units per second
    public var acceleration: Double // units per second²
    public init(position: Double = 0, velocity: Double = 0, acceleration: Double = 0) {
        self.position = position; self.velocity = velocity; self.acceleration = acceleration
    }
}

/// Plays DirectInput effects the way a force-feedback device would: tracks start times,
/// durations and envelopes, and evaluates condition effects against live wheel motion.
/// Output is −1…+1 where positive pushes the wheel toward +X (right).
public final class EffectEngine {
    /// Flip constant/ramp/periodic forces, for a game that gets the convention backwards.
    /// Spring/damper/friction/inertia always resist motion regardless.
    public var reverseDirectional = false
    private var started: [Int: (starts: UInt32, at: Double)] = [:]
    public init() {}

    public func reset() { started.removeAll() }

    public func force(_ state: BridgeForceState, wheel: WheelKinematics, now: Double) -> Double {
        var directional = 0.0, resisting = 0.0
        var live = Set<Int>()
        for effect in state.effects where effect.playing {
            live.insert(effect.slot)
            if started[effect.slot]?.starts != effect.starts { started[effect.slot] = (effect.starts, now) }
            guard let begin = started[effect.slot]?.at else { continue }
            let elapsed = (now - begin) * 1_000_000 - Double(effect.startDelayMicros)
            guard elapsed >= 0 else { continue }
            let finite = effect.durationMicros != .max && effect.durationMicros > 0
            let duration = Double(effect.durationMicros)
            if finite, effect.iterations != .max, elapsed >= duration * Double(max(effect.iterations, 1)) { continue }
            let t = finite ? elapsed.truncatingRemainder(dividingBy: duration) : elapsed
            let gain = Double(effect.gain) / 10000
            if effect.kind.isCondition {
                resisting += condition(effect, wheel) * gain
            } else {
                directional += value(effect, t: t, duration: finite ? duration : nil) * gain * xFactor(effect)
            }
        }
        started = started.filter { live.contains($0.key) }
        // DirectInput directions say where a force comes from: a positive force along +X
        // pushes the wheel toward −X. Conditions are already in "resist" form.
        let total = (reverseDirectional ? directional : -directional) - resisting
        return max(-1, min(1, total / 10000 * Double(state.deviceGain) / 10000))
    }

    /// Fraction of the effect's direction vector along the steering axis.
    func xFactor(_ e: BridgeEffect) -> Double {
        let angle = Double(e.direction.0) / 36000 * 2 * .pi
        switch e.coordinates {
        case 0x20: return sin(angle) // polar: 0 = north, 9000 = east (+X)
        case 0x40: return cos(angle) // spherical: angle from +X
        default:
            if e.axisCount <= 1 { return e.direction.0 < 0 ? -1 : 1 }
            let xi = e.xIndex < e.axisCount ? Int(e.xIndex) : 0
            let x = Double(xi == 0 ? e.direction.0 : e.direction.1), y = Double(xi == 0 ? e.direction.1 : e.direction.0)
            let length = (x * x + y * y).squareRoot()
            return length > 0 ? x / length : 0
        }
    }

    private func envelope(_ e: BridgeEffect, _ sustain: Double, t: Double, duration: Double?) -> Double {
        guard e.hasEnvelope else { return sustain }
        if e.attackMicros > 0, t < Double(e.attackMicros) {
            let a = Double(e.attackLevel)
            return a + (sustain - a) * t / Double(e.attackMicros)
        }
        if let duration, e.fadeMicros > 0, t > duration - Double(e.fadeMicros) {
            let f = Double(e.fadeLevel), into = t - (duration - Double(e.fadeMicros))
            return sustain + (f - sustain) * into / Double(e.fadeMicros)
        }
        return sustain
    }

    private func value(_ e: BridgeEffect, t: Double, duration: Double?) -> Double {
        let p = e.params.map(Double.init)
        switch e.kind {
        case .constant:
            return (p[0] < 0 ? -1 : 1) * envelope(e, abs(p[0]), t: t, duration: duration)
        case .ramp:
            let fraction = duration.map { min(1, t / $0) } ?? 0
            let v = p[0] + (p[1] - p[0]) * fraction
            return v * envelope(e, 10000, t: t, duration: duration) / 10000
        default:
            let magnitude = envelope(e, abs(p[0]), t: t, duration: duration)
            let period = max(p[3], 1000)
            var phase = (t.truncatingRemainder(dividingBy: period) / period + p[2] / 36000)
            phase -= phase.rounded(.down)
            let wave: Double
            switch e.kind {
            case .square: wave = phase < 0.5 ? 1 : -1
            case .sine: wave = sin(phase * 2 * .pi)
            case .triangle: wave = phase < 0.25 ? 4 * phase : phase < 0.75 ? 2 - 4 * phase : 4 * phase - 4
            case .sawtoothUp: wave = 2 * phase - 1
            default: wave = 1 - 2 * phase
            }
            return p[1] + magnitude * wave
        }
    }

    /// DirectInput condition: piecewise-linear response to a metric in −10000…10000,
    /// returned in the direction of the metric (the caller subtracts it so it resists).
    private func condition(_ e: BridgeEffect, _ w: WheelKinematics) -> Double {
        let metric: Double
        switch e.kind {
        case .spring: metric = w.position * 10000
        case .damper: metric = w.velocity / 2 * 10000 // full scale ≈ lock-to-lock in one second
        case .inertia: metric = w.acceleration / 40 * 10000
        default: metric = tanh(w.velocity / 0.05) * 10000 // friction
        }
        let p = e.params.map(Double.init)
        let x = max(-10000, min(10000, metric)) - p[0], dead = max(0, p[5])
        var f = 0.0
        if x > dead {
            f = p[1] * (x - dead) / 10000
            let saturation = UInt32(bitPattern: e.params[3]) == 0 ? 10000 : Double(UInt32(bitPattern: e.params[3]))
            f = max(-saturation, min(saturation, f))
        } else if x < -dead {
            f = p[2] * (x + dead) / 10000
            let saturation = UInt32(bitPattern: e.params[4]) == 0 ? 10000 : Double(UInt32(bitPattern: e.params[4]))
            f = max(-saturation, min(saturation, f))
        }
        return f
    }
}

