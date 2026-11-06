param(
    [switch]$DryRun,
    [switch]$ForceZjuRestart,
    [switch]$SkipClash,
    [switch]$NonInteractive,
    [switch]$Gui,
    [switch]$Detailed,
    [ValidateSet('Ask', 'Auto', 'Direct', 'Connect')][string]$VpnMode = 'Ask',
    [string]$ClashPath,
    [string]$ClashDataDir,
    [ValidateRange(5, 300)][int]$WaitSeconds = 30
)

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\powershell\common.ps1')

if ($Gui -and -not $DryRun) {
    try {
        . (Join-Path $script:CampusRoot 'src\powershell\ui.ps1')
        Show-ZjuVpnWindow -ClashPath $ClashPath -ClashDataDir $ClashDataDir -SkipClash:$SkipClash `
            -Connect:($VpnMode -eq 'Connect') -ForceZjuRestart:$ForceZjuRestart -WaitSeconds $WaitSeconds
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        . (Join-Path $script:CampusRoot 'src\powershell\localization.ps1')
        [void][Windows.Forms.MessageBox]::Show((Get-UiText 'window_open_failed'), 'zju-vpn')
        throw
    }
    return
}

$startupLock = New-Object Threading.Mutex($false, 'Local\ZjuVpnStartup')
$lockAcquired = $false
try {
    try { $lockAcquired = $startupLock.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $lockAcquired = $true }
    if (-not $lockAcquired) { throw 'Another zju-vpn launcher is running. Retry after it finishes.' }
    if (-not $DryRun) { Initialize-CampusData }
    if ($DryRun) { Write-Step 'Dry run: no files, settings or processes will be changed.' }
    # Install DIRECT bypass rules before VPN login to prevent a VPN connection loop.
    $clashOptions = @{
        SkipClash = $SkipClash; DryRun = $DryRun; Detailed = $Detailed; ClashPath = $ClashPath
        ClashDataDir = $ClashDataDir; WaitSeconds = $WaitSeconds
    }
    Initialize-Clash @clashOptions
    $vpnOptions = @{
        ForceZjuRestart = $ForceZjuRestart; DryRun = $DryRun
        NonInteractive = $NonInteractive; WaitSeconds = $WaitSeconds
    }
    $directAvailable = Test-CampusDirect
    if ($directAvailable) { Write-Step 'Campus resources are available directly.' }
    else { Write-Step 'Direct campus access is not available. Connect school VPN if you need campus resources.' }
    if ($VpnMode -eq 'Ask' -and ($NonInteractive -or $DryRun)) { $VpnMode = 'Auto' }
    $connectVpn = $VpnMode -eq 'Connect' -or ($VpnMode -eq 'Auto' -and -not $directAvailable)
    if ($VpnMode -eq 'Ask') {
        $connectVpn = (Read-Host 'Connect school VPN for off-campus access? [y/N]') -match '^(?i)y(es)?$'
    }
    if ($connectVpn) { Start-Zju @vpnOptions }
    else { Write-Step 'School VPN was not started. You can connect it later from start.cmd.' }
    if ($Detailed) {
        Get-Listeners @(1090,1091,7890,7891,7892) | Sort-Object LocalPort |
            Select-Object LocalAddress,LocalPort,@{Name='Process';Expression={Get-OwnerName $_.OwningProcess}} |
            Format-Table -AutoSize
    }
    if (-not $DryRun) { Write-Step 'Routing is ready. Use Clash in Rule mode with its system proxy enabled.' }
}
finally {
    if ($lockAcquired) { $startupLock.ReleaseMutex() }
    $startupLock.Dispose()
}
