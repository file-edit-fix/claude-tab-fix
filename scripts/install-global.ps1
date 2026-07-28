<#
.SYNOPSIS
    Install claude-tab-fix hooks into the global Claude Code settings.

.DESCRIPTION
    This script adds the claude-tab-fix hooks to the global ~/.claude/settings.json
    so they activate in every project (including worktrees).

    Usage: .\scripts\install-global.ps1
#>

$ErrorActionPreference = "Stop"

# --- Find the global settings file ---
$settingsDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { "$env:USERPROFILE\.claude" }
$settingsFile = "$settingsDir\settings.json"

# --- Check if claude-tab-fix binary is in PATH ---
$binaryPath = (Get-Command "claude-tab-fix" -ErrorAction SilentlyContinue).Source
if (-not $binaryPath) {
    Write-Error "'claude-tab-fix' binary not found in PATH."
    Write-Error "Install it first: go install github.com/WithHolm/claude-tab-fix@latest"
    exit 1
}
Write-Host "claude-tab-fix binary found at: $binaryPath"

# --- Ensure settings directory exists ---
New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

# --- Hook configuration template ---
$hooksJson = @'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit",
        "hooks": [{ "type": "command", "command": "claude-tab-fix" }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "claude-tab-fix" }]
      },
      {
        "matcher": "Write",
        "hooks": [{ "type": "command", "command": "claude-tab-fix" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Read",
        "hooks": [{ "type": "command", "command": "claude-tab-fix" }]
      }
    ]
  }
}
'@

# --- Merge hooks into settings ---
if (Test-Path $settingsFile) {
    Write-Host "Found existing settings file: $settingsFile"

    # Check if claude-tab-fix EDIT hooks are already present in hooks section
    $config = $content | ConvertFrom-Json
    $hasHooks = $false
    if ($config.hooks) {
        foreach ($hookType in @("PreToolUse", "PostToolUse")) {
            if ($config.hooks.$hookType) {
                foreach ($h in $config.hooks.$hookType) {
                    if ($h.hooks -and ($h.hooks.command -eq "claude-tab-fix" -or $h.hooks[0].command -eq "claude-tab-fix")) {
                        $hasHooks = $true
                    }
                }
            }
        }
    }
    if ($hasHooks) {
        Write-Host "claude-tab-fix hooks are already configured in the global settings."
        Write-Host "No changes made."
        exit 0
    }

    # Merge hooks into existing JSON
    $config = $content | ConvertFrom-Json
    $newHooks = $hooksJson | ConvertFrom-Json

    if (-not $config.hooks) {
        $config | Add-Member -NotePropertyName "hooks" -NotePropertyValue @{}
    }

    $hookTypes = @("PreToolUse", "PostToolUse")
    foreach ($hookType in $hookTypes) {
        if (-not $config.hooks.$hookType) {
            $config.hooks | Add-Member -NotePropertyName $hookType -NotePropertyValue @()
        }
        $existingMatchers = $config.hooks.$hookType | ForEach-Object { $_.matcher }
        foreach ($newHook in $newHooks.hooks.$hookType) {
            if ($existingMatchers -notcontains $newHook.matcher) {
                $config.hooks.$hookType += $newHook
                Write-Host "Added $hookType/$($newHook.matcher) hook"
            }
        }
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
    Write-Host "Settings file updated successfully."
} else {
    Write-Host "No existing settings file. Creating new one..."
    $hooksJson | Set-Content $settingsFile -Encoding UTF8
    Write-Host "Settings file created at $settingsFile"
}

# --- Verify ---
Write-Host ""
Write-Host "=== Verification ==="
$config = Get-Content $settingsFile -Raw | ConvertFrom-Json
$hasHooks = $false
if ($config.hooks) {
    foreach ($hookType in @("PreToolUse", "PostToolUse")) {
        if ($config.hooks.$hookType) {
            foreach ($h in $config.hooks.$hookType) {
                if ($h.hooks -and ($h.hooks.command -eq "claude-tab-fix" -or $h.hooks[0].command -eq "claude-tab-fix")) {
                    $hasHooks = $true
                }
            }
        }
    }
}
if ($hasHooks) {
    Write-Host "PASS: claude-tab-fix hooks found in $settingsFile"
    Write-Host ""
    Write-Host "The hook will now activate in ALL projects, including worktrees."
    Write-Host "To test it, run:"
    Write-Host '  echo ''{"tool_name":"Edit","tool_input":{"file_path":"D:/path/to/tab/file.go","old_string":"    func","new_string":"    func"}}'' | claude-tab-fix'
    Write-Host ""
    Write-Host "Expected: exit code 2 with indent normalization message"
} else {
    Write-Host "FAIL: claude-tab-fix hooks not found in $settingsFile"
    Write-Host "Please check the file manually."
    exit 1
}