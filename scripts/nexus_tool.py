#!/usr/bin/env python3
"""
Nexus Mods CLI Tool for Helldivers 2 Universal Mod Loader (Mod ID: 18527)
Queries mod metadata, download stats, endorsement count, files, and bug reports.
"""

import os
import sys
import json
import urllib.request
import urllib.error

MOD_ID = 18527
GAME_DOMAIN = "helldivers2"
API_BASE_V1 = "https://api.nexusmods.com/v1"
API_BASE_V3 = "https://api.nexusmods.com/v3"

def get_api_key():
    key = os.environ.get("NEXUS_API_KEY")
    if key:
        return key.strip()
    env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("NEXUS_API_KEY="):
                    return line.split("=", 1)[1].strip()
    return "O1b7u+XpQUCViM6k/uJ+18/Tn8M/ORxCAYKIYG/+atEcoQvmcDiK--J/c+Otk/ppsWxw0d--TewWG0uVxCbtuQHt48tkHw=="

def fetch_json(url, api_key):
    req = urllib.request.Request(url)
    req.add_header("apikey", api_key)
    req.add_header("User-Agent", "UniversalModLoader-CI/1.0.1")
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def main():
    api_key = get_api_key()
    if not api_key:
        print("[ERROR] NEXUS_API_KEY not found.")
        sys.exit(1)

    print(f"[*] Querying Nexus Mods API for {GAME_DOMAIN} / mod {MOD_ID}...")
    try:
        mod_info = fetch_json(f"{API_BASE_V1}/games/{GAME_DOMAIN}/mods/{MOD_ID}.json", api_key)
        files_info = fetch_json(f"{API_BASE_V1}/games/{GAME_DOMAIN}/mods/{MOD_ID}/files.json", api_key)

        print("\n==================== MOD OVERVIEW ====================")
        print(f"Mod Name:          {mod_info.get('name')}")
        print(f"Mod ID:            {mod_info.get('mod_id')}")
        print(f"Current Version:   {mod_info.get('version')}")
        print(f"Author:            {mod_info.get('author')}")
        print(f"Status:            {mod_info.get('status').upper()}")
        print(f"Unique Downloads:  {mod_info.get('mod_unique_downloads')}")
        print(f"Total Downloads:   {mod_info.get('mod_downloads')}")
        print(f"Endorsements:      {mod_info.get('endorsement_count')}")
        print(f"Nexus URL:         https://www.nexusmods.com/{GAME_DOMAIN}/mods/{MOD_ID}")
        print("======================================================")

        print("\n==================== FILE BREAKDOWN ==================")
        for f in files_info.get("files", []):
            cat = f.get("category_name", "UNKNOWN")
            is_primary = " [PRIMARY]" if f.get("is_primary") else ""
            print(f"- File ID {f.get('file_id')}: {f.get('name')} (v{f.get('version')})")
            print(f"  Category:        {cat}{is_primary}")
            print(f"  File Size:       {f.get('size_in_bytes', 0):,} bytes ({f.get('size_kb', 0)} KB)")
            print(f"  Total Downloads: {f.get('total_downloads', 0)}")
            print(f"  Unique Downloads:{f.get('unique_downloads', 0)}")
            print(f"  Uploaded:        {f.get('uploaded_time')}")
        print("======================================================")

        # Check v3 Bug Reports
        try:
            bugs_info = fetch_json(f"{API_BASE_V3}/mod-bugs", api_key)
            bugs = bugs_info.get("data", {}).get("bugs", [])
            print("\n==================== BUG REPORTS =====================")
            print(f"Open Bug Reports:  {len(bugs)}")
            if bugs:
                for b in bugs:
                    print(f"- [{b.get('status')}] #{b.get('id')}: {b.get('title')}")
            else:
                print("All clear! No open bug reports.")
            print("======================================================\n")
        except Exception as e:
            print(f"\n[Note: Bug reports check skipped: {e}]")

    except urllib.error.HTTPError as e:
        print(f"[ERROR] HTTP {e.code}: {e.reason}")
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
