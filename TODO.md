# Pendora — Roadmap & TODO

Tracking upcoming features, tool expansions, bugfixes, and environment enhancements for the Pendora project.

---

## 🐛 Bugfixes & Active Investigations

- [ ] **Portainer CE Deployment**:
  - Debug and resolve initialization failure during upstream installation (`upstreams/install-upstreams.sh`).
  - Ensure Portainer runs reliably alongside SysReptor and BloodHound CE.
- [ ] **Sway VM Display Auto-Rescaling**:
  - Investigate dynamic display rescaling on window drag under QEMU/SPICE virtual machines (currently defaults to fixed 1080p).
- [ ] **Impacket `ping` PATH Collision**:
  - Impacket's pipx install symlinks raw-socket `ping` and `ping6` into `~/.local/bin/`, shadowing system ping when `~/.local/bin` is first in PATH. Add post-install cleanup or `.zshrc` alias.

---

## 🛠️ Tooling & Upstream Additions

- [ ] **ADWS Domain Dump (r4cken fork)**:
  - Active Directory Web Services dump utility (`pipx`).
  - Source: [https://github.com/r4cken/adwsdomaindump](https://github.com/r4cken/adwsdomaindump)
- [ ] **Nuclei**:
  - Fast, template-based vulnerability scanner by ProjectDiscovery.
  - Source: [https://github.com/projectdiscovery/nuclei](https://github.com/projectdiscovery/nuclei)
- [ ] **Coercer**:
  - Automatic Active Directory machine account authentication coercion utility.
  - Source: [https://github.com/p0dalirius/coercer](https://github.com/p0dalirius/coercer)
- [ ] **Programming Language Libraries**:
  - Common development and offensive tooling libraries/headers across primary languages.
- [ ] **Oh My Pi (omp)**:
  - Terminal AI coding agent with IDE tooling and shell integration.
  - Source: [https://github.com/can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) (`https://omp.sh/install`)

---

## 🎨 Desktop Environment & UX Polish

- [ ] **Rofi Theme Customization**:
  - Add native Catppuccin Macchiato / Pendora colorway for Rofi launcher (`$mod+Shift+space`).
- [ ] **Noctalia Widgets & Bar Polish**:
  - Configure custom status bar items (VPN tunnel status `tun0`/`wg0`, IP address widget, system resource monitors).

---

## ⚙️ Framework & Installer Improvements

- [ ] **Minimal vs. Full Installation Profiles**:
  - Provide distinct installation modes: a minimal/streamlined profile for essentials and basics only, and a comprehensive full profile that installs every available tool and upstream integration.
- [ ] **Self-Check / Verification Subcommand**:
  - Add `./install.sh --verify` to test if all tools, services, and symlinks are installed and responsive.
- [ ] **Modular Uninstall / Cleanup**:
  - Add `./install.sh --clean` or module removal option to safely un-stow configurations and purge unused cache files.
- [ ] **Air-Gapped / Offline Deployment**:
  - Support pre-cached RPMs and container tarballs for offline lab deployment.
