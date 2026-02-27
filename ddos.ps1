#Requires -Version 5.0
<#
.SYNOPSIS
    DDOS / Pentmenu - Windows PowerShell Launcher

.DESCRIPTION
    Detects WSL, Git Bash, or Cygwin and runs the ddos script.
    Run as Administrator for full raw-socket attack support.

.NOTES
    Usage: .\ddos.ps1
    Or right-click > "Run with PowerShell"
#>

# -------------------------------------------------------
# Colors and helpers
# -------------------------------------------------------
function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  =========================================================" -ForegroundColor Cyan
    Write-Host "   DDOS / Pentmenu - Windows PowerShell Launcher" -ForegroundColor Red
    Write-Host "   Version 1.2.4  |  github.com/ekovegeance/DDOS" -ForegroundColor DarkGray
    Write-Host "  =========================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Ok    { param($msg) Write-Host "  [OK]     $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [WARN]   $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "  [ERROR]  $msg" -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host "  [INFO]   $msg" -ForegroundColor Cyan }

# -------------------------------------------------------
# Check admin rights
# -------------------------------------------------------
function Test-Admin {
    $currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# -------------------------------------------------------
# Convert a Windows path to a WSL-compatible /mnt/ path
# -------------------------------------------------------
function Convert-ToWslPath {
    param([string]$WinPath)
    $wslPath = $WinPath -replace '\\', '/'
    $wslPath = $wslPath -replace '^([A-Za-z]):', { '/mnt/' + $Matches[1].ToLower() }
    return $wslPath
}

# -------------------------------------------------------
# Install WSL helper
# -------------------------------------------------------
function Show-WslInstallGuide {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "  ║           HOW TO SET UP WSL (Recommended)             ║" -ForegroundColor Yellow
    Write-Host "  ╠═══════════════════════════════════════════════════════╣" -ForegroundColor Yellow
    Write-Host "  ║  1. Open PowerShell as Administrator                  ║"
    Write-Host "  ║  2. Run:  wsl --install                               ║"
    Write-Host "  ║  3. Restart your PC                                   ║"
    Write-Host "  ║  4. Open Ubuntu and run:                              ║"
    Write-Host "  ║     sudo apt update && sudo apt install -y \           ║"
    Write-Host "  ║       bash curl nmap hping3 netcat-openbsd \          ║"
    Write-Host "  ║       openssl stunnel whois                           ║"
    Write-Host "  ║  5. Re-run this launcher                              ║"
    Write-Host "  ╠═══════════════════════════════════════════════════════╣" -ForegroundColor Yellow
    Write-Host "  ║  OPTION 2: Git for Windows (limited, no raw sockets)  ║"
    Write-Host "  ║    https://git-scm.com/download/win                   ║"
    Write-Host "  ╠═══════════════════════════════════════════════════════╣" -ForegroundColor Yellow
    Write-Host "  ║  OPTION 3: Cygwin (full POSIX)                        ║"
    Write-Host "  ║    https://www.cygwin.com/                            ║"
    Write-Host "  ║    Install packages: bash curl nmap netcat openssl    ║"
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
}

# -------------------------------------------------------
# Check WSL dependencies inside the distro
# -------------------------------------------------------
function Test-WslDependencies {
    Write-Info "Checking dependencies inside WSL..."
    $missingTools = @()
    $tools = @("curl", "nmap", "hping3", "openssl", "nc", "whois", "stunnel")
    foreach ($tool in $tools) {
        $result = wsl which $tool 2>$null
        if (-not $result) { $missingTools += $tool }
    }
    if ($missingTools.Count -gt 0) {
        Write-Warn "Missing WSL tools: $($missingTools -join ', ')"
        Write-Host ""
        Write-Host "  Install them with:" -ForegroundColor Yellow
        Write-Host "    wsl sudo apt install -y $($missingTools -join ' ')" -ForegroundColor White
        Write-Host ""
        $answer = Read-Host "  Continue anyway? [y/N]"
        if ($answer -notmatch '^[yY]$') {
            Write-Host ""
            Write-Host "  Run the install command above, then re-launch." -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Ok "All tools found in WSL."
    }
}

# -------------------------------------------------------
# MAIN
# -------------------------------------------------------
Write-Header

# Admin check
if (-not (Test-Admin)) {
    Write-Warn "Not running as Administrator."
    Write-Warn "Raw-socket attacks may fail. Consider re-running as Administrator."
    Write-Host ""
}

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $scriptDir "ddos"

if (-not (Test-Path $scriptPath)) {
    Write-Err "Cannot find 'ddos' script in: $scriptDir"
    Write-Err "Make sure ddos.ps1 and the 'ddos' file are in the same folder."
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Info "Detecting available Linux environments..."
Write-Host ""

# -------------------------------------------------------
# Priority 1: WSL
# -------------------------------------------------------
$wslExe = Get-Command wsl -ErrorAction SilentlyContinue
if ($wslExe) {
    Write-Info "WSL binary found. Probing WSL health..."

    # Run a short probe with a timeout (10 s) via a background job.
    # This avoids hanging forever when HCS/vmcompute service is down.
    $probeJob = Start-Job -ScriptBlock {
        $out = & wsl echo wsl_ok 2>&1
        return @{ Output = ($out -join "`n"); ExitCode = $LASTEXITCODE }
    }
    $finished = Wait-Job $probeJob -Timeout 10
    $wslOk = $false

    if (-not $finished) {
        # Timed out -- WSL is hanging (Hyper-V issue)
        Stop-Job  $probeJob
        Remove-Job $probeJob -Force
        Write-Warn "WSL probe timed out (Hyper-V / HCS service not responding)."
    } else {
        $result = Receive-Job $probeJob
        Remove-Job $probeJob -Force

        $errorPatterns = @(
            'HCS_E', 'SERVICE_NOT_AVAILABLE', 'vmcompute', '0x80070422',
            'not installed', 'no installed', 'WSL 2 requires', 'virtual machine',
            'enable-feature', 'ERROR_FILE_NOT_FOUND'
        )
        $hasError = $errorPatterns | Where-Object { $result.Output -match $_ }
        $hasOkOutput = $result.Output -match 'wsl_ok'

        if ($result.ExitCode -eq 0 -and $hasOkOutput -and -not $hasError) {
            $wslOk = $true
        } else {
            Write-Warn "WSL returned non-zero or unexpected output:"
            Write-Host "  $($result.Output.Trim())" -ForegroundColor DarkGray
        }
    }

    if ($wslOk) {
        # Make sure at least one distro is registered
        $distros = & wsl --list --quiet 2>$null | Where-Object { $_ -match '\S' }
        if (-not $distros) {
            Write-Warn "WSL works but no Linux distro is installed."
            Write-Host "  Run: wsl --install  (then restart)" -ForegroundColor Yellow
            $wslOk = $false
        }
    }

    if ($wslOk) {
        Write-Ok "WSL is healthy. Running dependency check..."
        Test-WslDependencies
        Write-Host ""
        Write-Info "Launching ddos via WSL..."
        Write-Host ""
        $wslPath = Convert-ToWslPath $scriptPath
        & wsl bash "$wslPath"
        exit 0
    } else {
        Write-Host ""
        Write-Host "  Common fixes (run PowerShell as Administrator):" -ForegroundColor Yellow
        Write-Host "    wsl --update" -ForegroundColor White
        Write-Host "    wsl --set-default-version 1   # WSL 1 -- no Hyper-V needed" -ForegroundColor White
        Write-Host ""
        Write-Info "Falling through to Git Bash..."
        Write-Host ""
    }
}

# -------------------------------------------------------
# Priority 2: Git Bash
# -------------------------------------------------------
$gitBashCandidates = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$gitBash = $gitBashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($gitBash) {
    Write-Ok "Git Bash found: $gitBash"
    Write-Warn "Git Bash has limited tool support (no raw sockets, no hping3)."
    Write-Warn "WSL is recommended for full functionality."
    Write-Host ""
    Write-Info "Launching ddos via Git Bash..."
    Write-Host ""
    & $gitBash --login -i $scriptPath
    exit 0
}

# -------------------------------------------------------
# Priority 3: Cygwin
# -------------------------------------------------------
$cygwinCandidates = @(
    "C:\cygwin64\bin\bash.exe",
    "C:\cygwin\bin\bash.exe"
)
$cygwinBash = $cygwinCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($cygwinBash) {
    Write-Ok "Cygwin found: $cygwinBash"
    Write-Info "Launching ddos via Cygwin..."
    Write-Host ""
    & $cygwinBash --login -i -c "cd '$scriptDir' && bash ddos"
    exit 0
}

# -------------------------------------------------------
# Nothing found
# -------------------------------------------------------
Write-Err "No compatible Linux environment found."
Write-Host ""
Show-WslInstallGuide

Read-Host "  Press Enter to exit"
exit 1
