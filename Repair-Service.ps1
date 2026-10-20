param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
try {
    Write-Host '=== Clash Verge service repair ===' -ForegroundColor Cyan
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin -and -not $CheckOnly) {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
        $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
        exit $p.ExitCode
    }
    $roots = @($PSScriptRoot)
    foreach ($base in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA)) {
        if ($base) { $roots += Join-Path $base 'Clash Verge'; $roots += Join-Path $base 'Programs\Clash Verge' }
    }
    Get-Process -Name clash-verge -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Path) { $roots += Split-Path -Parent $_.Path } }
    foreach ($key in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Clash Verge*' } | ForEach-Object { if ($_.InstallLocation) { $roots += $_.InstallLocation } }
    }
    $installer = $null
    foreach ($root in ($roots | Select-Object -Unique)) {
        foreach ($rel in @('resources\clash-verge-service-install.exe','clash-verge-service-install.exe')) {
            $candidate = Join-Path $root $rel
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $installer = $candidate; break }
        }
        if ($installer) { break }
    }
    $svc = Get-Service clash_verge_service -ErrorAction SilentlyContinue
    if ($CheckOnly) {
        Write-Host "Installer: $installer"
        if ($svc) { Write-Host "Service status: $($svc.Status)" } else { Write-Host 'Service: not installed' }
        if (-not $installer) { throw 'Bundled installer not found.' }
        Write-Host 'Read-only check passed. No changes made.' -ForegroundColor Green
    } else {
        if (-not $svc) {
            if (-not $installer) {
                $folder = (Read-Host 'Enter the Clash Verge installation folder').Trim().Trim('"')
                $installer = Join-Path $folder 'resources\clash-verge-service-install.exe'
                if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'Installer not found. Check the folder or install Clash Verge first.' }
            }
            Write-Host "Installing: $installer"
            $p = Start-Process -FilePath $installer -WorkingDirectory (Split-Path -Parent $installer) -WindowStyle Hidden -PassThru
            if (-not $p.WaitForExit(60000)) { throw 'Installer timeout. Check Windows prompts and wait for it to finish.' }
            if ($p.ExitCode -ne 0) { throw "Installer exit code: $($p.ExitCode)" }
        }
        $svc = Get-Service clash_verge_service
        if ($svc.Status -ne 'Running') { Start-Service clash_verge_service }
        $svc.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running,[TimeSpan]::FromSeconds(15))
        Set-Service clash_verge_service -StartupType Automatic
        Write-Host 'SUCCESS: Service is running. Automatic startup is enabled.' -ForegroundColor Green
        Write-Host 'Reopen Clash Verge, enable Service Mode if shown, then turn on TUN.'
    }
    $result = 0
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Keep this error for troubleshooting.'
    $result = 1
}
if (-not $CheckOnly) { Read-Host 'Press Enter to close' | Out-Null }
exit $result