. (Join-Path $PSScriptRoot 'session.ps1')
. (Join-Path $PSScriptRoot 'localization.ps1')

function Set-WizardMessage([string]$Key, [object[]]$Values = @()) {
    $script:Wizard.StatusKey = $Key
    $script:Wizard.StatusValues = $Values
    $script:Wizard.Status.Text = Get-UiText -Key $Key -Language $script:Wizard.Language -Values $Values
}

function Update-WizardLanguage {
    $w = $script:Wizard
    foreach ($name in $w.TextBindings.Keys) {
        $w[$name].Text = Get-UiText -Key $w.TextBindings[$name] -Language $w.Language
    }
    $w.Network.Text = Get-UiText -Key $w.NetworkKey -Language $w.Language
    $w.Status.Text = Get-UiText -Key $w.StatusKey -Language $w.Language -Values $w.StatusValues
    $installed = Test-Path -LiteralPath (Get-ZjuExecutable) -PathType Leaf
    $w.InstallLabel.Text = Get-UiText -Key $(if ($installed) { 'installed' } else { 'not_installed' }) -Language $w.Language
    $w.Start.Text = Get-UiText -Key $(if ($w.Connect.Checked) { 'start_connect' } else { 'start_direct' }) -Language $w.Language
}

function Set-WizardBusy([bool]$Busy) {
    $w = $script:Wizard
    $w.Busy = $Busy
    foreach ($control in @($w.Direct, $w.Connect, $w.User, $w.Password, $w.Start, $w.Download)) {
        $control.Enabled = -not $Busy
    }
    if (-not $Busy) { Update-WizardChoice }
}

function Update-WizardChoice {
    $w = $script:Wizard
    if ($w.Busy) { return }
    $installed = Test-Path -LiteralPath (Get-ZjuExecutable) -PathType Leaf
    $w.Download.Visible = -not $installed
    Update-WizardLanguage
    $w.User.Enabled = $w.Connect.Checked
    $w.Password.Enabled = $w.Connect.Checked
    $w.Start.Enabled = $w.Direct.Checked -or $installed
    $w.Form.AcceptButton = $w.Start
}

function Complete-WizardOperation([string]$Key) {
    Set-WizardBusy $false
    Set-WizardMessage $Key
    $script:Wizard.Code.Enabled = $false
    $script:Wizard.SendCode.Enabled = $false
    $script:Wizard.Form.AcceptButton = $script:Wizard.Close
    $script:Wizard.Close.Focus() | Out-Null
}

function Invoke-WizardDownload {
    $w = $script:Wizard
    try {
        $info = Get-ZjuDownloadInfo
        $w.DownloadDir = Join-Path $w.Data ('download-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $w.DownloadDir | Out-Null
        Set-PrivateDirectoryPermissions $w.DownloadDir
        $w.Archive = Join-Path $w.DownloadDir 'zju-connect.zip'
        $w.Client = New-Object Net.WebClient
        $w.Client.Headers.Add('User-Agent', 'zju-vpn')
        $w.DownloadTask = $w.Client.DownloadFileTaskAsync([uri]$info.url, $w.Archive)
        $w.DownloadDeadline = (Get-Date).AddMinutes(3)
        Set-WizardBusy $true
        Set-WizardMessage 'download_progress' @($info.version)
    }
    catch {
        Set-WizardBusy $false
        Set-WizardMessage 'download_start_failed'
    }
}

function Start-WizardRouting {
    $w = $script:Wizard
    try {
        $w.WantVpn = $w.Connect.Checked
        if ($w.WantVpn -and -not (Test-ProxyPorts @(1090,1091) @('zju-connect'))) {
            if ($w.Password.Text.Length -gt 0) {
                if ([string]::IsNullOrWhiteSpace($w.User.Text)) {
                    Set-WizardMessage 'account_required'
                    return
                }
                $secure = ConvertTo-SecureString $w.Password.Text -AsPlainText -Force
                $credential = New-Object Management.Automation.PSCredential($w.User.Text.Trim(), $secure)
                Save-ZjuCredential $credential
                $w.Saved = $true
                $credential = $null
                $w.Password.Clear()
            }
            elseif (-not (Get-ZjuCredential -Quiet)) {
                Set-WizardMessage 'credentials_required'
                return
            }
        }
        $launcher = Join-Path $w.Root 'scripts\start.ps1'
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $launcher),
            '-NonInteractive', '-VpnMode', 'Direct', '-WaitSeconds', $w.WaitSeconds)
        if ($w.SkipClash) { $arguments += '-SkipClash' }
        if ($w.ClashPath) { $arguments += @('-ClashPath', ('"{0}"' -f $w.ClashPath)) }
        if ($w.ClashDataDir) { $arguments += @('-ClashDataDir', ('"{0}"' -f $w.ClashDataDir)) }
        $w.Routing = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $w.Data 'startup.out.log') `
            -RedirectStandardError (Join-Path $w.Data 'startup.err.log')
        # Retain the process handle before returning to the WinForms message loop.
        # Otherwise Windows PowerShell can lose the exit code after the child exits.
        [void]$w.Routing.Handle
        Set-WizardBusy $true
        Set-WizardMessage 'routing_preparing'
    }
    catch {
        Set-WizardBusy $false
        Set-WizardMessage 'routing_start_failed'
    }
}

function Start-WizardSession {
    $w = $script:Wizard
    $w.SessionDir = Join-Path $w.Data ('ui-session-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $w.SessionDir | Out-Null
    Set-PrivateDirectoryPermissions $w.SessionDir
    $worker = Join-Path $w.Root 'scripts\vpn-session.ps1'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $worker),
        '-SessionDir', ('"{0}"' -f $w.SessionDir))
    if ($w.ForceZjuRestart) { $arguments += '-ForceZjuRestart' }
    $w.Session = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $w.SessionDir 'worker.out.log') `
        -RedirectStandardError (Join-Path $w.SessionDir 'worker.err.log')
    $w.SessionReady = $false
    $w.LastSessionText = ''
    Set-WizardMessage 'vpn_connecting'
}

