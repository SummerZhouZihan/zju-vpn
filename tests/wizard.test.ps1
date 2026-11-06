$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\powershell\common.ps1')
. (Join-Path $root 'src\powershell\ui.ps1')
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$fixture = Join-Path $env:TEMP ('zju-vpn-wizard-test-' + [guid]::NewGuid().ToString('N'))
$script:CampusData = Join-Path $fixture 'data'
$worker = $null
try {
    Initialize-CampusData
    $synthetic = New-Object Management.Automation.PSCredential('test-user', (ConvertTo-SecureString 'synthetic-password' -AsPlainText -Force))
    Save-ZjuCredential $synthetic
    Assert-True ((Get-ZjuCredential -Quiet).UserName -eq 'test-user') 'Saved account did not round-trip'

    # A ZIP with a path-like entry must not extract to that entry's path.
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $archivePath = Join-Path $fixture 'fixture.zip'
    $zip = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $zip.CreateEntry('../../zju-connect.exe')
        $stream = New-Object IO.StreamWriter($entry.Open())
        try { $stream.Write('fixture-binary') } finally { $stream.Dispose() }
    }
    finally { $zip.Dispose() }
    $script:TestDownload = @{ sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash }
    $script:TestExe = Join-Path $fixture 'installed\zju-connect.exe'
    function Get-ZjuDownloadInfo { return $script:TestDownload }
    function Get-ZjuExecutable { return $script:TestExe }
    Install-ZjuArchive $archivePath
    Assert-True ([IO.File]::ReadAllText($script:TestExe) -eq 'fixture-binary') 'Verified binary was not installed'
    $rejected = $false
    try { Install-ZjuArchive $archivePath } catch { $rejected = $true }
    Assert-True $rejected 'An existing executable was overwritten'
    $script:TestDownload.sha256 = '0' * 64
    $rejected = $false
    try { Install-ZjuArchive $archivePath } catch { $rejected = $true }
    Assert-True $rejected 'An unverified download was accepted'

    # Build controls without opening a window or contacting an authentication service.
    $form = Show-ZjuVpnWindow -BuildOnly
    try {
        Assert-True ($script:Wizard.Language -eq 'zh-CN') 'The interface must default to Simplified Chinese'
        Assert-True ($script:Wizard.LanguageChoice.SelectedIndex -eq 1) 'The language selector must match the default'
        Assert-True ($script:Wizard.Close.Text -eq (Get-UiText 'close' 'zh-CN')) 'The default labels were not translated'
        Assert-True $script:Wizard.Direct.Checked 'Direct access should be the default'
        Assert-True (-not $script:Wizard.Password.Enabled) 'Direct mode should not request credentials'
        Assert-True $script:Wizard.Password.UseSystemPasswordChar 'Password entry must be masked'
        $script:Wizard.Connect.Checked = $true
        Assert-True $script:Wizard.Password.Enabled 'VPN selection should enable credentials'
        $script:Wizard.User.Text = 'draft-user'
        $script:Wizard.Password.Text = 'draft-password'
        Set-WizardMessage 'download_progress' @('v-test')
        Set-WizardBusy $true
        $script:Wizard.LanguageChoice.SelectedIndex = 0
        Assert-True ($script:Wizard.Language -eq 'en') 'English selection was not applied'
        Assert-True ($script:Wizard.Close.Text -eq 'Close') 'English labels were not refreshed'
        Assert-True ($script:Wizard.Status.Text -eq 'Downloading zju-connect v-test from its upstream GitHub release...') 'The current operation was not translated'
        Assert-True $script:Wizard.Busy 'Switching language must not reset the running operation'
        Assert-True (-not $script:Wizard.Start.Enabled) 'Switching language must not reenable a busy action'
        Assert-True $script:Wizard.Connect.Checked 'Switching language changed the VPN choice'
        Assert-True ($script:Wizard.User.Text -eq 'draft-user' -and $script:Wizard.Password.Text -eq 'draft-password') 'Switching language changed account input'
        Complete-WizardOperation 'routing_ready_direct'
        $script:Wizard.LanguageChoice.SelectedIndex = 1
        Assert-True ($script:Wizard.Status.Text -eq (Get-UiText 'routing_ready_direct' 'zh-CN')) 'Completed status was not translated'
        Assert-True ($form.AcceptButton -eq $script:Wizard.Close) 'Enter must close after completion'
        Assert-True ($form.CancelButton -eq $script:Wizard.Close) 'Escape must close the window'
    }
    finally { $form.Dispose(); $script:Wizard = $null }

    # Exercise real child completion from the WinForms message loop. Polling a
    # process only from a console loop does not reproduce the lost-exit-code bug.
    $routingRoot = Join-Path $fixture 'routing-root'
    New-Item -ItemType Directory -Path (Join-Path $routingRoot 'scripts') -Force | Out-Null
    foreach ($expectedExit in @(0,7)) {
        $stub = 'param([switch]$NonInteractive,[string]$VpnMode,[int]$WaitSeconds,[switch]$SkipClash); Start-Sleep -Milliseconds 200; exit ' + $expectedExit
        [IO.File]::WriteAllText((Join-Path $routingRoot 'scripts\start.ps1'), $stub)
        $form = Show-ZjuVpnWindow -BuildOnly -SkipClash
        $script:Wizard.Root = $routingRoot
        $script:RoutingTestDeadline = (Get-Date).AddSeconds(15)
        $script:RoutingTestTimedOut = $false
        $script:RoutingTestTimer = New-Object Windows.Forms.Timer
        $script:RoutingTestTimer.Interval = 100
        $script:RoutingTestTimer.Add_Tick({
            Update-WizardTasks
            if ((Get-Date) -gt $script:RoutingTestDeadline) {
                $script:RoutingTestTimedOut = $true
                if ($script:Wizard.Routing -and -not $script:Wizard.Routing.HasExited) {
                    $script:Wizard.Routing.Kill()
                    $script:Wizard.Routing.WaitForExit()
                }
                $script:Wizard.Busy = $false
            }
            if (-not $script:Wizard.Busy) {
                $script:RoutingTestTimer.Stop()
                $script:Wizard.Form.Close()
            }
        })
        try {
            Start-WizardRouting
            $script:RoutingTestTimer.Start()
            [void]$form.ShowDialog()
            Assert-True (-not $script:RoutingTestTimedOut) 'Routing fixture did not finish'
            $expectedStatus = if ($expectedExit -eq 0) { 'routing_ready_direct' } else { 'routing_failed' }
            Assert-True ($script:Wizard.StatusKey -eq $expectedStatus) "Child exit $expectedExit was misclassified"
        }
        finally {
            $script:RoutingTestTimer.Dispose()
            $form.Dispose()
            $script:Wizard = $null
        }
    }

    $form = Show-ZjuVpnWindow -BuildOnly
    try {
        $unknown = [pscustomobject]@{HasExited = $true; ExitCode = $null}
        $unknown | Add-Member ScriptMethod WaitForExit {}
        $unknown | Add-Member ScriptMethod Dispose {}
        $script:Wizard.Routing = $unknown
        Set-WizardBusy $true
        Update-WizardTasks
        Assert-True ($script:Wizard.StatusKey -eq 'routing_result_unknown') 'An unavailable exit code must not be reported as a routing failure'
    }
    finally { $form.Dispose(); $script:Wizard = $null }

    # A local child fixture requests a code without a newline, then remains alive.
    $fakeDir = Join-Path $fixture 'fake'
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    $fakeExe = Join-Path $fakeDir 'zju-connect.exe'
    $source = @'
