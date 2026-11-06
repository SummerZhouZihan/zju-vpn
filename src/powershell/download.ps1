function Get-ZjuExecutable {
    return (Join-Path $script:CampusRoot 'zju-connect-windows-386\zju-connect.exe')
}

function Get-ZjuDownloadInfo {
    $info = Get-Content -LiteralPath (Join-Path $script:CampusRoot 'config\zju-connect-release.json') -Raw | ConvertFrom-Json
    if ($info.url -notmatch '^https://github\.com/Mythologyli/zju-connect/releases/download/v[0-9.]+/zju-connect-windows-386\.zip$' -or
        $info.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'The pinned download information is invalid.' }
    return $info
}

function Install-ZjuArchive([string]$ArchivePath) {
    $info = Get-ZjuDownloadInfo
    if ((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash -ine $info.sha256) {
        throw 'The download could not be verified. Please download it again.'
    }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $executables = @($zip.Entries | Where-Object { $_.Name -eq 'zju-connect.exe' })
        if ($executables.Count -ne 1 -or $executables[0].Length -gt 100MB) {
            throw 'The download does not contain the expected program.'
        }
        # Only this entry is copied; archive paths are never extracted to disk.
        $target = Get-ZjuExecutable
        $directory = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
        $inputStream = $executables[0].Open()
        $outputStream = $null
        try {
            $outputStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $inputStream.CopyTo($outputStream)
        }
        catch {
            if ($outputStream) {
                $outputStream.Dispose()
                $outputStream = $null
                Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            }
            throw
        }
        finally {
            $inputStream.Dispose()
            if ($outputStream) { $outputStream.Dispose() }
        }
    }
    finally { $zip.Dispose() }
}
