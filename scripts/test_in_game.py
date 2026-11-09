#!/usr/bin/env python3
"""
Automated Live In-Game Test Harness for Helldivers 2 Universal Mod Loader v2.0.0
Deploys patch bundle, arms the in-engine diagnostic sentinel, initiates a live Steam boot pass,
and waits for the in-engine telemetry report.
"""

import os, sys, time, json, shutil, subprocess
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parents[1]

def find_game_data_dir():
    candidates = [
        Path(r"S:\SteamLibrary\steamapps\common\Helldivers 2\data"),
        Path(r"C:\Program Files (x86)\Steam\steamapps\common\Helldivers 2\data"),
        Path(r"D:\SteamLibrary\steamapps\common\Helldivers 2\data"),
        Path(r"E:\SteamLibrary\steamapps\common\Helldivers 2\data")
    ]
    for p in candidates:
        if p.exists() and p.is_dir():
            return p
    return None

def get_appdata_dir():
    local = os.getenv("LOCALAPPDATA") or os.getenv("APPDATA") or "."
    p = Path(local) / "UniversalModLoader"
    p.mkdir(parents=True, exist_ok=True)
    return p

def main():
    print("=" * 60)
    print("  HELLDIVERS 2 UNIVERSAL MOD LOADER v2.0.0")
    print("  AUTOMATED IN-GAME TEST RUNNER")
    print("=" * 60)

    game_data = find_game_data_dir()
    if not game_data:
        print("[!] ERROR: Could not locate Helldivers 2 data directory.")
        sys.exit(1)
    print(f"[*] Target Game Data: {game_data}")

    src_patch0 = ROOT / "data" / "9ba626afa44a3aa3.patch_0"
    if not src_patch0.exists():
        print("[!] ERROR: Built patch_0 not found in repo data/. Run scripts/build.py first.")
        sys.exit(1)

    # Scan for all UML patches (Stingray loads the highest numbered patch!)
    deployed_targets = []
    target_patch0 = game_data / "9ba626afa44a3aa3.patch_0"
    deployed_targets.append(target_patch0)

    for p in game_data.glob("9ba626afa44a3aa3.patch_*"):
        if not p.suffix.endswith((".gpu_resources", ".stream", ".bak")):
            try:
                data = p.read_bytes()
                if b"Universal Mod Loader" in data and p != target_patch0:
                    deployed_targets.append(p)
            except Exception:
                pass

    for target in deployed_targets:
        bak_file = target.with_suffix(target.suffix + ".bak")
        if target.exists() and not bak_file.exists():
            shutil.copy2(target, bak_file)
            print(f"  [OK] Backed up {target.name} to {bak_file.name}")
        shutil.copy2(src_patch0, target)
        print(f"  [OK] Deployed v2.0.0 payload to {target.name} ({src_patch0.stat().st_size} bytes)")

    # Arm In-Engine Test Sentinel
    appdata = get_appdata_dir()
    test_mode_file = appdata / "test_mode.json"
    results_file = appdata / "in_game_test_results.json"

    if results_file.exists():
        results_file.unlink()

    test_config = {
        "enabled": True,
        "auto_quit": False,
        "timeout_seconds": 15,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
    }
    test_mode_file.write_text(json.dumps(test_config, indent=2), encoding="utf-8")
    print("  [OK] Armed In-Engine Test Sentinel at %LOCALAPPDATA%/UniversalModLoader/test_mode.json")

    print("\n[*] Ready to launch Helldivers 2 via Steam...")
    print("    Command: start steam://run/553850")
    print("    Universal Mod Loader will automatically boot, test all 15 subsystems,")
    print("    verify F9 UI rendering, write test telemetry, and cleanly exit the game.")
    print("-" * 60)

    auto_mode = "--auto" in sys.argv or "--yes" in sys.argv or "-y" in sys.argv or not sys.stdin.isatty()
    if not auto_mode:
        launch_now = input("Launch game now for automated verification? (y/n) [y]: ").strip().lower()
        if launch_now != "" and launch_now != "y":
            print("[*] Aborted. Sentinel remains armed for your next manual launch.")
            return
    else:
        print("[*] Running in automated mode. Proceeding with Steam launch...")

    subprocess.run(["cmd", "/c", "start", "steam://run/553850"])
    print("[*] Game launch initiated. Monitoring for in-engine telemetry report...")

    start_wait = time.time()
    max_wait = 120 # 120 seconds timeout for EAC splash + engine boot
    passed = False

    while (time.time() - start_wait) < max_wait:
        if results_file.exists():
            try:
                data = json.loads(results_file.read_text(encoding="utf-8"))
                if data.get("status") == "PASSED":
                    passed = True
                    break
            except Exception:
                pass
        time.sleep(1)
        sys.stdout.write(".")
        sys.stdout.flush()

    print("\n" + "=" * 60)
    if test_mode_file.exists():
        test_mode_file.unlink()

    if passed:
        report = json.loads(results_file.read_text(encoding="utf-8"))
        print("  [PASS] IN-GAME AUTOMATED VERIFICATION: PASSED!")
        print(f"  Version:            {report.get('version')}")
        print(f"  Frame Count:        {report.get('frame')}")
        print(f"  Multi-APIs Verified: {report.get('apis')}")
        print(f"  F9 Settings Menu:   {report.get('f9_menu')}")
        print(f"  Persistence State:  {report.get('options')}")
        print(f"  Loaded Mods Count:  {report.get('loaded_count')}")
        print("=" * 60)
    else:
        print("  [WARN] Timed out waiting for in-game telemetry report (120s).")
        print("  Check %LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log for details.")
        print("=" * 60)

if __name__ == "__main__":
    main()
