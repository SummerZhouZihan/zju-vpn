$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$names = Get-Content -LiteralPath (Join-Path $root 'public-files.json') -Raw | ConvertFrom-Json
if (Get-Command node.exe -ErrorAction SilentlyContinue) {
    & node.exe (Join-Path $root 'tests\public-source.test.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'Public source validation failed.' }
}
else {
    . (Join-Path $root 'src\powershell\common.ps1')
    $installation = Get-ClashInstallation
    Invoke-ClashNode $installation @((Join-Path $root 'tests\public-source.test.cjs'))
}
$output = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$zip = Join-Path $output 'zju-vpn-source.zip'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream = [IO.File]::Open($zip, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
$archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in $names) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $root $name), $name) | Out-Null
    }
}
finally { $archive.Dispose(); $stream.Dispose() }
Write-Output $zip
