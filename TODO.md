# Pendora — Roadmap & TODO

Tracking upcoming features, tool expansions, bugfixes, and environment enhancements for the Pendora project.

---

## 🐛 Bugfixes & Active Investigations

- [ ] **Sway VM Display Auto-Rescaling**:
  - Investigate dynamic display rescaling on window drag under QEMU/SPICE virtual machines (currently defaults to fixed `1080p` in `sway/.config/sway/config`). Note: dynamic resizing was attempted (`7a77b8c`) and reverted to 1080p (`a73643d`) — document why before retrying; see README "Known Issues".

---

## 🛠️ Tooling & Upstream Additions

- [ ] **ADWS Domain Dump (r4cken fork)**:
  - Active Directory Web Services dump utility (`pipx`, same `git+https` pattern as NetExec in `pipx-lists/pipx-tools.list`).
  - Source: [https://github.com/r4cken/adwsdomaindump](https://github.com/r4cken/adwsdomaindump)
- [ ] **Nuclei**:
  - Fast, template-based vulnerability scanner by ProjectDiscovery.
  - Install as a standalone upstream binary in `upstreams/install-upstreams.sh` (same channel as naabu/rustscan).
  - Source: [https://github.com/projectdiscovery/nuclei](https://github.com/projectdiscovery/nuclei)
- [ ] **Coercer**:
  - Automatic Active Directory machine account authentication coercion utility (`pipx` — PyPI package `coercer`).
  - Source: [https://github.com/p0dalirius/coercer](https://github.com/p0dalirius/coercer)
- [ ] **Language Toolchain Gaps**:
  - Add Go toolchain (`golang`) to `pkg-lists/00-base.list` ("Runtimes, Compilers & Build Tools"); decide whether Java / Node.js are in scope for offensive tooling before adding.
- [ ] **Oh My Pi (omp)**:
  - Terminal AI coding agent with IDE tooling and shell integration.
  - Install via installer-script style in `upstreams/install-upstreams.sh` (precedent: SysReptor remote installer, devtunnel binary).
  - Source: [https://github.com/can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) (`https://omp.sh/install`)

---

## 🎨 Desktop Environment & UX Polish

- [ ] **Rofi Theme Customization**:
  - Add native Catppuccin Macchiato / Pendora colorway for Rofi launcher (`$mod+Shift+space`).
- [ ] **Noctalia Widgets & Bar Polish**:
  - Configure custom status bar items (VPN tunnel status `tun0`/`wg0`, IP address widget, system resource monitors).

---

## ⚙️ Framework & Installer Improvements

- [ ] **Container Restart-Policy Decision (SysReptor / BloodHound)**:
  - Both stacks intentionally do not auto-start after reboot. Decide: keep manual start (document it in README + TOOL_REFERENCE) or pin `restart: unless-stopped` in the generated compose files so behavior matches Portainer's documented `restart: always`.
- [ ] **SysReptor / BloodHound Start-on-Demand Documentation**:
  - Re-running `./install-upstreams.sh sysreptor` starts a stopped stack automatically; `assets/TOOL_REFERENCE.md` (dashboard table + "Manage all containers via Docker") never tells users how to start the stacks after a reboot — document the start commands.
- [ ] **Self-Check / Verification Subcommand**:
  - Add `./install.sh --verify` to test if all tools, services, and symlinks are installed and responsive (precedent: `portainer_test_deployment()`).
- [ ] **Modular Uninstall / Cleanup**:
  - Add `./install.sh --clean` or module removal option to safely un-stow configurations and purge unused cache files.
- [ ] **Air-Gapped / Offline Deployment**:
  - Support pre-cached RPMs and container tarballs for offline lab deployment.
