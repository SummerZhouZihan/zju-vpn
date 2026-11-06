function Get-ClashInstallation([string]$ClashPath, [string]$ClashDataDir) {
    if (-not $ClashPath) {
        $running = Get-Process -Name 'Clash for Windows' -ErrorAction SilentlyContinue |
            Where-Object { $_.Path } | Select-Object -First 1
        if ($running) { $ClashPath = $running.Path }
    }
    if (-not $ClashPath) {
        $candidates = @(
            'C:\programfiles\clash_for_windows\Clash for Windows.exe',
            "$env:LOCALAPPDATA\Programs\Clash for Windows\Clash for Windows.exe",
            "$env:ProgramFiles\Clash for Windows\Clash for Windows.exe"
        )
        $ClashPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    if (-not $ClashPath -or -not (Test-Path -LiteralPath $ClashPath)) {
        throw 'Clash for Windows not found. Specify -ClashPath with its executable path.'
    }
    $installDir = Split-Path -Parent $ClashPath
    if (-not $ClashDataDir) {
        $coreProcess = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^clash.*\.exe$' -and $_.ExecutablePath -like "$installDir\*" } |
            Select-Object -First 1
        if ($coreProcess -and $coreProcess.CommandLine -match '(?:^|\s)-d\s+(?:"([^"]+)"|(.+?))\s*$') {
            $ClashDataDir = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
        }
        if (-not $ClashDataDir) {
            $ClashDataDir = @((Join-Path $installDir 'data'), "$env:USERPROFILE\.config\clash") |
                Where-Object { Test-Path -LiteralPath (Join-Path $_ 'profiles\list.yml') } |
                Select-Object -First 1
        }
    }
    if (-not $ClashDataDir -or -not (Test-Path -LiteralPath (Join-Path $ClashDataDir 'profiles\list.yml'))) {
        throw 'Clash data directory not found. Specify -ClashDataDir.'
    }
    $coreExe = Join-Path $installDir 'resources\static\files\win\x64\clash-win64.exe'
    if (-not (Test-Path -LiteralPath $coreExe)) { throw "Clash core not found: $coreExe" }
    [pscustomobject]@{ Exe = $ClashPath; DataDir = $ClashDataDir; CoreExe = $coreExe }
}

function Invoke-ClashNode($Installation, [string[]]$Arguments) {
    $oldValue = $env:ELECTRON_RUN_AS_NODE
    try {
        $env:ELECTRON_RUN_AS_NODE = '1'
        # A pipeline makes Windows PowerShell wait for the Electron GUI-subsystem
        # executable, and captures its Node-mode stdout.
        $output = & $Installation.Exe @Arguments | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Clash configuration helper failed (exit $LASTEXITCODE)." }
        if ($output) { Write-Output $output.TrimEnd() }
    }
    finally {
        if ($null -eq $oldValue) { Remove-Item Env:\ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue }
        else { $env:ELECTRON_RUN_AS_NODE = $oldValue }
    }
}

function Initialize-Clash {
    param(
        [switch]$SkipClash,
        [switch]$DryRun,
        [switch]$Detailed,
        [string]$ClashPath,
        [string]$ClashDataDir,
        [int]$WaitSeconds = 30
    )
    if ($SkipClash) { return }
    $installation = Get-ClashInstallation $ClashPath $ClashDataDir
    $helper = Join-Path $script:CampusRoot 'src\clash\configure.cjs'
    $planJson = Invoke-ClashNode $installation @($helper, $installation.Exe, $installation.DataDir, $installation.CoreExe, 'plan')
    $plan = ($planJson -join "`n") | ConvertFrom-Json
    if ($Detailed) {
        Write-Step "Clash for Windows: $($installation.Exe)"
        Write-Step "Data directory: $($installation.DataDir); proxy port: $($plan.port)"
    }
    if ($DryRun) {
        Write-Step "Clash campus configuration needs updating: $($plan.changed)"
        return
    }
    if ($plan.changed) {
        # Stop CFW before editing settings so its in-memory state cannot overwrite
        # the changes. The subscription and saved node selections are retained.
        $gui = @(Get-Process -Name 'Clash for Windows' -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $installation.Exe })
        if ($gui.Count -gt 0) {
            Write-Step 'Restarting Clash for Windows to apply the campus configuration.'
            $gui | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            Get-Process -Name 'clash-win64' -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -eq $installation.CoreExe } | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        try {
            $applied = Invoke-ClashNode $installation @($helper, $installation.Exe, $installation.DataDir, $installation.CoreExe, 'apply')
            if ($Detailed -and $applied) { Write-Host $applied }
            $registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
            $current = Get-ItemProperty -LiteralPath $registryPath
            if ($current.ProxyEnable -eq 1 -and $current.ProxyServer -match '127\.0\.0\.1') {
                $filtered = @($current.ProxyOverride -split ';' | Where-Object {
                    $_ -ne '10.*' -and $_ -notmatch '^172\.(1[6-9]|2\d|3[01])\.\*$'
                }) -join ';'
                if ($filtered -ne $current.ProxyOverride) {
                    $backup = Join-Path $script:CampusData ('system-proxy.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.clixml')
                    $current | Select-Object ProxyEnable,ProxyServer,ProxyOverride | Export-Clixml -LiteralPath $backup
                    Set-ItemProperty -LiteralPath $registryPath -Name ProxyOverride -Value $filtered
                    if ($Detailed) { Write-Step "Campus IP proxy bypass updated. Backup: $backup" }
                }
            }
        }
        finally {
            Start-Process -FilePath $installation.Exe -WindowStyle Hidden `
                -RedirectStandardOutput (Join-Path $script:CampusData 'clash-start.out.log') `
                -RedirectStandardError (Join-Path $script:CampusData 'clash-start.err.log')
        }
    }
    elseif (-not (Get-Process -Name 'Clash for Windows' -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $installation.Exe -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $script:CampusData 'clash-start.out.log') `
            -RedirectStandardError (Join-Path $script:CampusData 'clash-start.err.log')
    }
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while (-not (Test-ProxyPorts @([int]$plan.port) @('clash-win64', 'clash', 'mihomo'))) {
        if ((Get-Date) -ge $deadline) { throw "Clash did not listen on port $($plan.port)." }
        Start-Sleep -Milliseconds 500
    }
}
