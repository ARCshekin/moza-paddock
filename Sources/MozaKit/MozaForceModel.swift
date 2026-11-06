import Foundation

/// Расчёт силы отдачи из телеметрии.
///
/// Игра не отдаёт момент на руле напрямую — только физику машины. Поэтому силу
/// приходится собирать из осмысленных составляющих, каждая со своим
/// коэффициентом, чтобы её можно было настроить по ощущениям.
public struct MozaForceModel {
    public struct Gains {
        /// Возвращающий момент от боковой перегрузки — основа ощущения.
        public var selfAligning: Double = 0.45
        /// Пружина к центру: нужна на малой скорости, где перегрузки почти нет.
        public var centering: Double = 0.06
        /// Кочки и неровности из разницы хода передней подвески.
        public var bumps: Double = 0.22
        /// Скорость, при которой сила выходит на полную величину, м/с.
        public var speedRamp: Double = 12
        /// Предел сцепления: выше него сила перестаёт расти, как у реальной шины.
        public var grip: Double = 1.6
        /// Общий множитель.
        public var master: Double = 1.0
        /// Сглаживание основной составляющей, 0…1 (0 — без сглаживания).
        public var smoothing: Double = 0.35

        public init() {}
    }

    public struct Force {
        /// Итог, −1…1. Знак: плюс — вправо, минус — влево.
        public let total: Double
        public let selfAligning: Double
        public let centering: Double
        public let bumps: Double
        public let speedFactor: Double
    }

    public var gains: Gains
    private var smoothed: Double = 0

    public init(gains: Gains = Gains()) {
        self.gains = gains
    }

    public mutating func reset() {
        smoothed = 0
    }

    public mutating func force(for frame: MozaTelemetryFrame) -> Force {
        let speed = Double(frame.speed)

        // На месте руль не должен ничего изображать: сила нарастает со скоростью.
        let speedFactor = min(speed / max(gains.speedRamp, 0.1), 1)

        // Возвращающий момент. Знак боковой перегрузки в этой игре уже такой,
        // какой нужен: поворот вправо даёт отрицательную перегрузку, то есть
        // сила выходит направленной против поворота (проверено на записи заезда).
        let lateral = Double(frame.gForceLateral)
        // Мягкое насыщение вместо жёсткого обрезания: так шина «сдаётся»
        // постепенно, а не упирается в стену.
        let saturated = tanh(lateral / max(gains.grip, 0.1)) * max(gains.grip, 0.1)
        let selfAligning = saturated * gains.selfAligning * speedFactor

        // Пружина к центру — чтобы на малой скорости руль не был пустым.
        let centering = -Double(frame.steer) * gains.centering * speedFactor

        // Кочки: разница скоростей хода передней подвески даёт толчок в сторону
        // того колеса, которое сейчас грузится сильнее.
        //
        // Обязательно с привязкой к скорости: подвеска дёргается и на месте
        // (машина оседает на старте, её ставят на трассу), а неподвижное колесо
        // трясти нечему — иначе руль живёт своей жизнью на стартовой линии.
        let rollingGate = min(speed / 3, 1)
        let suspensionDifference = Double(frame.suspensionVelocityFrontLeft
            - frame.suspensionVelocityFrontRight)
        let bumps = (suspensionDifference / 2000) * gains.bumps * rollingGate

        // Сглаживаем только плавную часть: толчки должны оставаться резкими,
        // иначе пропадёт вся дорога.
        let smooth = selfAligning + centering
        smoothed = smoothed * gains.smoothing + smooth * (1 - gains.smoothing)

        let total = max(-1, min(1, (smoothed + bumps) * gains.master))

        return Force(
            total: total,
            selfAligning: selfAligning,
            centering: centering,
            bumps: bumps,
            speedFactor: speedFactor
        )
    }
}
