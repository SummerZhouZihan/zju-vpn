param([switch]$ResetCredential)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\powershell\common.ps1')
Initialize-CampusData
$exe = Join-Path $script:CampusRoot 'zju-connect-windows-386\zju-connect.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "zju-connect.exe not found: $exe" }
if (Get-Listeners @(1090, 1091)) { throw 'Port 1090/1091 is in use. Close that proxy before interactive login.' }
$credential = Get-ZjuCredential
if ($ResetCredential -or -not $credential) {
    & (Join-Path $script:CampusRoot 'scripts\save-credential.ps1')
    $credential = Get-ZjuCredential
}
if (-not $credential) { throw 'No usable credential was saved.' }
$runtimeConfig = New-ZjuRuntimeConfig $credential
try {
    Write-Step 'Complete captcha in the browser and enter any SMS code in this terminal. Keep this window open while using the VPN.'
    Push-Location $script:CampusData
    try { & $exe -config $runtimeConfig; $result = $LASTEXITCODE }
    finally { Pop-Location }
    if ($result -ne 0) { throw "zju-connect exited with code $result. Use -ResetCredential to change the saved password." }
}
finally { Remove-ZjuRuntimeConfig $runtimeConfig }
