# Pendora — Roadmap & TODO

Tracking upcoming features, tool expansions, bugfixes, and environment enhancements for the Pendora project.

---

## 🐛 Bugfixes & Active Investigations

- [x] **Sway VM Display Auto-Rescaling**:
  - Resolved (investigation): with the `output * resolution 1920x1080` pin in `sway/.config/sway/config` commented out, Sway adopts the QEMU/SPICE viewer window size at session start (virtio-gpu). History: the first attempt (`7a77b8c`) was reverted to fixed 1080p (`a73643d`) over the 1024×768 fallback this unpins.
  - Limitation (by design of virtio-gpu without blob): live resize does NOT propagate — the guest reads the mode only at display-pipeline start, so later host window resizes are ignored.
  - Follow-up (hypervisor-side): enable `blob='true'` on the virtio video model (QEMU ≥ 6.1) for true dynamic scanout; a `<resolution x='1920' y='1080'/>` subelement additionally pins the boot mode to counter the 1024×768 fallback. Guest config stays unpinned.
- [x] **SPICE Clipboard Bridge & User-Session De-duplication**:
  - Resolved: `sway/.config/sway/config` no longer `exec`s the bridge; the systemd user unit is the single lifecycle mechanism, enabled bus-free via `sway-session.target.wants` at install time (headless-safe) and started by `sway-session.target` on login. The script-level `flock` singleton remains as a belt-and-suspenders guard.

---

## 🧪 Testing & Quality Assurance

- [ ] **Thorough Testing of Included Tools and Configurations**:
  - Comprehensive testing of native Fedora RPM binaries in `$PATH` (e.g. `nmap`, `tcpdump`, `wireshark`, `ffuf`, `hydra`, `john`).
  - Functional validation of all 11 pipx offensive utilities (`netexec`, `impacket-*` symlinks, `/usr/local/bin/impacket` launcher, `certipy-ad`, `bloodhound-ce`, `sqlmap`).
  - Operational testing of standalone upstream CLI wrappers and wordlists (`rustscan`, `naabu`, `devtunnel`, `responder`, `msfconsole`, `/usr/share/wordlists/seclists`).
  - Validation of Sway desktop configuration, window manager hotkeys (`$mod+t`, `$mod+Shift+Arrows`), Noctalia bar widgets, SPICE host/guest clipboard bridge, and Neovim LazyVim plugin bootstrap.
- [ ] **Automated Post-Install Verification Harness (`./install.sh --test` / `--verify`)**:
  - Implement an automated health-check suite and CLI subcommand that verifies all RPM binaries, smoke-tests all 11 pipx offensive tools, validates `/usr/local/bin` wrappers, and checks HTTP health across the three local container ports (`127.0.0.1:9443`, `8000`, `8080`).
---

## 🛠️ Tooling & Upstream Additions

- [ ] **Noctalia Greeter — Official Fedora Packaging Watch**:
  - `--server` builds noctalia-greeter from the pinned upstream tag (`GREETER_TAG` in `install.sh`, currently `v1.7.0`) because it is not yet in the official Fedora repositories. When an official `noctalia-greeter` package lands: add it to `pkg-lists/70-sway.list`, delete `install_noctalia_greeter` and its build-dependency block, and keep only the greetd configuration.
  - Source: [https://github.com/noctalia-dev/noctalia-greeter](https://github.com/noctalia-dev/noctalia-greeter)
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
- [x] **SysReptor / BloodHound Start-on-Demand Documentation**:
  - Re-running `./install-upstreams.sh sysreptor` starts a stopped stack automatically; `assets/TOOL_REFERENCE.md` (dashboard table + "Manage all containers via Docker") now documents the post-reboot start commands (`docker compose up -d`) alongside the log commands.
- [ ] **Cryptographic Checksum Verification (SHA-256) for Standalone Downloads**:
  - Pin known SHA-256 release hashes (or fetch official `.sha256` sums) for GitHub release binaries (`rustscan`, `naabu`, `Hack Nerd Font`), Microsoft Dev Tunnels, and SysReptor installer before deploying to `/usr/local/bin` or executing under `sudo`.
- [ ] **Modular Uninstall / Cleanup**:
  - Add `./install.sh --clean` or module removal option to safely un-stow configurations and purge unused cache files.
- [ ] **Air-Gapped / Offline Deployment**:
  - Support pre-cached RPMs and container tarballs for offline lab deployment.
