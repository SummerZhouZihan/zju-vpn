# Advanced usage

## Runtime requirements

The launcher uses Windows PowerShell 5.1, Windows curl.exe, an existing Clash for
Windows installation, and a Windows zju-connect executable with aTrust support.
Node.js and npm are needed for development, not daily operation.

## Startup window

Double-click `start.cmd`. The interface defaults to Simplified Chinese. Use the
Language selector in the upper-right corner to switch to English or Simplified
Chinese immediately, including while an operation is running. Account input and
connection state are preserved when switching languages.

The window offers direct access without starting school
VPN, or an explicit school VPN connection. Direct access is the default; not
starting VPN is a normal choice and does not produce a warning.

When zju-connect is missing, select Download in the same window or skip it and
use direct access. The downloader uses the pinned upstream release and SHA256 in
`config/zju-connect-release.json`. It does not replace an existing executable.
After download, select school VPN and enter the account and password in the
window. Leave the password empty to reuse saved credentials.

Browser verification may open according to the school's authentication flow.
When an SMS or other verification code is requested, enter it in the window's
verification-code field. Closing a pending login cancels that login. Closing the
window after connection leaves the VPN running in the background. Once an
operation completes, Enter selects Close; Escape also closes the window.

`login.cmd` is retained as a shortcut to the same window with VPN selected.
Direct mode does not disconnect a VPN process that is already running.

## Command line

Run from the project directory:

```powershell
# Inspect the plan without changing settings or starting processes.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start.ps1 -DryRun

# Start routing without starting school VPN or asking questions.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start.ps1 -NonInteractive -VpnMode Direct

# Unattended: connect VPN only when direct campus access is unavailable.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start.ps1 -NonInteractive -VpnMode Auto

# Explicitly connect using existing credentials and session data.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start.ps1 -NonInteractive -VpnMode Connect

# Legacy terminal login for advanced diagnostics.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\login.ps1 -ResetCredential
```

Without `-Gui` or `-NonInteractive`, the launcher asks whether to connect VPN in
the terminal. Unattended startup never downloads software or requests account
input. If authentication needs user interaction, open `start.cmd` to complete it.

Use `-Detailed` for installation paths, backup paths, and listener diagnostics.
Normal startup uses short status messages. Use `-ClashPath` and `-ClashDataDir` to
override discovery. `-ForceZjuRestart` applies when a VPN connection is requested.
Avoid running the configuration installer directly during a launcher operation.

## Local configuration and state

On first use, the launcher creates `%LOCALAPPDATA%\zju-vpn` with permissions
restricted to the current Windows user, then copies `config\zju-connect.example.toml` into
that directory as `config.toml`.

| Local file | Purpose |
| --- | --- |
| `config.toml` | Workstation VPN settings; normally leave the password empty |
| `zju-connect.credential.clixml` | Windows DPAPI-encrypted credentials |
| `client_data.json` | Sensitive saved authentication session |
| `*.log` and backup files | Private diagnostics and settings backups |
| `runtime-*/config.toml` | Temporary plaintext startup configuration |

Temporary configuration is removed after normal startup or failure handling.
A crash or power loss can leave files behind. See [SECURITY.md](SECURITY.md)
before sharing diagnostics or moving local data between computers.

Clash profiles and subscription settings remain in Clash's own data directory.
The installer saves backups there before applying changes. Those backups may
contain subscription credentials and must also remain private.

## Routing and health checks

The generated `Campus` group uses `fallback`, with `DIRECT` before `ZJUconnect`.
It checks `https://www.cc98.org/` every 60 seconds, including when the group is
idle. Keep the probe representative of an internal resource. A public university
homepage or a general Internet connectivity endpoint cannot establish campus
reachability.

The installer prepends campus rules and direct VPN-server exceptions, preserving
existing external nodes, other user rules, and DNS configuration. Previously
generated campus groups are migrated to `Campus`. A subscription parser reapplies
the routing rules on subscription refresh.

## Troubleshooting

- **Campus access works but VPN standby is unavailable:** open `start.cmd` and select school VPN to
  renew authentication before changing to an off-campus network. The launcher
  permits direct access while standby is unavailable.
- **Captcha or SMS verification is required:** use the startup window to complete authentication. Detailed startup diagnostics remain in the private
  local data directory.
- **A program bypasses Clash:** enable system proxy support in the program or
  configure its proxy explicitly. System proxy settings do not capture every
  application.
- **TUN creates a routing loop:** verify that VPN-server connections and the
  zju-connect process remain direct, and that loopback proxy connections are not
  intercepted recursively.
- **A campus hostname fails:** check DNS resolution and resource permissions.
  Success for the health-check URL does not establish access to every campus
  service.

## Optional integrations

The core launcher has no dependency on external applications. The optional
[PaperRead adapter](PAPERREAD.md) lets an existing
installation check connectivity or request startup. Its probes, JSON protocol,
and setup instructions are documented separately.
