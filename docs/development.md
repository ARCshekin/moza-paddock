# Разработка

Установите Command Line Tools, Swift и Homebrew `llvm lld`. Сборка приложения: `./Scripts/make-paddock-app.sh`; мост: `./Scripts/build-ac-bridge.sh`.

Обычная сборка `.app` автоматически импортирует сервер из установленной Steam-копии и подготавливает закреплённый Wine. Для разработки без Steam/сетевой установки: `./Scripts/make-paddock-app.sh --without-server`.

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
python3 Scripts/check-server.py
./Scripts/check-ac-bridge.sh
```

CI на macOS выполняет эти проверки и проверяет заголовки авторских коммитов; автоматические merge-коммиты GitHub исключены из этой проверки. При ручном слиянии задавайте заголовок в том же формате, например `gh pr merge --merge --subject "feat(app): merge online browser"`. Игра, Steam, MOZA и вход в аккаунт в CI не требуются. Для CLT без XCTest bridge-check использует адаптер assertions. Не выдавайте офлайн-проверки за проверку в реальной игре.

Аппаратная проверка — отдельная ручная сессия. Не запускайте моторные тесты из CI. Для runtime фиксируйте версию Wine, способ рендеринга, запуск Steam и реальный результат игры.


## Реальный сервер (явная интеграционная проверка)

```sh
.build/release/MozaPaddock --server-live-check
# Дополнительно проверить адрес интерфейса этого Mac:
.build/release/MozaPaddock --server-live-check --server-check-address <LAN-IP>
```

Требуются установленная игра и Wine. Тест запускает реальный Kunos-сервер на 19600 TCP/UDP и 18081 TCP через тот же ServerHost, что и UI, проверяет INFO/JSON, checksum общего surfaces, статус готовности, остановку и повторный запуск. Порты должны быть свободны. Это не офлайн-тест и не входит в CI. Игра, Steam login и аппаратный FFB не запускаются. Тест оставляет журналы в Application Support/MozaPaddock/Servers, завершает свой сервер при выходе и не публикует его в лобби. Проверка LAN-IP с того же Mac не заменяет вход с другого устройства или из интернета.
