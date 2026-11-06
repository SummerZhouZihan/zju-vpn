function Read-ZjuSessionState([string]$Directory) {
    $path = Join-Path $Directory 'status.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
    try { return ($reader.ReadToEnd() | ConvertFrom-Json) }
    finally { $reader.Dispose() }
}

function Write-ZjuSessionState([string]$Directory, [string]$State, [string]$Message, [string]$MessageKey) {
    $json = @{ state = $State; message = $Message; message_key = $MessageKey } | ConvertTo-Json -Compress
    $temporary = Join-Path $Directory 'status.next.json'
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
    $status = Join-Path $Directory 'status.json'
    if (Test-Path -LiteralPath $status) {
        [IO.File]::Replace($temporary, $status, (Join-Path $Directory 'status.previous.json'))
    }
    else { [IO.File]::Move($temporary, $status) }
}

function Invoke-ZjuSession {
    param([string]$SessionDir, [switch]$ForceZjuRestart, [string]$MutexName = 'Local\ZjuVpnInteractiveSession')
    $resolved = [IO.Path]::GetFullPath($SessionDir)
    if ((Split-Path -Parent $resolved) -ne $script:CampusData -or (Split-Path -Leaf $resolved) -notmatch '^ui-session-[a-f0-9]{32}$') {
        throw 'Invalid private session directory.'
    }
    if (-not $ForceZjuRestart -and (Test-ProxyPorts @(1090,1091) @('zju-connect'))) {
        Write-ZjuSessionState $resolved 'ready' 'School VPN is already connected. You can close this window.' 'vpn_already_connected'
        return
    }
    $exe = Get-ZjuExecutable
    if ($ForceZjuRestart) {
        Get-Process -Name 'zju-connect' -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $exe } | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    $mutex = New-Object Threading.Mutex($false, $MutexName)
    $acquired = $false
    $process = $null
    $runtime = $null
    $log = $null
    $ready = $false
    try {
        try { $acquired = $mutex.WaitOne($(if ($ForceZjuRestart) { 3000 } else { 0 })) }
        catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) {
            Write-ZjuSessionState $resolved 'failed' 'Another VPN connection is being managed. Close the pending connection window and try again.' 'vpn_session_busy'
            return
        }
        if (Test-ProxyPorts @(1090,1091) @('zju-connect')) {
            Write-ZjuSessionState $resolved 'ready' 'School VPN is already connected. You can close this window.' 'vpn_already_connected'
            return
        }
        if (Get-Listeners @(1090,1091)) { throw 'The local VPN ports are in use by another program.' }
        $credential = Get-ZjuCredential -Quiet
        if (-not $credential) { throw 'Enter your ZJU account and password to connect.' }
        $runtime = New-ZjuRuntimeConfig $credential
        $credential = $null
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $exe
        $info.Arguments = '-config "' + $runtime + '"'
        $info.WorkingDirectory = $script:CampusData
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $info
        [void]$process.Start()
        $log = New-Object IO.StreamWriter((Join-Path $resolved 'vpn.log'), $true, (New-Object Text.UTF8Encoding($false)))
        $log.AutoFlush = $true
        # Read raw pipe chunks: StreamReader can wait for a full buffer when a
        # verification prompt has no trailing newline.
        $readers = @($process.StandardOutput.BaseStream, $process.StandardError.BaseStream)
        $buffers = New-Object 'Collections.Generic.List[byte[]]'
        $buffers.Add([byte[]]::new(4096))
        $buffers.Add([byte[]]::new(4096))
        $decoders = @([Text.Encoding]::UTF8.GetDecoder(), [Text.Encoding]::UTF8.GetDecoder())
        $characters = [char[]]::new(8192)
        $tasks = @($readers[0].ReadAsync($buffers[0],0,4096), $readers[1].ReadAsync($buffers[1],0,4096))
        $recent = ''
        $lastPrompt = ''
        $deadline = (Get-Date).AddMinutes(6)
        Write-ZjuSessionState $resolved 'authenticating' 'Connecting. Complete any verification that opens in your browser.' 'vpn_authenticating'
        while (-not $process.HasExited) {
            for ($i = 0; $i -lt 2; $i++) {
                if ($tasks[$i] -and $tasks[$i].IsCompleted) {
                    $count = $tasks[$i].GetAwaiter().GetResult()
                    if ($count -gt 0) {
                        $charCount = $decoders[$i].GetChars($buffers[$i],0,$count,$characters,0,$false)
                        $chunk = [string]::new($characters,0,$charCount)
                        $log.Write($chunk)
                        $recent += $chunk
                        if ($recent.Length -gt 8192) { $recent = $recent.Substring($recent.Length - 8192) }
                        $tasks[$i] = $readers[$i].ReadAsync($buffers[$i],0,4096)
                    }
                    else { $tasks[$i] = $null }
                }
            }
            if (-not $ready) {
                if (Test-Path -LiteralPath (Join-Path $resolved 'cancel')) {
                    Write-ZjuSessionState $resolved 'cancelled' 'Connection cancelled. Direct routing remains available.' 'vpn_cancelled'
                    return
                }
                if (Test-ProxyPorts @(1090,1091) @('zju-connect')) {
                    $ready = $true
                    Remove-ZjuRuntimeConfig $runtime
                    $runtime = $null
                    Write-ZjuSessionState $resolved 'ready' 'School VPN is connected. You can close this window; it will keep running.' 'vpn_connected'
                }
                elseif ($recent -match '(?i)(?:enter|input)[^\r\n]{0,100}(?:sms|verification code|totp)') {
                    if ($lastPrompt -ne $recent) {
                        Write-ZjuSessionState $resolved 'code_required' 'Enter the verification code requested by the school VPN.' 'vpn_code_required'
                        $lastPrompt = $recent
                    }
                }
                $codePath = Join-Path $resolved 'code.txt'
                if (Test-Path -LiteralPath $codePath) {
                    $code = [IO.File]::ReadAllText($codePath).Trim()
                    Remove-Item -LiteralPath $codePath -Force
                    if ($code -match '^[a-zA-Z0-9-]{1,32}$') {
                        $process.StandardInput.WriteLine($code)
                        $process.StandardInput.Flush()
                        $recent = ''
                        Write-ZjuSessionState $resolved 'authenticating' 'Verification submitted. Waiting for the school VPN.' 'vpn_code_submitted'
                    }
                    $code = $null
                }
                if ((Get-Date) -gt $deadline) { throw 'The login session expired. Try connecting again.' }
            }
            Start-Sleep -Milliseconds 200
        }
        Write-ZjuSessionState $resolved 'failed' 'The school VPN stopped. Check your account or try connecting again.' 'vpn_stopped'
    }
    catch {
        # Diagnostics stay private; user messages do not contain credentials.
        if ($log) { $log.WriteLine($_.Exception.Message) }
        Write-ZjuSessionState $resolved 'failed' 'Could not connect to school VPN. Check your account and retry; private diagnostics are saved.' 'vpn_failed'
    }
    finally {
        if ($process) {
            if (-not $process.HasExited) { try { $process.Kill() } catch {} }
            $process.Dispose()
        }
        if ($runtime) { Remove-ZjuRuntimeConfig $runtime }
        $codePath = Join-Path $resolved 'code.txt'
        if (Test-Path -LiteralPath $codePath) { Remove-Item -LiteralPath $codePath -Force }
        $nextCode = Join-Path $resolved 'code.next'
        if (Test-Path -LiteralPath $nextCode) { Remove-Item -LiteralPath $nextCode -Force }
        if ($log) { $log.Dispose() }
        if ($acquired) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
