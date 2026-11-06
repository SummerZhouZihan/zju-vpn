function Test-CampusDirect {
    try {
        $output = & curl.exe --head --silent --output NUL --write-out '%{http_code}' `
            --noproxy '*' --connect-timeout 3 --max-time 6 --ssl-revoke-best-effort https://www.cc98.org/ 2>$null
        return ($LASTEXITCODE -eq 0 -and ($output -join '').Trim() -match '^2\d\d$')
    }
    catch { return $false }
}

function Get-Listeners([int[]]$Ports) {
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $Ports -contains $_.LocalPort }
}

function Get-OwnerName([int]$PidValue) {
    $ownerProcess = Get-Process -Id $PidValue -ErrorAction SilentlyContinue
    if ($ownerProcess) { return $ownerProcess.ProcessName }
    return 'unknown'
}

function Test-ProxyPorts([int[]]$Ports, [string[]]$ProcessNames) {
    $listeners = @(Get-Listeners $Ports)
    foreach ($port in $Ports) {
        $owned = @($listeners | Where-Object {
            $_.LocalPort -eq $port -and
            $_.LocalAddress -in @('127.0.0.1', '0.0.0.0', '::', '::1') -and
            (Get-OwnerName $_.OwningProcess) -in $ProcessNames
        })
        if ($owned.Count -eq 0) { return $false }
    }
    return $true
}
