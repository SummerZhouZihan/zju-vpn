param(
    [string]$Username = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\powershell\common.ps1')
Initialize-CampusData
if (-not $Username) {
    $baseConfig = Get-Content -LiteralPath (Join-Path $script:CampusData 'config.toml') -Raw -Encoding UTF8
    if ($baseConfig -match '(?m)^username\s*=\s*"([^"]+)"') { $Username = $Matches[1] }
    else { $Username = Read-Host 'ZJU username' }
}
if ([string]::IsNullOrWhiteSpace($Username)) { throw 'ZJU username cannot be empty.' }

Write-Host "This stores the ZJU password encrypted for the current Windows user."
Write-Host ""

$securePassword = Read-Host "ZJU password for $Username" -AsSecureString
if ($securePassword.Length -eq 0) { throw 'Password cannot be empty.' }
$credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)
Save-ZjuCredential $credential

Write-Host ""
Write-Host "Credential saved. Only this Windows user on this machine can decrypt it."
