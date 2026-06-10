param(
    [switch]$Apply,
    [string]$Locale = "zh-cn",
    [string]$CodexLocale = "zh-CN",
    [string]$AppDataPath = $env:APPDATA,
    [string]$UserProfilePath = $env:USERPROFILE,
    [string]$PowerShellProfilePath = $PROFILE,
    [switch]$SkipUserEnvironment
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n== $Message =="
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Backup-File {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        Copy-Item -LiteralPath $Path -Destination "$Path.bak-$stamp" -Force
    }
}

function Read-JsonObject {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $raw = Get-Content -LiteralPath $Path -Raw
        if ($raw.Trim().Length -gt 0) {
            return $raw | ConvertFrom-Json
        }
    }
    return [pscustomobject]@{}
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory=$true)]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$Value
    )
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Save-JsonObject {
    param(
        [Parameter(Mandatory=$true)]$Object,
        [Parameter(Mandatory=$true)][string]$Path
    )
    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Show-Diagnostics {
    Write-Step "Console"
    [pscustomobject]@{
        InputEncoding = [Console]::InputEncoding.WebName
        OutputEncoding = [Console]::OutputEncoding.WebName
        OutputCodePage = [Console]::OutputEncoding.CodePage
    } | Format-List
    chcp

    Write-Step "Culture"
    Get-Culture | Select-Object Name,DisplayName | Format-List
    Get-UICulture | Select-Object Name,DisplayName | Format-List

    Write-Step "Environment"
    $envRows = foreach ($name in "PYTHONUTF8","PYTHONIOENCODING","LANG","LC_ALL") {
        [pscustomobject]@{
            Name = $name
            Process = [Environment]::GetEnvironmentVariable($name, "Process")
            User = [Environment]::GetEnvironmentVariable($name, "User")
        }
    }
    $envRows | Format-Table -AutoSize

    Write-Step "VS Code and Codex paths"
    $paths = @(
        "$AppDataPath\Code\User\settings.json",
        "$AppDataPath\Code\User\locale.json",
        "$UserProfilePath\.codex\config.toml",
        "$UserProfilePath\.codex\.env",
        $PowerShellProfilePath
    )
    $pathRows = foreach ($path in $paths) {
        [pscustomobject]@{
            Path = $path
            Exists = Test-Path -LiteralPath $path
        }
    }
    $pathRows | Format-Table -AutoSize
}

function Apply-Fix {
    $codeUserDir = Join-Path $AppDataPath "Code\User"
    $settingsPath = Join-Path $codeUserDir "settings.json"
    $localePath = Join-Path $codeUserDir "locale.json"
    $codexDir = Join-Path $UserProfilePath ".codex"
    $codexConfigPath = Join-Path $codexDir "config.toml"
    $codexEnvPath = Join-Path $codexDir ".env"

    Ensure-Directory $codeUserDir
    Ensure-Directory $codexDir
    Ensure-Directory (Split-Path -Parent $PowerShellProfilePath)

    Write-Step "Writing VS Code locale"
    Backup-File $localePath
    [pscustomobject]@{ locale = $Locale } | ConvertTo-Json | Set-Content -LiteralPath $localePath -Encoding UTF8

    Write-Step "Writing VS Code settings"
    Backup-File $settingsPath
    $settings = Read-JsonObject $settingsPath
    Set-JsonProperty $settings "chatgpt.localeOverride" $CodexLocale
    Set-JsonProperty $settings "terminal.integrated.defaultProfile.windows" "PowerShell"
    Set-JsonProperty $settings "files.encoding" "utf8"
    Set-JsonProperty $settings "files.autoGuessEncoding" $true
    $terminalEnv = [pscustomobject]@{
        PYTHONUTF8 = "1"
        PYTHONIOENCODING = "utf-8"
        LANG = "zh_CN.UTF-8"
        LC_ALL = "zh_CN.UTF-8"
    }
    Set-JsonProperty $settings "terminal.integrated.env.windows" $terminalEnv
    Save-JsonObject $settings $settingsPath

    Write-Step "Writing Codex environment"
    Backup-File $codexEnvPath
    @(
        "PYTHONUTF8=1",
        "PYTHONIOENCODING=utf-8",
        "LANG=zh_CN.UTF-8",
        "LC_ALL=zh_CN.UTF-8"
    ) | Set-Content -LiteralPath $codexEnvPath -Encoding UTF8

    Write-Step "Writing Codex shell environment policy"
    if (Test-Path -LiteralPath $codexConfigPath) {
        Backup-File $codexConfigPath
        $config = Get-Content -LiteralPath $codexConfigPath -Raw
    } else {
        $config = ""
    }
    $policy = "[shell_environment_policy]`r`nset = { PYTHONUTF8 = `"1`", PYTHONIOENCODING = `"utf-8`", LANG = `"zh_CN.UTF-8`", LC_ALL = `"zh_CN.UTF-8`" }"
    if ($config -match "(?ms)^\[shell_environment_policy\]\s*.*?(?=^\[|\z)") {
        $config = [regex]::Replace($config, "(?ms)^\[shell_environment_policy\]\s*.*?(?=^\[|\z)", "$policy`r`n")
    } elseif ($config.Trim().Length -gt 0) {
        $config = $config.TrimEnd() + "`r`n`r`n" + $policy + "`r`n"
    } else {
        $config = $policy + "`r`n"
    }
    Set-Content -LiteralPath $codexConfigPath -Value $config -Encoding UTF8

    Write-Step "Writing PowerShell profile"
    Backup-File $PowerShellProfilePath
    $profileBlock = @'
# Keep PowerShell and child tools on UTF-8.
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

try {
    chcp 65001 > $null
} catch {
}
'@
    if (Test-Path -LiteralPath $PowerShellProfilePath) {
        $existingProfile = Get-Content -LiteralPath $PowerShellProfilePath -Raw
        if ($existingProfile -notmatch "PYTHONIOENCODING|OutputEncoding|chcp 65001") {
            Add-Content -LiteralPath $PowerShellProfilePath -Value "`r`n$profileBlock" -Encoding UTF8
        }
    } else {
        Set-Content -LiteralPath $PowerShellProfilePath -Value $profileBlock -Encoding UTF8
    }

    if ($SkipUserEnvironment) {
        Write-Step "Skipping Windows user environment"
    } else {
        Write-Step "Writing Windows user environment"
        [Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
        [Environment]::SetEnvironmentVariable("PYTHONIOENCODING", "utf-8", "User")
        Set-ItemProperty -Path "HKCU:\Environment" -Name "LANG" -Value "zh_CN.UTF-8" -Type String
        Set-ItemProperty -Path "HKCU:\Environment" -Name "LC_ALL" -Value "zh_CN.UTF-8" -Type String
    }
}

function Verify-Fix {
    Write-Step "Verification"
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        python -c "import sys,locale,os; print(sys.stdout.encoding); print(locale.getpreferredencoding(False)); print(os.getenv('PYTHONUTF8'), os.getenv('PYTHONIOENCODING'), os.getenv('LANG'), os.getenv('LC_ALL')); print('\u4e2d\u6587\u6d4b\u8bd5')"
    } else {
        Write-Host "python not found; skipping Python verification"
    }

    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if ($codex) {
        codex --version
    } else {
        Write-Host "codex not found on PATH; skipping Codex CLI verification"
    }
}

Show-Diagnostics

if ($Apply) {
    Apply-Fix
    Show-Diagnostics
    Verify-Fix
    Write-Host "`nRestart or reload VS Code/Codex for language and user environment changes to take effect."
} else {
    Write-Host "`nDiagnosis only. Re-run with -Apply to write the standard repair."
}
