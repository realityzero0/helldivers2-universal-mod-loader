# Community Reporting & Troubleshooting Guide

This guide explains how to gather logs, test compatibility, and submit actionable reports for the **Helldivers 2 Universal Mod Loader** ecosystem.

---

## 1. Where Are the Mod Loader Logs?

Whenever Universal Mod Loader initializes and boots your mods, it writes a detailed execution log.

* **Primary Log Location on Windows:**
  ```text
  %LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\BingusSharedLoader.log
  ```
  *(Press `Win + R`, paste the path above, and press `Enter` to open it in Notepad).*

* **Clean-Install Fallback Location:**
  If CowboyBingus was never installed on your PC, the log is located in your Helldivers 2 data folder:
  ```text
  %APPDATA%\Arrowhead\Helldivers2\BingusSharedLoader.log
  ```

* **Settings File Location:**
  ```text
  %LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\uml_mod_settings.json
  ```
  *(Or `%APPDATA%\Arrowhead\Helldivers2\uml_mod_settings.json` on clean installations).*

---

## 2. Understanding Your Log File

When you inspect `BingusSharedLoader.log`, look for lines starting with `[UniversalLoader]`:

| Log Entry | Meaning |
| :--- | :--- |
| `[UniversalLoader] Loaded mod: mods/author/mod_1` | The mod initialized successfully with zero errors. |
| `[UniversalLoader] Failed loading mods/author/mod_1: ...` | The mod encountered a syntax error or missing prerequisite. Universal Mod Loader's circuit breaker caught the error so your game **did not crash**. |
| `[UniversalLoader] [SafeMode] Skipping quarantined mod ...` | The mod previously caused a hard C++ crash in the game engine. Universal Mod Loader quarantined it on this launch so your game boots smoothly. |

---

## 3. How to Submit a Structured Report

To ensure your report can be investigated and resolved immediately without guesswork:

1. **Verify Your Load Order:** Make sure Universal Mod Loader is placed in **Position 1 (`patch_0`)** in Arsenal Mod Manager.
2. **Open a GitHub Issue:**
   * **For Bugs / Loader Glitches:** Use the [Bug Report Form](https://github.com/realityzero0/helldivers2-universal-mod-loader/issues/new?template=bug_report.yml).
   * **For Mod Compatibility Submissions:** Use the [Mod Compatibility Form](https://github.com/realityzero0/helldivers2-universal-mod-loader/issues/new?template=compatibility_report.yml).
   * **For Author Status / Monthly Check-Ins:** Use the [Mod Stewardship Form](https://github.com/realityzero0/helldivers2-universal-mod-loader/issues/new?template=mod_stewardship.yml).
3. **Always Include Your Log:** A report without `BingusSharedLoader.log` cannot be diagnosed!

---

## 4. The 90-Day Mod Lifecycle & Abandonment Policy

To prevent player confusion about whether broken mods will ever be fixed:

* **Active (🟢):** Actively maintained by the original mod author.
* **Static / Feature-Complete (🔵):** The mod has completed development, works reliably, and does not require future updates. **These mods are permanently exempt from abandonment flags.**
* **Needs Verification (🟡):** A mod with no author or community activity in over 60 days. Players are encouraged to submit a monthly check-in confirming it works on the latest game patch.
* **Abandoned Upstream (🔴):** A mod whose author has been inactive for **90+ days** and which has open, unresolved crash reports on the latest game build. Open for community adoption/forking.
