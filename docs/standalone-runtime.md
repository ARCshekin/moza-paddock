# Независимая среда Wine

Приложение получает отдельный провайдер `standalone`, доступный на вкладке «Запуск». Он использует бесплатный Wine, а не исполняемые файлы или лицензию CrossOver. Steam и купленная игра по-прежнему необходимы.

## Зависимости

Закреплённые URL, версии, лицензии и SHA-256 находятся в `Scripts/runtime/manifest.json`:

- Wine Staging 11.21 — [официальные macOS-пакеты WineHQ от Gcenx](https://github.com/Gcenx/macOS_Wine_builds).
- DXVK macOS 1.10.3-20230507-repack builtin — [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS/releases/tag/v1.10.3-20230507-repack).

Wine включает MoltenVK, Vulkan loader, Mono и Gecko. В собственном скачанном Wine заменяются только builtin `d3d11` и `d3d10core` обеих архитектур, как предусмотрено релизом DXVK. `dxgi` остаётся Wine. В исходники проекта бинарники не включены. Нужна установленная Rosetta для x86_64 Wine на Apple Silicon.

## Папки

В `~/Library/Application Support/MozaPaddock`:

- `Runtimes/wine-11.21` — собственный Wine с DXVK.
- `Downloads` — проверенные установочные архивы.
- `Prefixes/assetto` — отдельная Windows-среда.
- `runtime-setup.log`, `prepare.log`, `Logs` — диагностика установки и графики.

Установщик проверяет хеш до распаковки, проверяет пути и ссылки tar, распаковывает во временную папку и только после успешной проверки публикует runtime. Незавершённая загрузка не становится установленной версией. Существующий prefix/Steam не перезаписывается переносом.

Перенос создаёт APFS-клоны Windows Steam и только Assetto Corsa с её appmanifest. Другие игры, кеши и журналы Steam не копируются. Системные папки Windows и Wine CrossOver не переносятся. Steam-клиент может потребовать повторный вход; проверка лицензии остаётся штатной. Локальные файлы аккаунта никогда не попадают в Git.

Игровые настройки продолжают храниться в macOS Documents/Assetto Corsa. Поэтому пресеты, назначения и текущий выбор не теряются при переключении провайдера.

## CLI

```sh
python3 Scripts/paddock-runtime.py status
python3 Scripts/paddock-runtime.py install
python3 Scripts/paddock-runtime.py prepare --source-steam '/path/to/Windows Steam'
python3 Scripts/paddock-runtime.py wine --provider standalone -- 'C:/Program Files (x86)/Steam/steam.exe'
MOZA_AC_RUNTIME=standalone ./Scripts/play-assetto.command
```

Подготовка не переключает текущую игру на лету. Закройте заезд до смены среды или установки модов. Удаление `Runtimes` не удаляет игру; удаление `Prefixes/assetto` удалит независимую копию Steam/игры и установленные в неё моды.

## Проверки

`python3 Scripts/check-runtime.py` проверяет хеши, архивы, раздельные пути, клонирование и отказ перезаписи на временных фикстурах. Вкладка «Запуск → Проверить графику» запускает небольшой Win64 probe: создание D3D11 hardware device и перечисление мониторов. Он не загружает игру, не входит в Steam и не обращается к рулю.

Проверено на macOS 27.0.1 / Apple M3 Pro: установка из вкладки приложения, создание чистого prefix, независимый APFS-перенос 26 ГБ Assetto Corsa, Wine 11.21, D3D11 feature level 11.0 (`HRESULT=0`), DXVK через bundled MoltenVK и два монитора. Steam прошёл проверку файлов и открыл новую сессию клиента; требуется отдельный вход в аккаунт. Загрузка реального заезда и FFB в этой среде пока не подтверждены.
