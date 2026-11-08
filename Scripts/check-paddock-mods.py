#!/usr/bin/env python3
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import subprocess
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("paddock_mods", Path(__file__).with_name("paddock-mods.py"))
mods = importlib.util.module_from_spec(spec); spec.loader.exec_module(mods)


def rejected(operation):
    try: operation()
    except (ValueError, RuntimeError): return
    raise AssertionError("Unsafe operation was accepted")


with tempfile.TemporaryDirectory(prefix="paddock-mod-tests-") as temporary:
    root = Path(temporary); game = root / "game"; game.mkdir(); (game / "acs.exe").touch()
    store = root / "store"
    archive = root / "car.zip"
    with zipfile.ZipFile(archive, "w") as z:
        z.writestr("wrapper/content/cars/test_car/ui/ui_car.json", '{"name":"Test Car"}')
        z.writestr("wrapper/content/cars/test_car/test.kn5", "new model")
    plan = mods.operate(archive, game, store)
    assert len(plan) == 1 and plan[0]["destination"] == "content/cars/test_car"
    assert not (game / "content").exists()
    mods.operate(archive, game, store, install=True)
    target = game / "content/cars/test_car/test.kn5"
    assert target.read_text() == "new model"
    target.write_text("old model")
    mods.operate(archive, game, store, install=True)
    assert target.read_text() == "new model"
    assert any(p.read_text() == "old model" for p in (store / "ModBackups").rglob("test.kn5"))
    print("PASS inspect, nested package discovery, install, backup")
    target.write_text("keep me")
    copytree = mods.shutil.copytree
    def fail_copy(source, destination, *args, **kwargs):
        if str(destination).startswith(str(game)):
            Path(destination).mkdir(parents=True, exist_ok=True)
            raise RuntimeError("simulated disk failure")
        return copytree(source, destination, *args, **kwargs)
    with patch.object(mods.shutil, "copytree", fail_copy):
        rejected(lambda: mods.operate(archive, game, store, install=True))
    assert target.read_text() == "keep me"
    print("PASS failed installation restores original package")
    dependencies = root / "car-with-dependencies.zip"
    with zipfile.ZipFile(dependencies, "w") as z:
        z.writestr("pack/content/cars/dependency_car/ui/ui_car.json", '{"name":"Dependency car"}')
        z.writestr("pack/content/cars/dependency_car/body.kn5", "model")
        z.writestr("pack/content/fonts/rss-font.txt", "new font")
        z.writestr("pack/apps/lua/RSS_Settings/manifest.ini", "[ABOUT]")
        z.writestr("pack/apps/lua/RSS_Settings/RSS_Settings.lua", "-- fixture")
    fonts = game / "content/fonts"; fonts.mkdir(parents=True, exist_ok=True)
    (fonts / "unrelated.txt").write_text("keep unrelated")
    (fonts / "rss-font.txt").write_text("old font")
    plan = mods.operate(dependencies, game, store)
    assert {x["kind"] for x in plan} == {"cars", "fonts", "apps"}
    mods.operate(dependencies, game, store, install=True)
    assert (fonts / "rss-font.txt").read_text() == "new font"
    assert (fonts / "unrelated.txt").read_text() == "keep unrelated"
    assert (game / "apps/lua/RSS_Settings/RSS_Settings.lua").is_file()
    (fonts / "rss-font.txt").write_text("keep font on rollback")
    copy2 = mods.shutil.copy2
    def fail_font(source, destination, *args, **kwargs):
        if Path(destination) == fonts / "rss-font.txt": raise RuntimeError("simulated font failure")
        return copy2(source, destination, *args, **kwargs)
    with patch.object(mods.shutil, "copy2", fail_font):
        rejected(lambda: mods.operate(dependencies, game, store, install=True))
    assert (fonts / "rss-font.txt").read_text() == "keep font on rollback"
    assert (fonts / "unrelated.txt").read_text() == "keep unrelated"
    print("PASS car dependencies include scoped fonts/Lua apps, preserve other fonts and roll back files")
    malicious = root / "bad.zip"
    with zipfile.ZipFile(malicious, "w") as z: z.writestr("../escape", "bad")
    rejected(lambda: mods.operate(malicious, game, store, install=True))
    assert not (root / "escape").exists()
    print("PASS ZIP traversal rejected")
    symlink = root / "link.zip"
    with zipfile.ZipFile(symlink, "w") as z:
        entry = zipfile.ZipInfo("link"); entry.create_system = 3; entry.external_attr = (0o120777 << 16)
        z.writestr(entry, "/tmp")
    rejected(lambda: mods.operate(symlink, game, store))
    print("PASS ZIP symlink rejected")
    tar = root / "track.tar"
    with tarfile.open(tar, "w") as z:
        for name, content in [("track/ui/ui_track.json", b'{"name":"Test Track"}'), ("track/models.ini", b"[MODEL_0]")]:
            info = tarfile.TarInfo(name); info.size = len(content); z.addfile(info, io.BytesIO(content))
    result = mods.operate(tar, game, store)
    assert result[0]["kind"] == "tracks"
    print("PASS libarchive extraction and track discovery")
    bsdtar = Path("/opt/homebrew/opt/libarchive/bin/bsdtar")
    if bsdtar.exists():
        package = root / "seven-source/test_seven"
        (package / "ui").mkdir(parents=True)
        (package / "ui/ui_car.json").write_text('{"name":"7z Test"}')
        (package / "body.kn5").write_text("test model")
        seven = root / "car.7z"
        subprocess.run([str(bsdtar), "--format", "7zip", "-cf", str(seven), "-C", str(package.parent), package.name], check=True)
        assert mods.operate(seven, game, store)[0]["id"] == "test_seven"
        print("PASS real 7z archive extraction")
    source = root / "folder"; source.mkdir(); (source / "link").symlink_to(game, target_is_directory=True)
    rejected(lambda: mods.operate(source, game, store))
    print("PASS folder symlink rejected")
print("All mod checks passed; user library unchanged.")
