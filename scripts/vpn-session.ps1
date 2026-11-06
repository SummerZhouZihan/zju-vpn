param([Parameter(Mandatory = $true)][string]$SessionDir, [switch]$ForceZjuRestart)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\powershell\common.ps1')
. (Join-Path $script:CampusRoot 'src\powershell\session.ps1')
Invoke-ZjuSession -SessionDir $SessionDir -ForceZjuRestart:$ForceZjuRestart