function Update-WizardTasks {
    $w = $script:Wizard
    try {
        if ($w.ProbeTask -and $w.ProbeTask.IsCompleted) {
            try {
                $response = $w.ProbeTask.GetAwaiter().GetResult()
                $w.DirectAvailable = [int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 300
                $response.Dispose()
            }
            catch { $w.DirectAvailable = $false }
            $w.ProbeTask = $null
            $w.NetworkKey = if ($w.DirectAvailable) { 'network_available' } else { 'network_unavailable' }
            Update-WizardLanguage
        }
        if ($w.DownloadTask) {
            if ((Get-Date) -gt $w.DownloadDeadline) { $w.Client.CancelAsync() }
            if ($w.DownloadTask.IsCompleted) {
                try {
                    $w.DownloadTask.GetAwaiter().GetResult()
                    Install-ZjuArchive $w.Archive
                    Set-WizardMessage 'download_complete'
                }
                catch { Set-WizardMessage 'download_failed' }
                finally {
                    $w.Client.Dispose()
                    $w.Client = $null
                    $w.DownloadTask = $null
                    if (Test-Path -LiteralPath $w.Archive) { Remove-Item -LiteralPath $w.Archive -Force }
                    Remove-Item -LiteralPath $w.DownloadDir -ErrorAction SilentlyContinue
                    Set-WizardBusy $false
                }
            }
        }
        if ($w.Routing -and $w.Routing.HasExited) {
            $w.Routing.WaitForExit()
            $exitCode = $w.Routing.ExitCode
            $w.Routing.Dispose()
            $w.Routing = $null
            if ($null -eq $exitCode) {
                Complete-WizardOperation 'routing_result_unknown'
            }
            elseif ($exitCode -ne 0) {
                Complete-WizardOperation 'routing_failed'
            }
            elseif ($w.WantVpn) { Start-WizardSession }
            else { Complete-WizardOperation 'routing_ready_direct' }
        }
        if ($w.Session) {
            $statusPath = Join-Path $w.SessionDir 'status.json'
            if (Test-Path -LiteralPath $statusPath) {
                try { $status = Read-ZjuSessionState $w.SessionDir } catch { $status = $null }
                if ($status -and $status.message -ne $w.LastSessionText) {
                    $w.LastSessionText = $status.message
                    $messageKey = if ($status.message_key) { $status.message_key } else {
                        switch ($status.state) {
                            'ready' { 'vpn_connected' }
                            'code_required' { 'vpn_code_required' }
                            'cancelled' { 'vpn_cancelled' }
                            'authenticating' { 'vpn_authenticating' }
                            default { 'vpn_failed' }
                        }
                    }
                    Set-WizardMessage $messageKey
                    $w.Code.Enabled = $status.state -eq 'code_required'
                    $w.SendCode.Enabled = $w.Code.Enabled
                    if ($w.Code.Enabled) { $w.Code.Focus() | Out-Null; $w.Form.AcceptButton = $w.SendCode }
                    if ($status.state -eq 'ready') {
                        $w.SessionReady = $true
                        Complete-WizardOperation $messageKey
                    }
                    elseif ($status.state -in @('failed','cancelled')) { Complete-WizardOperation $messageKey }
                }
            }
            if ($w.Session.HasExited) {
                $w.Session.Dispose()
                $w.Session = $null
                if ($w.Busy) { Complete-WizardOperation 'vpn_connection_ended' }
            }
        }
    }
    catch { Complete-WizardOperation 'operation_failed' }
}

function Show-ZjuVpnWindow {
    param([string]$ClashPath, [string]$ClashDataDir, [switch]$SkipClash, [switch]$Connect,
        [switch]$ForceZjuRestart, [int]$WaitSeconds = 30, [switch]$BuildOnly)
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Net.Http
    [Windows.Forms.Application]::EnableVisualStyles()
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Initialize-CampusData
    $saved = Get-ZjuCredential -Quiet
    $w = @{
        Language = 'zh-CN'; NetworkKey = 'network_checking'; StatusKey = 'direct_normal'; StatusValues = @()
        Root = $script:CampusRoot; Data = $script:CampusData; Busy = $false; Saved = [bool]$saved
        ClashPath = $ClashPath; ClashDataDir = $ClashDataDir; SkipClash = $SkipClash
        ForceZjuRestart = $ForceZjuRestart; WaitSeconds = $WaitSeconds; SessionReady = $false
    }
    $script:Wizard = $w
    $form = New-Object Windows.Forms.Form
    $w.Form = $form
    $form.Text = 'zju-vpn'
    $form.ClientSize = New-Object Drawing.Size(640,660)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.Font = New-Object Drawing.Font('Segoe UI',10)
    $form.AutoScaleMode = 'Dpi'
    function Add-Label($Text, $X, $Y, $Width, $Height) {
        $label = New-Object Windows.Forms.Label
        $label.UseMnemonic = $false
        $label.Text = $Text; $label.Location = New-Object Drawing.Point($X,$Y)
        $label.Size = New-Object Drawing.Size($Width,$Height)
        $form.Controls.Add($label)
        return $label
    }
    $w.Title = Add-Label '' 24 20 376 34
    $w.Title.Font = New-Object Drawing.Font('Segoe UI',14,[Drawing.FontStyle]::Bold)
    $w.Description = Add-Label '' 24 62 592 50
    $w.Network = Add-Label 'Checking direct campus access...' 24 116 592 44
    $w.Direct = New-Object Windows.Forms.RadioButton
    $w.Direct.Text = 'Use direct access (do not start school VPN)'; $w.Direct.Location = New-Object Drawing.Point(24,166)
    $w.Direct.Size = New-Object Drawing.Size(592,28); $w.Direct.Checked = -not $Connect
    $form.Controls.Add($w.Direct)
    $w.Connect = New-Object Windows.Forms.RadioButton
    $w.Connect.Text = 'Connect school VPN for off-campus access'; $w.Connect.Location = New-Object Drawing.Point(24,198)
    $w.Connect.Size = New-Object Drawing.Size(592,28); $w.Connect.Checked = [bool]$Connect
    $form.Controls.Add($w.Connect)
    $w.InstallLabel = Add-Label '' 24 238 450 54
    $w.Download = New-Object Windows.Forms.Button
    $w.Download.Text = 'Download'; $w.Download.Location = New-Object Drawing.Point(492,238)
    $w.Download.Size = New-Object Drawing.Size(124,36); $form.Controls.Add($w.Download)
    $w.UserLabel = Add-Label '' 24 304 126 28
    $w.User = New-Object Windows.Forms.TextBox
    $w.User.Location = New-Object Drawing.Point(156,300); $w.User.Size = New-Object Drawing.Size(460,28)
    if ($saved) { $w.User.Text = $saved.UserName }
    $saved = $null
    $form.Controls.Add($w.User)
    $w.PasswordLabel = Add-Label '' 24 344 126 28
    $w.Password = New-Object Windows.Forms.TextBox
    $w.Password.Location = New-Object Drawing.Point(156,340); $w.Password.Size = New-Object Drawing.Size(460,28)
    $w.Password.UseSystemPasswordChar = $true; $form.Controls.Add($w.Password)
    $w.SavedHint = Add-Label '' 156 378 460 48
    $w.CodeLabel = Add-Label '' 24 436 126 28
    $w.Code = New-Object Windows.Forms.TextBox
    $w.Code.Location = New-Object Drawing.Point(156,432); $w.Code.Size = New-Object Drawing.Size(316,28)
    $w.Code.Enabled = $false; $w.Code.MaxLength = 32; $form.Controls.Add($w.Code)
    $w.SendCode = New-Object Windows.Forms.Button
    $w.SendCode.Text = 'Submit code'; $w.SendCode.Location = New-Object Drawing.Point(492,430)
    $w.SendCode.Size = New-Object Drawing.Size(124,32); $w.SendCode.Enabled = $false; $form.Controls.Add($w.SendCode)
    $w.Status = Add-Label 'Direct access without school VPN is a normal choice on campus.' 24 490 592 70
    $w.Status.BorderStyle = 'FixedSingle'; $w.Status.Padding = New-Object Windows.Forms.Padding(8)
    $w.Start = New-Object Windows.Forms.Button
    $w.Start.Location = New-Object Drawing.Point(24,590); $w.Start.Size = New-Object Drawing.Size(420,42)
    $form.Controls.Add($w.Start)
    $w.Close = New-Object Windows.Forms.Button
    $w.Close.Text = 'Close'; $w.Close.Location = New-Object Drawing.Point(464,590)
    $w.Close.Size = New-Object Drawing.Size(152,42); $form.Controls.Add($w.Close)
    $form.CancelButton = $w.Close
    $w.TextBindings = @{
        Title = 'title'; Description = 'description'; Direct = 'direct_option'; Connect = 'connect_option'
        Download = 'download'; UserLabel = 'account_label'; PasswordLabel = 'password_label'
        SavedHint = 'saved_account_hint'; CodeLabel = 'code_label'; SendCode = 'submit_code'; Close = 'close'
    }
    $w.LanguageLabel = Add-Label 'Language' 416 24 76 28
    $w.LanguageChoice = New-Object Windows.Forms.ComboBox
    $w.LanguageChoice.Location = New-Object Drawing.Point(492,20)
    $w.LanguageChoice.Size = New-Object Drawing.Size(124,28)
    $w.LanguageChoice.DropDownStyle = 'DropDownList'
    [void]$w.LanguageChoice.Items.Add((Get-UiText 'language_name' 'en'))
    [void]$w.LanguageChoice.Items.Add((Get-UiText 'language_name' 'zh-CN'))
    $w.LanguageChoice.SelectedIndex = 1
    $form.Controls.Add($w.LanguageChoice)
    $w.LanguageChoice.Add_SelectedIndexChanged({
        $script:Wizard.Language = if ($script:Wizard.LanguageChoice.SelectedIndex -eq 0) { 'en' } else { 'zh-CN' }
        Update-WizardLanguage
    })
    $w.Direct.Add_CheckedChanged({ Update-WizardChoice })
    $w.Connect.Add_CheckedChanged({ Update-WizardChoice })
    $w.Download.Add_Click({ Invoke-WizardDownload })
    $w.Start.Add_Click({ Start-WizardRouting })
    $w.Close.Add_Click({ $script:Wizard.Form.Close() })
    $w.SendCode.Add_Click({
        $code = $script:Wizard.Code.Text.Trim()
        if ($code -notmatch '^[a-zA-Z0-9-]{1,32}$') { Set-WizardMessage 'code_invalid'; return }
        $next = Join-Path $script:Wizard.SessionDir 'code.next'
        [IO.File]::WriteAllText($next, $code)
        [IO.File]::Move($next, (Join-Path $script:Wizard.SessionDir 'code.txt'))
        $script:Wizard.Code.Clear()
        $script:Wizard.SendCode.Enabled = $false
    })
    $form.Add_FormClosing({
        param($sender, $eventArgs)
        $state = $script:Wizard
        if ($state.Routing -and -not $state.Routing.HasExited) {
            $eventArgs.Cancel = $true
            Set-WizardMessage 'routing_finishing'
            return
        }
        if ($state.Session -and -not $state.SessionReady) {
            [IO.File]::WriteAllText((Join-Path $state.SessionDir 'cancel'), '')
        }
        if ($state.Client) { $state.Client.CancelAsync() }
        if ($state.Http) { $state.Http.CancelPendingRequests(); $state.Http.Dispose() }
        if ($state.Timer) { $state.Timer.Stop(); $state.Timer.Dispose() }
    })
    Update-WizardChoice
    if ($BuildOnly) { return $form }
    $windowMutex = New-Object Threading.Mutex($false, 'Local\ZjuVpnWindow')
    $windowAcquired = $false
    try { $windowAcquired = $windowMutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $windowAcquired = $true }
    if (-not $windowAcquired) {
        $form.Dispose()
        $windowMutex.Dispose()
        [void][Windows.Forms.MessageBox]::Show((Get-UiText 'window_already_open' $w.Language), 'zju-vpn')
        return
    }
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.UseProxy = $false
    $w.Http = New-Object Net.Http.HttpClient($handler)
    $w.Http.Timeout = [TimeSpan]::FromSeconds(6)
    $request = New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Head, 'https://www.cc98.org/')
    $w.ProbeTask = $w.Http.SendAsync($request)
    $w.Timer = New-Object Windows.Forms.Timer
    $w.Timer.Interval = 300
    $w.Timer.Add_Tick({ Update-WizardTasks })
    $w.Timer.Start()
    try { [void]$form.ShowDialog() }
    finally {
        $w.Password.Clear(); $form.Dispose(); $script:Wizard = $null
        $windowMutex.ReleaseMutex(); $windowMutex.Dispose()
    }
}
