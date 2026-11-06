function Set-PrivateDirectoryPermissions([string]$DirectoryPath) {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        [IO.Directory]::SetAccessControl($DirectoryPath, $acl)
    }
    else {
        [IO.FileSystemAclExtensions]::SetAccessControl((New-Object IO.DirectoryInfo($DirectoryPath)), $acl)
    }
}

function Initialize-CampusData {
    if (-not (Test-Path -LiteralPath $script:CampusData)) {
        New-Item -ItemType Directory -Path $script:CampusData -Force | Out-Null
    }
    Set-PrivateDirectoryPermissions $script:CampusData
    $configPath = Join-Path $script:CampusData 'config.toml'
    if (-not (Test-Path -LiteralPath $configPath)) {
        Copy-Item -LiteralPath (Join-Path $script:CampusRoot 'config\zju-connect.example.toml') -Destination $configPath
    }
}

function Write-Step([string]$Message) { Write-Host "[zju-vpn] $Message" }
