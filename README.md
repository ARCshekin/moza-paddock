# MOZA Paddock for macOS

Нативный менеджер Assetto Corsa и драйверный мост MOZA R5 для macOS. SwiftUI, Swift, C и Python; без kext.

## Возможности

- Выбор машины, скина, трассы, конфигурации, сетапа и режима заезда.
- Назначение кнопок, живые оси MOZA R5, угол поворота и сила FFB.
- Пресеты, история сессий и рекорды отдельно для каждой конфигурации.
- Установка автомобилей и трасс из ZIP/7z/RAR или папок с резервными копиями.
- Отдельное окно игры на внешнем мониторе во весь экран.

Доступны CrossOver и независимая бесплатная среда Wine с отдельным prefix. Установка Wine и перенос Steam доступны на вкладке «Запуск»; [устройство и ограничения](docs/standalone-runtime.md). На M3 Pro проверены вход в Steam, загрузка Mercedes GT3 / Spa, окно 1920×1080 на внешнем экране и передача ввода/FFB через мост R5. Пользователь подтвердил изображение, руль, педали, лепестки и отдачу. Совместимость других машин/модов проверяется отдельно. Нужна купленная Windows-версия Assetto Corsa в Steam. Игра, Steam, Wine и пользовательские данные в репозиторий не входят.

## Быстрый старт

Требования: Apple Silicon Mac, macOS 13+, Command Line Tools, Homebrew LLVM/LLD для Windows-моста; MOZA R5 для управления.

```sh
brew install llvm lld
./Scripts/build-ac-bridge.sh
./Scripts/make-paddock-app.sh
open build/MozaPaddock.app
```

На этой стадии приложение использует исходный checkout: не перемещайте его после сборки `.app`. Установка и ограничения описаны в [installation](docs/installation.md).

## Разделы проекта

| Каталог | Назначение |
| --- | --- |
| `Sources/Paddock/App`, `Views` | SwiftUI приложение и экраны |
| `Sources/Paddock/Models`, `Services` | Конфигурации, библиотека, запуск и хранение |
| `Sources/MozaKit` | Serial/HID, протокол MOZA, FFB и shared memory |
| `Sources/MozaACBridge` | Нативный процесс игрового моста |
| `Bridge` | Win64 DirectInput DLL и запуск на внешнем мониторе |
| `Scripts` | Сборка, моды, проверки и инструменты запуска |
| `Tests` | Проверки протокола и моста |
| `docs` | Архитектура, установка, разработка и протокол |

[Архитектура](docs/architecture.md) · [Разработка](docs/development.md) · [Протокол MOZA](docs/moza-protocol.md) · [CrossOver](docs/legacy-crossover.md)

## Проверки без игры и оборудования

```sh
swift build -c release
.build/release/MozaPaddock --self-test --without-game
python3 Scripts/check-paddock-mods.py
python3 Scripts/check-runtime.py
./Scripts/check-ac-bridge.sh
```

`--self-test` без `--without-game` также проверяет установленную библиотеку. Проверки выше не отправляют команды мотору и не меняют игровые настройки.

## Работа с Git

Новые возможности — через `feat/<name>` от `main`, исправления — через `fix/<name>`. Коммиты: `<type>(<part>): <description>`, например `feat(runtime): add standalone Wine provider`. Включить локальную проверку: `git config core.hooksPath .githooks`. Подробности в [CONTRIBUTING](CONTRIBUTING.md).

## Данные и лицензия

Пресеты и история: `~/Library/Application Support/MozaPaddock/paddock.json`. Игровые настройки: `~/Documents/Assetto Corsa`. Резервные копии модов — `ModBackups` в папке данных приложения. Эти файлы и Steam-учётные данные не публикуются.

MIT для кода проекта; сторонние компоненты имеют собственные лицензии. См. [LICENSE](LICENSE), [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md) и лицензию моста в `Bridge`.


### Alpine и CSP через Metal

Для Alpine A525 проверен отдельный профиль: WineSikarugir10.0_6 + DXMT 0.80 + CSP 0.2.11. Пользователь подтвердил стабильные 60 FPS на Interlagos с пятью AI при 1920×1080. Обычный запуск Audi сохранён отдельно.

После подготовки профиля запуск: `./Scripts/play-alpine.command`. На настроенном компьютере ему соответствует ярлык `Alpine Metal.command` на рабочем столе. Это отдельный запуск; обычная кнопка Paddock пока не переключается на CSP автоматически. Подготовка и ограничения описаны в [CSP trial](docs/csp-trial.md).
