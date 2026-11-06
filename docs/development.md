# Разработка

Установите Command Line Tools, Swift и Homebrew `llvm lld`. Сборка приложения: `./Scripts/make-paddock-app.sh`; мост: `./Scripts/build-ac-bridge.sh`.

## Ветки и коммиты

```sh
git switch main
git pull --ff-only
git switch -c feat/example
git config core.hooksPath .githooks
```

Формат: `<type>(<part>): <description>`. Типы: feat, fix, refactor, docs, test, build, ci, chore, perf, revert. Части: app, runtime, core, bridge, mods, records, docs, repo, ci. Делайте логические коммиты и PR; сохраняйте историю веток. Исходная работа импортирована одним честным baseline-коммитом, без выдуманной прошлой истории.

## Проверки

```sh
swift build -c release
.build/release/MozaPaddock --self-test --without-game
python3 Scripts/check-paddock-mods.py
python3 Scripts/check-runtime.py
./Scripts/check-ac-bridge.sh
```

CI на macOS выполняет эти проверки и проверяет заголовки коммитов. Игра, Steam, MOZA и вход в аккаунт в CI не требуются. Для CLT без XCTest bridge-check использует адаптер assertions. Не выдавайте офлайн-проверки за проверку в реальной игре.

Аппаратная проверка — отдельная ручная сессия. Не запускайте моторные тесты из CI. Для runtime фиксируйте версию Wine, способ рендеринга, запуск Steam и реальный результат игры.
