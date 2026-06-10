---
name: codex-windows-locale-fix
description: Diagnose and fix Codex or VS Code language and encoding problems on Windows. Use when the user reports Codex in VS Code showing English despite Chinese settings, ChatGPT/Codex extension locale not applying, terminal Chinese mojibake, UnicodeDecodeError, GBK/UTF-8 decode failures, Python stdout encoding problems, or Windows PowerShell/VS Code integrated terminal not preserving UTF-8.
---

# Codex Windows Locale Fix

## Workflow

Use this skill on Windows when Codex, VS Code, or tools launched through Codex disagree about UI language or text encoding.

1. Check the active environment first:
   - `[Console]::InputEncoding`, `[Console]::OutputEncoding`
   - `chcp`
   - `Get-Culture`, `Get-UICulture`
   - user environment variables: `PYTHONUTF8`, `PYTHONIOENCODING`, `LANG`, `LC_ALL`
   - VS Code files under `$env:APPDATA\Code\User`
   - Codex config under `$env:USERPROFILE\.codex`

2. For Codex UI language in VS Code:
   - Ensure the Simplified Chinese VS Code language pack is installed if VS Code itself is expected to be Chinese.
   - Set `$env:APPDATA\Code\User\locale.json` to `{ "locale": "zh-cn" }`.
   - Set `chatgpt.localeOverride` in VS Code `settings.json` to `zh-CN`.
   - Restart or reload VS Code after changing these values.

3. For terminal and child-process encoding:
   - Prefer UTF-8 everywhere: console code page `65001`, PowerShell input/output UTF-8, and Python UTF-8 mode.
   - Set VS Code `terminal.integrated.env.windows` with:
     - `PYTHONUTF8=1`
     - `PYTHONIOENCODING=utf-8`
     - `LANG=zh_CN.UTF-8`
     - `LC_ALL=zh_CN.UTF-8`
   - Set Windows user environment variables with the same values so apps launched outside a shell inherit them on next start.
   - Add a PowerShell profile only if none exists or merge carefully if it exists.

4. For commands launched by Codex:
   - Put the same values in `$env:USERPROFILE\.codex\.env`.
   - Add or update `[shell_environment_policy]` in `$env:USERPROFILE\.codex\config.toml`.
   - Do not overwrite unrelated Codex settings.

5. Verify in a new shell:
   - `chcp` reports `Active code page: 65001`.
   - Python reports UTF-8 for `sys.stdout.encoding` and `locale.getpreferredencoding(False)`.
   - Printing Chinese text succeeds.
   - `codex --version` still runs, proving `config.toml` remains parseable.

## Script

Use `scripts/fix-codex-windows-locale.ps1` for repeatable diagnosis and repair.

Run diagnosis only:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-windows-locale-fix\scripts\fix-codex-windows-locale.ps1"
```

Apply the standard repair:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-windows-locale-fix\scripts\fix-codex-windows-locale.ps1" -Apply
```

Use `-Locale zh-cn` and `-CodexLocale zh-CN` unless the user explicitly wants another language.
For dry-run testing of `-Apply`, pass temporary `-AppDataPath`, `-UserProfilePath`,
`-PowerShellProfilePath`, and `-SkipUserEnvironment`.

## Editing Rules

- Preserve unrelated user settings in `settings.json` and `config.toml`.
- Create parent directories if missing.
- Prefer PowerShell JSON parsing for VS Code settings instead of string replacement.
- Back up files before changing them.
- Treat `Get-UICulture` being `en-US` as a likely reason auto-detection chooses English; explicit `chatgpt.localeOverride` should override it.
- Tell the user to reload or restart VS Code/Codex after applying changes.
