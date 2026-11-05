#!/usr/bin/env python3
"""
Nexus Mods Bug Report Synchronizer
Syncs bug reports from Nexus Mods (v3 mod-bugs API) to GitHub Issues.
Can run locally or in GitHub Actions.
"""

import os
import sys
import json
import subprocess
import urllib.request
import urllib.error

MOD_ID = 18527
REPO = "realityzero0/helldivers2-universal-mod-loader"
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

def fetch_nexus_bugs(api_key):
    url = f"{API_BASE_V3}/mod-bugs"
    req = urllib.request.Request(url)
    req.add_header("apikey", api_key)
    req.add_header("User-Agent", "UniversalModLoader-BugSync/1.0.1")
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        return data.get("data", {}).get("bugs", [])

def get_existing_github_bugs():
    try:
        cmd = ["gh", "issue", "list", "--repo", REPO, "--json", "number,title", "--limit", "100"]
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        issues = json.loads(res.stdout)
        existing_ids = set()
        for issue in issues:
            title = issue.get("title", "")
            if "[Nexus Bug #" in title:
                # Extract id between '[Nexus Bug #' and ']'
                try:
                    bug_id = title.split("[Nexus Bug #")[1].split("]")[0].strip()
                    existing_ids.add(bug_id)
                except Exception:
                    pass
        return existing_ids
    except Exception as e:
        print(f"[WARN] Failed to query existing GitHub issues: {e}")
        return set()

def create_github_issue(bug):
    bug_id = str(bug.get("id"))
    title = f"[Nexus Bug #{bug_id}] {bug.get('title', 'Untitled')}"
    user = bug.get("user", {}).get("name", "Nexus User")
    status = bug.get("status", "open")
    version = bug.get("mod_version", "unknown")
    body_text = bug.get("description", "No description provided.")
    nexus_url = f"https://www.nexusmods.com/helldivers2/mods/{MOD_ID}?tab=bugs"

    body = f"""### Nexus Mods Bug Report #{bug_id}

- **Reporter:** {user}
- **Status on Nexus:** `{status}`
- **Reported Mod Version:** `{version}`
- **Nexus Bug Tracker:** [View on Nexus Mods]({nexus_url})

---

### Description:
{body_text}
"""
    cmd = [
        "gh", "issue", "create",
        "--repo", REPO,
        "--title", title,
        "--body", body,
        "--label", "bug"
    ]
    print(f"[*] Creating GitHub Issue for Nexus Bug #{bug_id}: {title}")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        print(f"[+] Created: {res.stdout.strip()}")
    else:
        print(f"[ERROR] Failed to create issue: {res.stderr.strip()}")

def main():
    api_key = get_api_key()
    if not api_key:
        print("[ERROR] NEXUS_API_KEY not found.")
        sys.exit(1)

    print(f"[*] Checking Nexus Mods bug reports for Mod ID {MOD_ID}...")
    try:
        bugs = fetch_nexus_bugs(api_key)
        print(f"[*] Found {len(bugs)} open bug report(s) on Nexus Mods.")
        if not bugs:
            print("[+] No bug reports to sync.")
            return

        existing_bug_ids = get_existing_github_bugs()
        print(f"[*] Existing synced Nexus bug IDs on GitHub: {existing_bug_ids}")

        new_count = 0
        for bug in bugs:
            b_id = str(bug.get("id"))
            if b_id not in existing_bug_ids:
                create_github_issue(bug)
                new_count += 1
            else:
                print(f"[*] Bug #{b_id} already synced to GitHub. Skipping.")

        print(f"[+] Bug synchronization complete. Synced {new_count} new report(s).")
    except urllib.error.HTTPError as e:
        print(f"[ERROR] HTTP {e.code}: {e.reason}")
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
