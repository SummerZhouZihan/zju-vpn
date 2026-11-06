# Third-party software

This source package does not bundle zju-connect or Clash binaries.

- zju-connect: https://github.com/Mythologyli/zju-connect (AGPL-3.0).
  The startup window offers an optional download from the pinned upstream
  release in `config/zju-connect-release.json`, verified by SHA256 before
  installation. Manual installation at `zju-connect-windows-386/zju-connect.exe`
  remains supported. The directory is ignored by Git and
  excluded from release archives. Existing workstation validation used v1.1.1.
- Clash for Windows: this installer targets an existing installation and reuses
  its bundled YAML parser. It does not install, redistribute, or update the
  client. Its original distribution is discontinued; compatibility with other
  clients requires a separate installer integration.
- yaml: https://github.com/eemeli/yaml (ISC), pinned as a development dependency
  in package-lock.json. Runtime installation does not require npm.

Refer to the upstream repositories and distributions for complete licenses and
notices. Do not infer licensing or authenticity from a downloaded filename.
