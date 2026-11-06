param(
    [Parameter(Position = 0)]
    [ValidateSet('check', 'prepare')][string]$Action = 'check',
    [string]$ProxyUrl = 'http://127.0.0.1:7890'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) 'src\powershell\common.ps1')
$proxy = [uri]$ProxyUrl
if ($proxy.Scheme -ne 'http' -or $proxy.Host -notin @('127.0.0.1', 'localhost', '[::1]') -or $proxy.UserInfo) {
    throw 'ProxyUrl must be an unauthenticated loopback HTTP proxy.'
}

function Get-NetworkStatus {
    $checks = @()
    if (-not (Test-ProxyPorts @($proxy.Port) @('clash-win64', 'clash', 'mihomo'))) {
        return [pscustomobject]@{ protocol = 1; status = 'not_ready'; checks = $checks }
    }
    foreach ($probe in @(
        @{ name = 'campus_idp'; url = 'https://idp.zju.edu.cn/' },
        @{ name = 'carsi'; url = 'https://ds.carsi.edu.cn/' },
        @{ name = 'public_metadata'; url = 'https://api.crossref.org/works?rows=0' }
    )) {
        $code = 0
        try {
            $curlArgs = @(
                '--silent', '--output', 'NUL', '--write-out', '%{http_code}',
                '--connect-timeout', '3', '--max-time', '6', '--ssl-revoke-best-effort',
                '--proxy', $ProxyUrl, '--noproxy', 'localhost,127.0.0.1', $probe.url
            )
            $output = & curl.exe @curlArgs 2>$null
            if ($LASTEXITCODE -eq 0) { [void][int]::TryParse(($output -join '').Trim(), [ref]$code) }
        }
        catch { $code = 0 }
        $checks += [pscustomobject]@{
            name = $probe.name
            reachable = ($code -ge 200 -and $code -lt 400)
            http_status = $code
        }
    }
    $status = if (@($checks | Where-Object { -not $_.reachable }).Count -eq 0) { 'ready' } else { 'attention_required' }
    return [pscustomobject]@{ protocol = 1; status = $status; checks = $checks }
}

$prepareLock = $null
$lockAcquired = $false
try {
    if ($Action -eq 'prepare') {
        $prepareLock = New-Object Threading.Mutex($false, 'Local\ZjuCampusNetworkPrepare')
        try { $lockAcquired = $prepareLock.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $lockAcquired = $true }
        if (-not $lockAcquired) {
            [pscustomobject]@{ protocol = 1; status = 'attention_required'; checks = @() } | ConvertTo-Json -Compress
            return
        }
    }
    $result = Get-NetworkStatus
    if ($Action -eq 'prepare' -and $result.status -ne 'ready') {
        # Retain detailed launcher output locally. The public JSON contract carries no credentials.
        Initialize-CampusData
        $log = Join-Path $script:CampusData 'paperread-network.last.log'
        $launcher = Join-Path $script:CampusRoot 'scripts\start.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -NonInteractive -WaitSeconds 15 *> $log
        if ($LASTEXITCODE -eq 0) { $result = Get-NetworkStatus }
        else { $result = [pscustomobject]@{ protocol = 1; status = 'attention_required'; checks = @() } }
    }
}
catch {
    $result = [pscustomobject]@{ protocol = 1; status = 'provider_error'; checks = @() }
}
finally {
    if ($lockAcquired) { $prepareLock.ReleaseMutex() }
    if ($prepareLock) { $prepareLock.Dispose() }
}
$result | ConvertTo-Json -Depth 4 -Compress
