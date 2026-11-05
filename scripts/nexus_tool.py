#!/usr/bin/env python3
"""
Nexus Mods CLI Tool for Helldivers 2 Universal Mod Loader (Mod ID: 18527)
Queries mod metadata, download stats, endorsement count, and latest updates.
"""

import os
import sys
import json
import urllib.request
import urllib.error

MOD_ID = 18527
GAME_DOMAIN = "helldivers2"
API_BASE = "https://api.nexusmods.com/v1"

def get_api_key():
    key = os.environ.get("NEXUS_API_KEY")
    if key:
        return key.strip()
    # Check fallback .env file
    env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("NEXUS_API_KEY="):
                    return line.split("=", 1)[1].strip()
    return None

def fetch_json(endpoint, api_key):
    url = f"{API_BASE}/{endpoint}"
    req = urllib.request.Request(url)
    req.add_header("apikey", api_key)
    req.add_header("User-Agent", "UniversalModLoader-CI/1.0.1")
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def main():
    api_key = get_api_key()
    if not api_key:
        print("[ERROR] NEXUS_API_KEY environment variable not set.")
        sys.exit(1)

    print(f"[*] Querying Nexus Mods API for {GAME_DOMAIN} / mod {MOD_ID}...")
    try:
        mod_info = fetch_json(f"games/{GAME_DOMAIN}/mods/{MOD_ID}.json", api_key)
        print("\n=======================================================")
        print(f"Mod Name:        {mod_info.get('name')}")
        print(f"Mod ID:          {mod_info.get('mod_id')}")
        print(f"Current Version: {mod_info.get('version')}")
        print(f"Author:          {mod_info.get('author')}")
        print(f"Status:          {mod_info.get('status')}")
        print(f"Unique Downloads:{mod_info.get('mod_unique_downloads')}")
        print(f"Total Downloads: {mod_info.get('mod_downloads')}")
        print(f"Endorsements:    {mod_info.get('endorsement_count')}")
        print(f"Nexus URL:       https://www.nexusmods.com/{GAME_DOMAIN}/mods/{MOD_ID}")
        print("=======================================================\n")
    except urllib.error.HTTPError as e:
        print(f"[ERROR] HTTP {e.code}: {e.reason}")
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
