function Get-ZjuCredential([switch]$Quiet) {
    $path = Join-Path $script:CampusData 'zju-connect.credential.clixml'
    if (Test-Path -LiteralPath $path) {
        try {
            $saved = Import-Clixml -LiteralPath $path -ErrorAction Stop
            if ($saved -is [pscredential] -and $saved.Password.Length -gt 0) { return $saved }
        }
        catch { }
        if (-not $Quiet) { Write-Step 'Enter your account again to use it on this Windows account.' }
    }
    return $null
}

function Save-ZjuCredential([pscredential]$Credential) {
    if (-not $Credential -or [string]::IsNullOrWhiteSpace($Credential.UserName) -or $Credential.Password.Length -eq 0) {
        throw 'Enter both a ZJU account and a password.'
    }
    Initialize-CampusData
    $path = Join-Path $script:CampusData 'zju-connect.credential.clixml'
    if (Test-Path -LiteralPath $path) {
        Copy-Item -LiteralPath $path -Destination ($path + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    $Credential | Export-Clixml -LiteralPath $path
}

function New-ZjuRuntimeConfig([pscredential]$Credential) {
    Initialize-CampusData
    $content = Get-Content -LiteralPath (Join-Path $script:CampusData 'config.toml') -Raw -Encoding UTF8
    $bstr = [IntPtr]::Zero
    try {
        $values = @{
            client_data_file = (Join-Path $script:CampusData 'client_data.json')
            socks_bind = '127.0.0.1:1090'
            http_bind = '127.0.0.1:1091'
        }
        if ($Credential) {
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
            $values.username = $Credential.UserName
            $values.password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        foreach ($key in $values.Keys) {
            # JSON string escapes are also valid TOML basic-string escapes. MatchEvaluator
            # prevents passwords containing '$' from becoming regex replacement groups.
            $quoted = ConvertTo-Json -InputObject ([string]$values[$key]) -Compress
            $line = "$key = $quoted"
            $pattern = '(?m)^\s*' + [regex]::Escape($key) + '\s*=.*$'
            if ([regex]::IsMatch($content, $pattern)) {
                $replacement = { param($match) $line }.GetNewClosure()
                $content = [regex]::Replace($content, $pattern, [Text.RegularExpressions.MatchEvaluator]$replacement)
            }
            else { $content += "`r`n$line`r`n" }
        }
        # Create an owner-only directory BEFORE writing the temporary password.
        $runtimeDir = Join-Path $script:CampusData ('runtime-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
        Set-PrivateDirectoryPermissions $runtimeDir
        $path = Join-Path $runtimeDir 'config.toml'
        [IO.File]::WriteAllText($path, $content, (New-Object Text.UTF8Encoding($false)))
        return $path
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $content = $null
        $values = $null
    }
}

function Remove-ZjuRuntimeConfig([string]$Path) {
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Force
        # Only remove the now-empty directory, never recursively delete a computed path.
        Remove-Item -LiteralPath (Split-Path -Parent $Path) -ErrorAction SilentlyContinue
    }
}
