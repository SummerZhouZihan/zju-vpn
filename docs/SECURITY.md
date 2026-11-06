# Security policy

Do not disclose passwords, session data, subscription URLs, access tokens,
private keys, or unredacted logs in issues or pull requests.

Report vulnerabilities through the repository's private vulnerability reporting
feature when enabled. If it is unavailable, ask the maintainer for a private
reporting channel without posting exploit details or sensitive files publicly.

Local configuration, credentials, sessions, logs, and migration archives are
stored under `%LOCALAPPDATA%\zju-vpn`, outside the source tree. The directory is
restricted to the current Windows user. Passwords use Windows DPAPI; temporary
plaintext configuration is removed after startup. A process crash or power loss
can leave temporary configuration behind. DPAPI does not protect against
malicious software running as the same user or an administrator.

Keep proxy listeners on loopback. The Clash installer backs up configuration
inside Clash's own data directory; those backups can contain subscription
credentials and must remain private. Do not publish the local data directory,
Clash profiles, third-party binaries, or the historical migration archive.

Release packaging uses an explicit allowlist and validates public source files.
Before publication, review the staged diff and scan the complete Git history for
secrets. `.gitignore` cannot remove secrets already committed. Rotate exposed
credentials and sessions before cleaning repository history.

This project does not distribute zju-connect or Clash. Obtain them from their
upstream projects, review their licenses, and keep them patched. The launcher
uses a per-user-session mutex to prevent overlapping startups. Do not run the
configuration installer directly during a startup.

The startup window downloads zju-connect only after the user selects Download.
The release URL is restricted to the upstream GitHub repository, and a pinned
SHA256 is checked before installing the executable. Only the executable entry
is copied from the ZIP; archive paths are never extracted. Existing executables
are not overwritten. The source archive still excludes third-party binaries.

Verification codes pass through a private one-time file, removed when consumed
or when the session ends. After a successful graphical login, a hidden session
host remains running to manage the VPN's input and private logs. Closing the
startup window cancels pending authentication but preserves a ready connection.
No password or verification code is placed in command-line arguments.
