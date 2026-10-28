"""Build dist/Mundial_War.rbxlx from src/ following default.project.json (Rojo rules).

  folder with init.server.lua -> Script (children become ModuleScripts inside it)
  folder with init.client.lua -> LocalScript
  folder without init         -> Folder
  *.server.lua / *.client.lua -> Script / LocalScript
  *.lua                       -> ModuleScript

Only the Python standard library is used, so anyone can rebuild the place without Rojo.
"""
from pathlib import Path
import itertools
import json
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist" / "Mundial_War.rbxlx"
_ref = itertools.count(1)


def item(parent, cls, name):
    obj = E.SubElement(parent, "Item", {"class": cls, "referent": f"RBX{next(_ref):08X}"})
    props = E.SubElement(obj, "Properties")
    E.SubElement(props, "string", name="Name").text = name
    return obj, props


def script(parent, cls, name, source):
    obj, props = item(parent, cls, name)
    E.SubElement(props, "ProtectedString", name="Source").text = source
    if cls != "ModuleScript":
        E.SubElement(props, "token", name="RunContext").text = "0"
    return obj


def add_path(parent, path, name):
    path = ROOT / path
    if path.is_file():
        return add_file(parent, path, name)
    init_server, init_client = path / "init.server.lua", path / "init.client.lua"
    if init_server.exists():
        node = script(parent, "Script", name, init_server.read_text(encoding="utf-8"))
    elif init_client.exists():
        node = script(parent, "LocalScript", name, init_client.read_text(encoding="utf-8"))
    else:
        node, _ = item(parent, "Folder", name)
    for child in sorted(path.iterdir()):
        if child.name.startswith("init.") or child.name.startswith("."):
            continue
        if child.is_dir():
            add_path(node, child.relative_to(ROOT), child.name)
        elif child.suffix == ".lua":
            add_file(node, child, None)
    return node


def add_file(parent, file, name):
    stem = file.name[:-4]
    if stem.endswith(".server"):
        return script(parent, "Script", name or stem[:-7], file.read_text(encoding="utf-8"))
    if stem.endswith(".client"):
        return script(parent, "LocalScript", name or stem[:-7], file.read_text(encoding="utf-8"))
    return script(parent, "ModuleScript", name or stem, file.read_text(encoding="utf-8"))


def service(root, cls, props=None):
    obj, p = item(root, cls, cls)
    for key, (kind, value) in (props or {}).items():
        E.SubElement(p, kind, name=key).text = value
    return obj


def main():
    project = json.loads((ROOT / "default.project.json").read_text())["tree"]
    root = E.Element("roblox", version="4")
    E.SubElement(root, "External").text = "null"
    E.SubElement(root, "External").text = "nil"
    service(root, "Workspace", {"StreamingEnabled": ("bool", "false")})
    service(root, "Players", {"CharacterAutoLoads": ("bool", "false")})
    rs = service(root, "ReplicatedStorage")
    add_path(rs, project["ReplicatedStorage"]["MundialWarShared"]["$path"], "MundialWarShared")
    sss = service(root, "ServerScriptService")
    add_path(sss, project["ServerScriptService"]["MundialWar"]["$path"], "MundialWar")
    sp = service(root, "StarterPlayer")
    sps, _ = item(sp, "StarterPlayerScripts", "StarterPlayerScripts")
    add_path(sps, project["StarterPlayer"]["StarterPlayerScripts"]["MundialWar"]["$path"], "MundialWar")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    E.ElementTree(root).write(OUT, encoding="utf-8", xml_declaration=True)

    # verify: every source file made it into the place unchanged
    parsed = E.parse(OUT)
    sources = [n.text for n in parsed.iter("ProtectedString")]
    files = list((ROOT / "src").rglob("*.lua"))
    assert len(sources) == len(files), (len(sources), len(files))
    for f in files:
        assert f.read_text(encoding="utf-8") in sources, f
    print(f"{OUT.relative_to(ROOT)}: {len(files)} scripts, {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