using System;
using System.IO;
using System.Threading;
public static class VpnFixture {
    public static void Main() {
        Console.Write("Please enter the SMS verification code: ");
        Console.Out.Flush();
        if (Console.ReadLine() != "123456") Environment.Exit(3);
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        File.WriteAllText(Path.Combine(dir, "ready"), "ready");
        while (!File.Exists(Path.Combine(dir, "stop"))) Thread.Sleep(100);
    }
}
'@
    Add-Type -TypeDefinition $source -OutputAssembly $fakeExe -OutputType ConsoleApplication
    $runnerPath = Join-Path $fixture 'run-session.ps1'
    $runner = @'
param($Root, $Data, $SessionDir, $FakeExe)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'src\powershell\common.ps1')
$script:CampusData = $Data
. (Join-Path $Root 'src\powershell\session.ps1')
$script:FixtureExe = $FakeExe
function Get-ZjuExecutable { return $script:FixtureExe }
function Test-ProxyPorts { return (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $script:FixtureExe) 'ready')) }
function Get-Listeners { return $null }
Invoke-ZjuSession -SessionDir $SessionDir -MutexName ('Local\ZjuVpnFixture-' + (Split-Path -Leaf $SessionDir))
'@
    [IO.File]::WriteAllText($runnerPath, $runner)
    function Start-FixtureWorker([string]$SessionDir) {
        New-Item -ItemType Directory -Path $SessionDir | Out-Null
        return (Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $runnerPath),
            '-Root',('"{0}"' -f $root),'-Data',('"{0}"' -f $script:CampusData),
            '-SessionDir',('"{0}"' -f $SessionDir),'-FakeExe',('"{0}"' -f $fakeExe)) `
            -RedirectStandardOutput (Join-Path $SessionDir 'out.log') -RedirectStandardError (Join-Path $SessionDir 'err.log'))
    }
    function Wait-FixtureState([string]$SessionDir, [string]$Expected) {
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $deadline) {
            $statusPath = Join-Path $SessionDir 'status.json'
            if (Test-Path -LiteralPath $statusPath) {
                try { $status = Read-ZjuSessionState $SessionDir } catch { $status = $null }
                if ($status.state -eq $Expected) { return }
                if ($status.state -eq 'failed') {
                    $diagnostic = Get-Content -LiteralPath (Join-Path $SessionDir 'vpn.log') -Encoding UTF8 -Tail 2 -ErrorAction SilentlyContinue
                    throw ('Synthetic fixture session failed: ' + ($diagnostic -join ' '))
                }
            }
            Start-Sleep -Milliseconds 100
        }
        $diagnostic = Get-Content -LiteralPath (Join-Path $SessionDir 'vpn.log') -Encoding UTF8 -Tail 3 -ErrorAction SilentlyContinue
        $workerError = Get-Content -LiteralPath (Join-Path $SessionDir 'err.log') -Encoding UTF8 -Tail 4 -ErrorAction SilentlyContinue
        throw "Session did not reach $Expected. Last state: $($status.state). Fixture output: $($diagnostic -join ' '); $($workerError -join ' ')"
    }
    $session = Join-Path $script:CampusData ('ui-session-' + [guid]::NewGuid().ToString('N'))
    $worker = Start-FixtureWorker $session
    Wait-FixtureState $session 'code_required'
    Assert-True ((Read-ZjuSessionState $session).message_key -eq 'vpn_code_required') 'Code prompt needs a translatable message identifier'
    [IO.File]::WriteAllText((Join-Path $session 'code.txt'), '123456')
    Wait-FixtureState $session 'ready'
    Assert-True ((Read-ZjuSessionState $session).message_key -eq 'vpn_connected') 'Connected status needs a translatable message identifier'
    Assert-True (-not $worker.HasExited) 'The VPN host must survive closing the UI'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $session 'code.txt'))) 'One-time code was left on disk'
    Assert-True (@(Get-ChildItem -LiteralPath $script:CampusData -Directory -Filter 'runtime-*').Count -eq 0) 'Plaintext runtime config survived readiness'
    [IO.File]::WriteAllText((Join-Path $fakeDir 'stop'), '')
    Assert-True ($worker.WaitForExit(5000)) 'Fixture host did not exit'
    $worker.Dispose(); $worker = $null
    Remove-Item -LiteralPath (Join-Path $fakeDir 'ready'),(Join-Path $fakeDir 'stop') -Force

    $session = Join-Path $script:CampusData ('ui-session-' + [guid]::NewGuid().ToString('N'))
    $worker = Start-FixtureWorker $session
    Wait-FixtureState $session 'code_required'
    [IO.File]::WriteAllText((Join-Path $session 'cancel'), '')
    Assert-True ($worker.WaitForExit(5000)) 'Cancelling must stop the pending login'
    $worker.Dispose(); $worker = $null
    Assert-True ((Get-Content -LiteralPath (Join-Path $session 'status.json') -Raw | ConvertFrom-Json).state -eq 'cancelled') 'Cancellation state was lost'
    Write-Host 'Wizard, verified download, code submission, background session, and cancellation: OK'
}
finally {
    if ($worker -and -not $worker.HasExited) { $worker | Stop-Process -Force -ErrorAction SilentlyContinue }
    if ($fakeExe) {
        Get-Process -Name 'zju-connect' -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $fakeExe } | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    # Only this verified test-owned tree can be removed.
    $absolute = [IO.Path]::GetFullPath($fixture)
    if ((Split-Path -Parent $absolute) -ne [IO.Path]::GetFullPath($env:TEMP) -or
        (Split-Path -Leaf $absolute) -notmatch '^zju-vpn-wizard-test-[a-f0-9]{32}$') { throw 'Unsafe fixture cleanup path' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
