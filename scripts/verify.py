import os, sys, struct, hashlib, json, zipfile, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT / "scripts"))
import archive

ZIP_PATH = ROOT / "dist" / "Helldivers2-Universal-Mod-Loader-latest.zip"
if not ZIP_PATH.exists():
    candidates = list((ROOT / "dist").glob("Helldivers2-Universal-Mod-Loader-*.zip"))
    if candidates:
        ZIP_PATH = candidates[0]
    elif Path(r"g:\antigravity\Helldivers2-Universal-Mod-Loader-v2.0.0.zip").exists():
        ZIP_PATH = Path(r"g:\antigravity\Helldivers2-Universal-Mod-Loader-v2.0.0.zip")
    else:
        import subprocess
        subprocess.check_call([sys.executable, str(ROOT / "scripts" / "build.py")])
        if (ROOT / "dist" / "Helldivers2-Universal-Mod-Loader-latest.zip").exists():
            ZIP_PATH = ROOT / "dist" / "Helldivers2-Universal-Mod-Loader-latest.zip"
assert ZIP_PATH.exists(), f"ZIP not found: {ZIP_PATH}"

print(f"Verifying package: {ZIP_PATH} ({ZIP_PATH.stat().st_size} bytes)")

with zipfile.ZipFile(ZIP_PATH, "r") as z:
    m = json.loads(z.read("UniversalModLoader-manifest.json").decode("utf-8"))
    print(f"Manifest version: {m.get('version')} (revision: {m.get('revision')})")
    
    for fname, expected in m["files"].items():
        actual = hashlib.sha256(z.read(fname)).hexdigest().upper()
        assert actual == expected, f"Hash mismatch for {fname}: expected {expected}, got {actual}"
        print(f"  [OK] Hash matched for {fname}")

    patch0 = z.read("data/9ba626afa44a3aa3.patch_0")
    magic, ntypes, nentries = struct.unpack_from('<III', patch0, 0)
    assert magic == 0xF0000011, f"Bad magic: {hex(magic)}"
    payload = archive.read_resource(patch0, 0xF476DF93691895FA)
    assert payload is not None, "Missing boot resource in patch"
    print(f"  [OK] Stingray archive valid. Resource payload: {len(payload)} bytes")

    # Verify boot resource payload contains Lua header
    size, unk = struct.unpack_from('<II', payload, 0)
    lua_code = payload[8:8+size].decode('utf-8', errors='ignore')
    expected_v = f"Universal Mod Loader v{m.get('version')}"
    assert expected_v in lua_code, f"Missing {expected_v} version string in boot resource"
    print(f"  [OK] Payload contains verified v{m.get('version')} bootloader ({size} bytes of Lua)")

print(f"\nALL ARCHIVE INTEGRITY CHECKS PASSED FOR v{m.get('version')}!")
