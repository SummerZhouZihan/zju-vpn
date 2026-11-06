# Architecture

zju-vpn is a Windows launcher and routing configuration tool. It uses small
PowerShell components for workstation operations and JavaScript for Clash YAML
transformation. It does not implement the VPN protocol itself.

## Source layout

```text
start.cmd                         Daily entry point
login.cmd                         Interactive login entry point
scripts/                          Command-line orchestration and packaging
src/powershell/                   Reusable Windows operations
  common.ps1                      Bootstrap and component imports
  environment.ps1                 Private data directory and permissions
  network.ps1                     Reachability and listener checks
  credentials.ps1                 DPAPI and temporary runtime configuration
  clash.ps1                       Clash discovery, configuration, and startup
  vpn.ps1                         Unattended zju-connect lifecycle
  download.ps1                    Pinned download verification and installation
  session.ps1                     Authentication I/O and background VPN host
  ui.ps1                          Single-window startup and account setup
  localization.ps1                Resource loading and message formatting
src/clash/
  parser.cjs                      Pure routing configuration transformation
  configure.cjs                   CFW file I/O, validation, backup, and rollback
config/                           Public configuration templates
resources/locales/                English and escaped Simplified Chinese text
integrations/paperread/            Optional external-client adapter
tests/                            Parser, startup, source, and real-core checks
docs/                             User and developer documentation
```

## Dependency boundaries

The batch entry points invoke scripts. Scripts load reusable PowerShell
components, passing startup options explicitly. The JavaScript parser receives
configuration and a YAML implementation and returns transformed configuration;
it does not read workstation state.

The CFW adapter owns profile discovery, core validation, backups, and rollback.
Credentials and session files stay outside the repository. Local paths are
resolved from the source location, not the caller's current working directory.

Optional adapters depend on the core launcher. The core launcher never imports
or invokes an optional adapter. Removing the PaperRead integration therefore
does not affect daily startup, campus routing, or external proxy access.

## Why keep PowerShell components lightweight?

These components group existing functions by responsibility rather than adding a
class hierarchy or a service framework. The target runtime remains Windows
PowerShell 5.1. Shared configuration paths are initialized in common.ps1, while
components define functions and perform no startup work merely by being loaded.

## Verification

The tests cover pure parser behavior, existing-configuration upgrades, repeated
installation, synthetic credential handling, and DryRun state preservation. An
isolated real-core test verifies direct access, standby selection, and recovery.
Public source validation checks the release allowlist and source policy. See
[CONTRIBUTING.md](CONTRIBUTING.md) for commands.

## Interactive startup

The graphical window launches routing setup as a child operation, then starts a
private VPN session host only when the user requests school VPN. The host owns
the VPN process and its redirected streams, allowing browser verification and
code entry while keeping a connected process alive after the UI closes. Session
status is written atomically; readers allow file replacement. The host reads raw
pipe chunks so prompts without a newline are not delayed by text buffering.

The unattended entry point remains available for integrations. Direct mode does
not attempt authentication; Auto connects only when direct access is unavailable.
User-facing logs omit installation and backup details unless Detailed is enabled.

## Interface languages

The window defaults to zh-CN and supports live switching to en. Source code uses
stable resource keys. Resource files remain ASCII through JSON Unicode escapes.
Background sessions include message_key alongside English diagnostic text, so
the window can translate current status without restarting the operation. Input
fields, enabled states, and the completion default button are not recreated when
the language changes.
