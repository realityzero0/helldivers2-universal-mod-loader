import os, sys, struct, hashlib, json, zipfile, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT / "scripts"))
import archive

src_lua = ROOT / "src" / "boot_loader.lua"
lua_bytes = src_lua.read_bytes()
payload = struct.pack('<II', len(lua_bytes), 2) + lua_bytes
boot_id = 0xF476DF93691895FA
bundle = archive.make_archive({boot_id: payload})

patch0 = ROOT / "data" / "9ba626afa44a3aa3.patch_0"
patch0.write_bytes(bundle)
(ROOT / "data" / "9ba626afa44a3aa3.patch_0.gpu_resources").write_bytes(b"")
(ROOT / "data" / "9ba626afa44a3aa3.patch_0.stream").write_bytes(b"")

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()

files_hashes = {
    "data/9ba626afa44a3aa3.patch_0": sha(patch0),
    "data/9ba626afa44a3aa3.patch_0.stream": sha(ROOT / "data" / "9ba626afa44a3aa3.patch_0.stream"),
    "data/9ba626afa44a3aa3.patch_0.gpu_resources": sha(ROOT / "data" / "9ba626afa44a3aa3.patch_0.gpu_resources"),
    "UniversalModLoader-README.txt": sha(ROOT / "UniversalModLoader-README.txt"),
    "thumbnail.png": sha(ROOT / "thumbnail.png")
}

manifest_path = ROOT / "UniversalModLoader-manifest.json"
m = json.loads(manifest_path.read_text(encoding="utf-8"))
m["files"] = files_hashes
manifest_path.write_text(json.dumps(m, indent=2) + "\n", encoding="utf-8")

# Package ZIP
zip_out = Path(r"g:\antigravity\Helldivers2-Universal-Mod-Loader-v22.0.0.zip")
package_files = [
    ("UniversalModLoader-README.txt", ROOT / "UniversalModLoader-README.txt"),
    ("UniversalModLoader-manifest.json", ROOT / "UniversalModLoader-manifest.json"),
    ("manifest.json", ROOT / "manifest.json"),
    ("thumbnail.png", ROOT / "thumbnail.png"),
    ("data/9ba626afa44a3aa3.patch_0", ROOT / "data" / "9ba626afa44a3aa3.patch_0"),
    ("data/9ba626afa44a3aa3.patch_0.gpu_resources", ROOT / "data" / "9ba626afa44a3aa3.patch_0.gpu_resources"),
    ("data/9ba626afa44a3aa3.patch_0.stream", ROOT / "data" / "9ba626afa44a3aa3.patch_0.stream")
]

with zipfile.ZipFile(zip_out, "w", compression=zipfile.ZIP_DEFLATED) as z:
    for arcname, fpath in package_files:
        z.write(fpath, arcname=arcname)

# Also update legacy Helldivers2-Universal-Mod-Loader-v22.zip
shutil.copy2(zip_out, Path(r"g:\antigravity\Helldivers2-Universal-Mod-Loader-v22.zip"))

# Sync release_v22 artifact directory if present
release_v22 = Path(r"C:\Users\drews\.gemini\antigravity\brain\e6c8c351-3fc4-4332-9d71-f1fc99a33eb3\release_v22")
if release_v22.exists():
    shutil.copy2(patch0, release_v22 / "data" / "9ba626afa44a3aa3.patch_0")
    shutil.copy2(ROOT / "UniversalModLoader-manifest.json", release_v22 / "UniversalModLoader-manifest.json")
    shutil.copy2(ROOT / "UniversalModLoader-README.txt", release_v22 / "UniversalModLoader-README.txt")
    print(f"SUCCESS: Synced artifacts in {release_v22}")

# Deploy to active boot loader slot (0xF476DF93691895FA) in Helldivers 2\data without overwriting addon patches
hd2_data = Path(r"S:\SteamLibrary\steamapps\common\Helldivers 2\data")
if hd2_data.exists():
    deployed_slots = []
    for p in sorted(hd2_data.glob("9ba626afa44a3aa3.patch_*")):
        if p.name.endswith(".stream") or p.name.endswith(".gpu_resources"):
            continue
        try:
            raw = p.read_bytes()
            if len(raw) >= 72 and struct.unpack_from("<I", raw, 0)[0] == 0xF0000011:
                ntypes, nentries = struct.unpack_from("<II", raw, 4)
                if nentries == 1 and len(raw) >= 72 + 32 * ntypes + 80:
                    key = struct.unpack_from("<Q", raw, 72 + 32 * ntypes)[0]
                    if key == boot_id:
                        p.write_bytes(bundle)
                        deployed_slots.append(p.name)
        except Exception as e:
            print(f"WARNING: Could not inspect {p}: {e}")
    if deployed_slots:
        print(f"SUCCESS: Deployed UniversalModLoader v22.0.0 to live game boot slot(s): {', '.join(deployed_slots)}")

print(f"SUCCESS: Built {zip_out} ({zip_out.stat().st_size} bytes)")
