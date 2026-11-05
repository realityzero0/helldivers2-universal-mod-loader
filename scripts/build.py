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
version = m.get("version", "1.0.1")
m["files"] = files_hashes
manifest_path.write_text(json.dumps(m, indent=2) + "\n", encoding="utf-8")

# Package ZIPs for Arsenal Mod Manager / HD2MM in portable dist/ directory
dist_dir = ROOT / "dist"
dist_dir.mkdir(parents=True, exist_ok=True)

zip_out = dist_dir / f"Helldivers2-Universal-Mod-Loader-v{version}.zip"
zip_latest = dist_dir / "Helldivers2-Universal-Mod-Loader-latest.zip"

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

shutil.copy2(zip_out, zip_latest)

# Optional local copy if g:\antigravity exists
local_work = Path(r"g:\antigravity")
if local_work.exists() and local_work.is_dir():
    try:
        shutil.copy2(zip_out, local_work / f"Helldivers2-Universal-Mod-Loader-v{version}.zip")
        shutil.copy2(zip_out, local_work / "Helldivers2-Universal-Mod-Loader-v1.0.0.zip")
    except Exception:
        pass

# Optional artifact directory copy if present
brain_artifact = Path(r"C:\Users\drews\.gemini\antigravity\brain\e6c8c351-3fc4-4332-9d71-f1fc99a33eb3\release_v1")
if brain_artifact.parent.exists():
    brain_artifact.mkdir(parents=True, exist_ok=True)
    (brain_artifact / "data").mkdir(parents=True, exist_ok=True)
    shutil.copy2(patch0, brain_artifact / "data" / "9ba626afa44a3aa3.patch_0")
    shutil.copy2(ROOT / "data" / "9ba626afa44a3aa3.patch_0.stream", brain_artifact / "data" / "9ba626afa44a3aa3.patch_0.stream")
    shutil.copy2(ROOT / "data" / "9ba626afa44a3aa3.patch_0.gpu_resources", brain_artifact / "data" / "9ba626afa44a3aa3.patch_0.gpu_resources")
    shutil.copy2(ROOT / "UniversalModLoader-manifest.json", brain_artifact / "UniversalModLoader-manifest.json")
    shutil.copy2(ROOT / "manifest.json", brain_artifact / "manifest.json")
    shutil.copy2(ROOT / "UniversalModLoader-README.txt", brain_artifact / "UniversalModLoader-README.txt")
    shutil.copy2(ROOT / "thumbnail.png", brain_artifact / "thumbnail.png")

print(f"SUCCESS: Built {zip_out} ({zip_out.stat().st_size} bytes)")
