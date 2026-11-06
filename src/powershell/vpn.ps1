function Start-Zju {
    param(
        [switch]$ForceZjuRestart,
        [switch]$DryRun,
        [switch]$NonInteractive,
        [int]$WaitSeconds = 30
    )
    $zjuExe = Join-Path $script:CampusRoot 'zju-connect-windows-386\zju-connect.exe'
    if (-not (Test-Path -LiteralPath $zjuExe)) { throw "zju-connect not found: $zjuExe" }
    if ($ForceZjuRestart) {
        if ($DryRun) { Write-Step 'Would stop this directory''s zju-connect process.' }
        else {
            Get-Process -Name 'zju-connect' -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -eq $zjuExe } | Stop-Process -Force
        }
    }
    if ((Test-ProxyPorts @(1090, 1091) @('zju-connect')) -and -not ($ForceZjuRestart -and $DryRun)) {
        Write-Step 'zju-connect is already listening on 1090/1091.'
        return
    }
    $blocked = @(Get-Listeners @(1090, 1091))
    if ($blocked.Count -gt 0 -and -not ($ForceZjuRestart -and $DryRun)) {
        throw 'Port 1090/1091 is occupied or zju-connect is only partially started. Check the owning process.'
    }
    $credential = Get-ZjuCredential
    if ($DryRun) {
        Write-Step "Credential usable on this machine: $([bool]$credential)"
        Write-Step 'Would start zju-connect; missing/unreadable credentials require local password input.'
        return
    }
    # This zju-connect build requires a password even when client_data.json exists.
    if (-not $credential) {
        if ($NonInteractive) { throw 'The copied credential cannot be decrypted here. Run login.cmd locally to save this machine''s password and complete login.' }
        & (Join-Path $script:CampusRoot 'scripts\save-credential.ps1')
        $credential = Get-ZjuCredential
        if (-not $credential) { throw 'No usable credential was saved.' }
    }
    $runtimeConfig = New-ZjuRuntimeConfig $credential
    $outLog = Join-Path $script:CampusData 'zju-connect.onekey.out.log'
    $errLog = Join-Path $script:CampusData 'zju-connect.onekey.err.log'
    $zjuProcess = $null
    try {
        Write-Step 'Starting zju-connect.'
        $zjuProcess = Start-Process -FilePath $zjuExe -ArgumentList @('-config', ('"{0}"' -f $runtimeConfig)) `
            -WorkingDirectory $script:CampusData -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
            -WindowStyle Hidden -PassThru
        $deadline = (Get-Date).AddSeconds($WaitSeconds)
        while ((Get-Date) -lt $deadline) {
            if (Test-ProxyPorts @(1090, 1091) @('zju-connect')) {
                Write-Step 'zju-connect is listening on 127.0.0.1:1090/1091.'
                return
            }
            if ($zjuProcess.HasExited) { break }
            Start-Sleep -Milliseconds 500
        }
        throw 'VPN login needs attention. Run login.cmd in a local terminal to enter the password/captcha/SMS; then retry this launcher. Logs: zju-connect.onekey.out.log / zju-connect.onekey.err.log'
    }
    catch {
        # Do not leave an invisible process waiting for captcha/SMS and holding ports.
        if ($zjuProcess -and -not $zjuProcess.HasExited) { $zjuProcess | Stop-Process -Force }
        throw
    }
    finally { Remove-ZjuRuntimeConfig $runtimeConfig }
}
