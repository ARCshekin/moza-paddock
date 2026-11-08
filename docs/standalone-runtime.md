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

Проверено на macOS 27.0.1 / Apple M3 Pro: установка из вкладки приложения, создание чистого prefix, независимый APFS-перенос 26 ГБ Assetto Corsa, Wine 11.21, D3D11 feature level 11.0 (`HRESULT=0`), DXVK через bundled MoltenVK и два монитора. Steam прошёл проверку файлов, пользователь вошёл в аккаунт. После установки оригинальных D3DX11/D3DCompiler игра загрузила Mercedes GT3 / Spa. Подтверждены отдельное окно 1920×1080 на внешнем экране, живые оси руля/педалей и два игровых FFB-эффекта с передачей силы в R5 примерно на 177 Гц. Пользователь подтвердил нормальное изображение, работу руля, педалей, лепестков и ощутимую отдачу.

## Чёрное окно Steam

Одного `-cef-disable-gpu` на этом Mac оказалось недостаточно: устройство D3D11 работало, но Steam оставался чёрным. Независимый Steam теперь получает `-cef-disable-gpu -cef-disable-gpu-compositing` и небольшой собственный адаптер CEF.

`Bridge/steam-cef.c` предоставляет интерфейс WinMM, перенаправляя 189 экспортов к оригинальному `moza_winmm.dll`. Оригинал копируется из закреплённого Wine. В браузерном процессе `steamwebhelper.exe` адаптер заменяет только импорт `GetCommandLineW` в EXE и `libcef.dll`, добавляя `--in-process-gpu` и параметры программной отрисовки. Машинный код WinAPI не переписывается. Дочерние процессы с `--type=` и другие программы не получают изменённой командной строки. EXE Steam и CEF остаются оригинальными, поэтому штатная проверка и обновление клиента сохраняются.

Загрузка настраивается в `HKCU/Software/Wine/AppDefaults/steamwebhelper.exe/DllOverrides`, только в независимом prefix. Перед каждым запуском Steam установщик восстанавливает адаптер после возможного `wineboot`. Исходный Wine WinMM сохраняется под отдельным именем. Для отката при закрытой среде есть `runtime.steam_cef.uninstall(runtime)`.

Основание для исследования: [описание межпроцессного представления CEF и October 2026 Steam](https://gist.github.com/cameronwlewis/a0e2a06b026b4e6537dabb6312378b92), [проект с альтернативным single-process обходом](https://github.com/notpop/steam-on-m1-wine). Код адаптера написан в этом проекте; исходники и бинарники этих обходов не включены.

Проверки: ASan/UBSan для синтетической PE-таблицы импортов и ограничения области действия; в реальном Wine — тестовый `steamwebhelper.exe`, дочерний renderer и другая программа. Все прошли, оригинальный `timeGetTime` успешно перенаправляется. Журнал настоящего CEF подтвердил замену двух импортов; отдельный GPU-процесс перестал создаваться. Пользователь подтвердил появление видимого экрана входа после этого изменения. После входа подтверждён запуск игрового заезда.

Дополнительная ручная проверка после подготовки prefix и установки адаптера:

```sh
python3 Scripts/paddock-runtime.py wine --provider standalone -- "Z:$PWD/Bridge/build/cef-check/steamwebhelper.exe" --expect-browser
python3 Scripts/paddock-runtime.py wine --provider standalone -- "Z:$PWD/Bridge/build/cef-check/steamwebhelper.exe" --expect-browser --type=renderer
```

## DirectX для Assetto Corsa

Встроенная Wine `d3dx11_43` не реализует `D3DX11CreateShaderResourceViewFromFileW`; без оригинальной библиотеки игра завершалась при создании первой текстуры. `runtime/directx.py` извлекает `d3dx11_43.dll` и `d3dcompiler_43.dll` x64 из оригинальных June 2010 CAB, которые Steam устанавливает в `Steamworks Shared/_CommonRedist/DirectX/Jun2010` (также поддержан старый каталог внутри игры).

CAB и DLL сверяются с SHA-256 из `directx-manifest.json`; проверяется формат x64 PE. Используется только нужный файл из CAB, без запуска вложенных EXE. CAB и извлечённые DLL остаются локально в `Prerequisites/directx-jun2010`, поэтому после переноса исходный CrossOver можно удалить без потери этих компонентов. Системные DLL CrossOver не копируются. Бинарники Microsoft не включены в репозиторий.

DLL устанавливаются рядом с `acs.exe`, прежние файлы при наличии сохраняются в `Backups/DirectX`. Overrides `native,builtin` задаются только для `acs.exe`. Подготовка prefix устанавливает компоненты из выбранного Steam; перед запуском игры проверяется локальный кеш. При отсутствии оригинальных CAB подготовка объясняет, какой Steam prerequisite нужен.

Источник и условия использования: [Microsoft DirectX End-User Runtimes (June 2010)](https://www.microsoft.com/en-us/download/details.aspx?id=8109). Используются предоставленные с установленной игрой redistributable CAB; это не новый графический backend и не замена DXVK.

## Размер журналов

`MVK_CONFIG_LOG_LEVEL=1` оставляет ошибки MoltenVK и исключает повторяющиеся предупреждения descriptor pool, которые в первой проверке создавали гигабайты текста. [Значения параметра](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Configuration_Parameters.md). После завершения заезда приложение ограничивает `launcher.log`: если он больше 8 МиБ, сохраняет первые 128 КиБ и последние 2 МиБ. Открытый журнал не заменяется; пользовательские пресеты, результаты и файлы игры эта операция не затрагивает.


### Проверка CSP и возврат к штатным машинам

Проверка 8 ноября 2026: CSP 0.2.11 под Wine 11.21 не прошёл инициализацию Alpine A525. Экспериментальный адаптер символов пока не входит в приложение. Рабочая конфигурация Audi восстановлена без CSP: добавленные DLL и конфиги сохранены в локальной резервной копии, Wine `dbghelp.dll` восстановлен из управляемой среды, overrides `dwrite` и `dbghelp` удалены только для `acs.exe`. Audi R8 V10 Plus на Interlagos с пятью AI снова загрузилась, окно размещено на внешнем экране, DirectInput-мост подключён. Установщик CSP остаётся необязательным; совместимость Alpine пока не подтверждена.
