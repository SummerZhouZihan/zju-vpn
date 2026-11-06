$ErrorActionPreference = 'Stop'
$script:CampusRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script:CampusData = Join-Path $env:LOCALAPPDATA 'zju-vpn'
foreach ($component in @('environment.ps1', 'network.ps1', 'credentials.ps1', 'clash.ps1', 'vpn.ps1', 'download.ps1')) {
    . (Join-Path $PSScriptRoot $component)
}
