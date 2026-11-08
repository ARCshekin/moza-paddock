#!/usr/bin/env python3
"""Stage and install AC car/track packages; never execute archive contents."""
import argparse
import ctypes as C
import ctypes.util
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import tempfile
import uuid
import zipfile

MAX_FILES = 100_000
MAX_BYTES = 25 * 1024**3


def safe_relative(name):
    name = name.replace("\\", "/")
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or any(":" in part for part in path.parts):
        raise ValueError("Архив содержит небезопасный путь: " + name)
    if not path.parts:
        raise ValueError("Пустой путь в архиве")
    return Path(*path.parts)


def check_tree(root):
    total = count = 0
    for base, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(base) / name
            if path.is_symlink():
                raise ValueError("Символические ссылки в модах не поддерживаются")
            info = path.stat()
            if not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
                raise ValueError("В пакете есть специальный файл")
            total += info.st_size if path.is_file() else 0
            count += 1
            if total > MAX_BYTES or count > MAX_FILES:
                raise ValueError("Пакет превышает лимит 25 ГБ или 100 000 файлов")


def extract_zip(source, destination):
    with zipfile.ZipFile(source) as archive:
        entries = archive.infolist()
        if len(entries) > MAX_FILES or sum(x.file_size for x in entries) > MAX_BYTES:
            raise ValueError("Архив превышает лимит 25 ГБ или 100 000 файлов")
        for item in entries:
            relative = safe_relative(item.filename)
            mode = item.external_attr >> 16
            if stat.S_ISLNK(mode):
                raise ValueError("Символические ссылки в архивах не поддерживаются")
            target = destination / relative
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(item) as src, target.open("wb") as dst:
                    shutil.copyfileobj(src, dst, 1024 * 1024)


def extract_libarchive(source, destination):
    # macOS ships libarchive; it reads 7z and many RAR variants as well as tar.
    name = ctypes.util.find_library("archive")
    if not name:
        raise ValueError("Для этого архива нужен libarchive. Используйте ZIP или папку.")
    lib = C.CDLL(name)
    for function, result, args in [
        ("archive_read_new", C.c_void_p, []),
        ("archive_read_support_format_all", C.c_int, [C.c_void_p]),
        ("archive_read_support_filter_all", C.c_int, [C.c_void_p]),
        ("archive_read_open_filename", C.c_int, [C.c_void_p, C.c_char_p, C.c_size_t]),
        ("archive_read_next_header", C.c_int, [C.c_void_p, C.POINTER(C.c_void_p)]),
        ("archive_entry_pathname", C.c_char_p, [C.c_void_p]),
        ("archive_entry_filetype", C.c_uint, [C.c_void_p]),
        ("archive_entry_size", C.c_longlong, [C.c_void_p]),
        ("archive_entry_hardlink", C.c_char_p, [C.c_void_p]),
        ("archive_read_data", C.c_longlong, [C.c_void_p, C.c_void_p, C.c_size_t]),
        ("archive_error_string", C.c_char_p, [C.c_void_p]),
        ("archive_read_free", C.c_int, [C.c_void_p]),
    ]:
        fn = getattr(lib, function); fn.restype = result; fn.argtypes = args
    handle = lib.archive_read_new()
    try:
        lib.archive_read_support_format_all(handle); lib.archive_read_support_filter_all(handle)
        if lib.archive_read_open_filename(handle, os.fsencode(source), 1024 * 1024) != 0:
            raise ValueError("Не удалось открыть архив. Возможно, он повреждён или зашифрован.")
        entry = C.c_void_p(); count = total = expanded = 0
        buffer = C.create_string_buffer(1024 * 1024)
        while True:
            status = lib.archive_read_next_header(handle, C.byref(entry))
            if status == 1: break
            if status < -20:
                raise ValueError((lib.archive_error_string(handle) or b"Archive error").decode(errors="replace"))
            raw = lib.archive_entry_pathname(entry)
            if not raw: raise ValueError("Пустой путь в архиве")
            relative = safe_relative(os.fsdecode(raw))
            kind = lib.archive_entry_filetype(entry)
            if kind not in (stat.S_IFDIR, stat.S_IFREG) or lib.archive_entry_hardlink(entry):
                raise ValueError("Архив содержит ссылки или специальные файлы")
            count += 1
            total += max(0, lib.archive_entry_size(entry))
            if count > MAX_FILES or total > MAX_BYTES: raise ValueError("Архив слишком большой")
            target = destination / relative
            if kind == stat.S_IFDIR:
                target.mkdir(parents=True, exist_ok=True); continue
            target.parent.mkdir(parents=True, exist_ok=True)
            written = 0
            with target.open("wb") as output:
                while True:
                    n = lib.archive_read_data(handle, buffer, len(buffer))
                    if n == 0: break
                    if n < 0: raise ValueError("Ошибка распаковки архива")
                    written += n; expanded += n
                    if expanded > MAX_BYTES: raise ValueError("Файл слишком большой")
                    output.write(buffer.raw[:n])
    finally:
        lib.archive_read_free(handle)


