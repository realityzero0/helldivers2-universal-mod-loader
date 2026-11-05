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

# Package ZIPs for Arsenal Mod Manager / HD2MM
zip_out = Path(r"g:\antigravity\Helldivers2-Universal-Mod-Loader-v1.0.1.zip")
zip_out_compat = Path(r"g:\antigravity\Helldivers2-Universal-Mod-Loader-v1.0.0.zip")
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

shutil.copy2(zip_out, zip_out_compat)



# Sync release_v1 artifact directory if present in brain
release_v1 = Path(r"C:\Users\drews\.gemini\antigravity\brain\e6c8c351-3fc4-4332-9d71-f1fc99a33eb3\release_v1")
release_v1.mkdir(parents=True, exist_ok=True)
(release_v1 / "data").mkdir(parents=True, exist_ok=True)
shutil.copy2(patch0, release_v1 / "data" / "9ba626afa44a3aa3.patch_0")
shutil.copy2(ROOT / "data" / "9ba626afa44a3aa3.patch_0.stream", release_v1 / "data" / "9ba626afa44a3aa3.patch_0.stream")
shutil.copy2(ROOT / "data" / "9ba626afa44a3aa3.patch_0.gpu_resources", release_v1 / "data" / "9ba626afa44a3aa3.patch_0.gpu_resources")
shutil.copy2(ROOT / "UniversalModLoader-manifest.json", release_v1 / "UniversalModLoader-manifest.json")
shutil.copy2(ROOT / "manifest.json", release_v1 / "manifest.json")
shutil.copy2(ROOT / "UniversalModLoader-README.txt", release_v1 / "UniversalModLoader-README.txt")
shutil.copy2(ROOT / "thumbnail.png", release_v1 / "thumbnail.png")

print(f"SUCCESS: Built {zip_out} ({zip_out.stat().st_size} bytes)")
