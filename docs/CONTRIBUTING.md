# Contributing

Use English for source, filenames, comments, diagnostics, and documentation other
than README.md. Interface translations belong in resources/locales, with Unicode
escapes keeping the resource files ASCII. Do not embed translated text in source.
Keep local state outside the repository and bind proxies only to loopback addresses.

Run development commands from the project root. Use Node.js 20 or newer. Run `npm ci --ignore-scripts`, `npm test`, and on Windows
run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\startup.test.ps1`.
In CI, `CI=true` skips workstation-specific checks. Local checks need an installed
Clash for Windows and preserve active settings, credentials, and sessions.

Preserve existing subscription nodes, user rules, and DNS configuration. Keep
optional integrations separate from the core, preserving their public protocol
when changing them. Never log full subscription profiles or credentials. Test
upgrades from previous generated configurations and repeated
installation. Changes to routing should retain a direct VPN-server connection to
prevent recursive proxying.

Pull requests should describe the behavior change, verification, and relevant
limitations. Do not include generated archives, local paths, logs, or binaries.

## Real-core validation

With an existing Clash core and Country.mmdb, run the isolated fallback test:

```powershell
node .\tests\fallback-core.test.cjs <clash-core.exe> <Country.mmdb>
```

The test uses local fixture servers to exercise direct access, fallback, and
recovery. It does not use campus credentials or modify the active Clash profile.

## Source packaging

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\package.ps1
```

The output is `dist/zju-vpn-source.zip`. `public-files.json` is the release
allowlist. Public source validation must pass before packaging. The archive
preserves hidden engineering files and directory structure, and excludes local
credentials, sessions, logs, historical backups, and third-party executables.

Project source is licensed under the [MIT License](../LICENSE). Contributions
are provided under the same license. Third-party software retains its own
license; see [THIRD_PARTY.md](THIRD_PARTY.md).

See [the architecture guide](ARCHITECTURE.md) for component responsibilities
and dependency boundaries.

Run `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/wizard.test.ps1`
for download-integrity, form-state, code-submission, cancellation, and persistent
session-host checks. Authentication tests use a local synthetic executable and
credentials; they do not contact the school or use workstation account data.
