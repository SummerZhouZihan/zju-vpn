$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\powershell\common.ps1')
$realData = $script:CampusData
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

# Run with Windows PowerShell 5.1 to catch unsupported syntax in every entry point.
(Get-Content -LiteralPath (Join-Path $root 'public-files.json') -Raw | ConvertFrom-Json) |
    Where-Object { $_ -like '*.ps1' } | ForEach-Object { Get-Item -LiteralPath (Join-Path $root $_) } | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-True ($parseErrors.Count -eq 0) "Syntax errors in $($_.Name): $parseErrors"
}

# Exercise password escaping using synthetic credentials, without reading real secrets.
$password = 'test$1"back\slash' + "`t" + 'end'
$credential = New-Object Management.Automation.PSCredential('test$2', (ConvertTo-SecureString $password -AsPlainText -Force))
$script:CampusData = Join-Path $env:TEMP ('zju-vpn-test-' + [guid]::NewGuid().ToString('N'))
$runtime = New-ZjuRuntimeConfig $credential
try {
    $content = Get-Content -LiteralPath $runtime -Raw -Encoding UTF8
    Assert-True ($content -match '(?m)^password = (.+)$') 'Missing runtime password'
    $roundTrip = $Matches[1] | ConvertFrom-Json
    Assert-True ($roundTrip -ceq $password) 'Password characters were changed during TOML escaping'
    Assert-True ($content -match '(?m)^client_data_file = (.+)$') 'Missing absolute session path'
    $session = $Matches[1] | ConvertFrom-Json
    Assert-True ($session -eq (Join-Path $script:CampusData 'client_data.json')) 'Wrong session path'
    $acl = Get-Acl -LiteralPath (Split-Path -Parent $runtime)
    Assert-True $acl.AreAccessRulesProtected 'Runtime directory inherits permissions'
}
finally {
    Remove-ZjuRuntimeConfig $runtime
    Remove-Item -LiteralPath (Join-Path $script:CampusData 'config.toml') -Force
    Remove-Item -LiteralPath $script:CampusData
    $script:CampusData = $realData
}
Assert-True (-not (Test-Path -LiteralPath $runtime)) 'Temporary password file was left behind'

if ($env:CI -eq 'true') { Write-Host 'PowerShell syntax and credential handling: OK'; return }
$installation = Get-ClashInstallation
Invoke-ClashNode $installation @((Join-Path $root 'tests\clash-parser.test.cjs'), $installation.Exe)

# DryRun must preserve the active configuration and credential/session files.
$paths = @(
    (Join-Path $installation.DataDir 'cfw-settings.yaml'),
    (Join-Path $installation.DataDir 'profiles\list.yml'),
    (Join-Path $script:CampusData 'config.toml'),
    (Join-Path $script:CampusData 'client_data.json'),
    (Join-Path $script:CampusData 'zju-connect.credential.clixml')
) | Where-Object { Test-Path -LiteralPath $_ }
$paths += @(Get-ChildItem -LiteralPath (Join-Path $installation.DataDir 'profiles') -File | Select-Object -ExpandProperty FullName)
$before = @{}
foreach ($file in $paths) { $before[$file] = (Get-FileHash -LiteralPath $file).Hash }
$dryOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\start.ps1') -DryRun -VpnMode Direct 2>&1
Assert-True ($LASTEXITCODE -eq 0) 'DryRun failed'
Assert-True (($dryOutput -join "`n") -match 'School VPN was not started') 'Direct mode attempted to start VPN'
Assert-True (($dryOutput -join "`n") -notmatch 'WARNING|standby is not ready') 'Direct-only use should not produce a VPN warning'
Write-Host ($dryOutput -join "`n")
foreach ($file in $paths) {
    Assert-True ($before[$file] -eq (Get-FileHash -LiteralPath $file).Hash) "DryRun changed $file"
}
Write-Host 'One-key startup checks: OK'
