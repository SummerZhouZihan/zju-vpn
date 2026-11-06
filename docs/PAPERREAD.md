# Optional PaperRead adapter

This document describes the optional adapter at
`integrations/paperread/network.ps1` for an existing PaperRead installation. It is not PaperRead application code and is not required for
zju-vpn startup or routing. No PaperRead Python package or service is installed
or launched by the core project.

The adapter was retained for compatibility with a workstation that uses
PaperRead. It lets that external application check connectivity or request a
noninteractive zju-vpn startup. All PaperRead-specific probes and JSON protocol
handling belong here rather than in the core launcher.

## Usage

Run from the zju-vpn project directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\integrations\paperread\network.ps1 check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\integrations\paperread\network.ps1 prepare
```

In PaperRead's private configuration, set `network.command` to the PowerShell
command and the adapter's absolute path. PaperRead appends the action argument.
Update the configured path whenever this project or adapter moves. This adapter
does not modify PaperRead configuration itself.

`check` verifies the Clash listener and three HTTPS endpoints. It does not require
the zju-connect listener when direct routing is sufficient. `prepare` invokes the
noninteractive core launcher when necessary, then checks again. Use `-ProxyUrl`
for a different loopback HTTP proxy address.

## Protocol and limitations

Standard output is a single protocol 1 JSON object. Check names remain
`campus_idp`, `carsi`, and `public_metadata`. Status values are `ready`,
`not_ready`, `attention_required`, and `provider_error`. Detailed preparation
output stays in the private `paperread-network.last.log` file under
`%LOCALAPPDATA%\zju-vpn`.

`ready` means these probes succeeded. It does not confirm institutional sign-in,
subscription entitlements, or connectivity to every internal resource. Browser
authentication and resource permissions are handled by the external application
and the institution.
