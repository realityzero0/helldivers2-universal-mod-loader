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

print(f"SUCCESS: Built {zip_out} ({zip_out.stat().st_size} bytes)")