def discover(root, game):
    candidates = {}
    for name, kind in [("ui_car.json", "cars"), ("ui_track.json", "tracks")]:
        for metadata in root.rglob(name):
            ui = metadata.parent
            while ui != root and ui.name.lower() != "ui": ui = ui.parent
            if ui.name.lower() != "ui": continue
            package = ui.parent
            identity = package.name
            safe_relative(identity)
            if identity.startswith("."): continue
            if not any(package.glob("*.kn5")) and not any(package.glob("models*.ini")):
                continue
            destination = Path("content") / kind / identity
            key = str(destination)
            if key in candidates and candidates[key]["source"] != str(package):
                raise ValueError("В пакете несколько версий одного мода: " + identity)
            candidates[key] = {"id": identity, "kind": kind, "source": str(package),
                               "destination": key, "replaces": (game / destination).exists()}
    if not candidates:
        raise ValueError("Не найдены полноценные автомобили или трассы. Отдельные пакеты скинов, CSP и приложений не поддерживаются.")
    # Dependencies are accepted only beside a recognized content/cars or
    # content/tracks package, never by scanning arbitrary nested directories.
    package_roots = set()
    for item in candidates.values():
        package = Path(item["source"])
        if package.parent.name.lower() in ("cars", "tracks") and package.parent.parent.name.lower() == "content":
            package_roots.add(package.parent.parent.parent)
    for package_root in sorted(package_roots):
        fonts = package_root / "content/fonts"
        if fonts.is_dir():
            for source in sorted(fonts.iterdir()):
                if source.is_file() and source.suffix.lower() in (".png", ".txt", ".ttf", ".otf"):
                    destination = Path("content/fonts") / source.name
                    candidates[str(destination)] = {"id": source.name, "kind": "fonts", "source": str(source),
                        "destination": str(destination), "replaces": (game / destination).exists()}
        apps = package_root / "apps/lua"
        if apps.is_dir():
            for source in sorted(apps.iterdir()):
                if source.is_dir() and (source / "manifest.ini").is_file() and any(source.glob("*.lua")):
                    destination = Path("apps/lua") / source.name
                    candidates[str(destination)] = {"id": source.name, "kind": "apps", "source": str(source),
                        "destination": str(destination), "replaces": (game / destination).exists()}
    return list(candidates.values())


def operate(source, game, store, install=False):
    if not (game / "acs.exe").is_file(): raise ValueError("Папка Assetto Corsa не найдена")
    with tempfile.TemporaryDirectory(prefix="paddock-mod-") as temporary:
        stage = Path(temporary)
        if source.is_dir():
            check_tree(source)
            shutil.copytree(source, stage / source.name)
        elif zipfile.is_zipfile(source):
            extract_zip(source, stage)
        else:
            extract_libarchive(source, stage)
        check_tree(stage)
        items = discover(stage, game)
        if install:
            backup = store / "ModBackups" / str(uuid.uuid4())
            backup.mkdir(parents=True)
            completed = []
            current = None
            try:
                for item in items:
                    target = game / item["destination"]
                    # Reject a pre-existing symlink in any target component.
                    for ancestor in [target, *target.parents]:
                        if ancestor.is_symlink(): raise ValueError("Путь установки содержит ссылку")
                        if ancestor == game: break
                    saved = backup / item["destination"]
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists():
                        saved.parent.mkdir(parents=True, exist_ok=True)
                        shutil.move(str(target), str(saved))
                        current = (target, saved, True)
                    else:
                        current = (target, saved, False)
                    if Path(item["source"]).is_dir(): shutil.copytree(item["source"], target)
                    else: shutil.copy2(item["source"], target)
                    completed.append(current); current = None
            except Exception:
                for target, saved, had_old in ([current] if current else []) + list(reversed(completed)):
                    if target.is_dir(): shutil.rmtree(target)
                    elif target.exists(): target.unlink()
                    if had_old: shutil.move(str(saved), str(target))
                raise
            manifest = {"source": str(source), "items": [{k: v for k, v in x.items() if k != "source"} for x in items]}
            (backup / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
        return [{k: v for k, v in item.items() if k != "source"} for item in items]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["inspect", "install"])
    parser.add_argument("source", type=Path)
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--store", type=Path, required=True)
    args = parser.parse_args()
    try:
        items = operate(args.source, args.game, args.store, args.action == "install")
        print(json.dumps({"items": items}, ensure_ascii=False))
    except Exception as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        raise SystemExit(1)
