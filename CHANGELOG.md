# Changelog

## 0.3.1 — polish

- Add `uninstall.ps1`
- Add GitHub Actions CI for unit tests
- Centralize version string; improve README / install UX
- Keep jump-host login as the supported model (port-forward tunnels removed in 0.3.0)

## 0.3.0

- Remove port-forward tunnel feature; jump login via `--jump` only
- Open-source release (MIT)

## 0.2.0

- Rename, edit with password, status, remote commands
- DPAPI password storage + SSH_ASKPASS auto-fill

## 0.1.0

- Initial host CRUD, connect, jump ProxyCommand
