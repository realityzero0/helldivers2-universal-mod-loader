import os, sys, struct, hashlib, json, zipfile, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT / "scripts"))
import archive

ZIP_PATH = Path(r"g:\antigravity\Helldivers2-Universal-Mod-Loader-v1.0.0.zip")
assert ZIP_PATH.exists(), f"ZIP not found: {ZIP_PATH}"

with zipfile.ZipFile(ZIP_PATH, "r") as z:
    m = json.loads(z.read("UniversalModLoader-manifest.json").decode("utf-8"))
    for fname, expected in m["files"].items():
        actual = hashlib.sha256(z.read(fname)).hexdigest().upper()
        assert actual == expected, f"Hash mismatch for {fname}"
        print(f"  [OK] Hash matched for {fname}")

    patch0 = z.read("data/9ba626afa44a3aa3.patch_0")
    magic, ntypes, nentries = struct.unpack_from('<III', patch0, 0)
    assert magic == 0xF0000011, f"Bad magic: {hex(magic)}"
    payload = archive.read_resource(patch0, 0xF476DF93691895FA)
    assert payload is not None, "Missing boot resource in patch"
    print(f"  [OK] Stingray archive valid. Resource payload: {len(payload)} bytes")

print("ALL ARCHIVE INTEGRITY CHECKS PASSED!")
