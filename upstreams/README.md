# Standalone Upstream Installers

This directory contains deployment scripts and documentation for security tools, containers, and prerequisites not distributed directly as native Fedora RPMs.

## Tools Covered

| Tool | Source / Method | Port / Access | Description |
|---|---|---|---|
| **Metasploit** | Rapid7 Omnibus Installer | CLI (`msfconsole`) | Industry standard penetration testing framework |
| **Burp Suite** | PortSwigger Linux Installer | GUI (`burpsuite`) | Web application security testing and interception proxy |
| **SecLists** | GitHub Git Clone | `/usr/share/seclists` | Security tester's companion wordlists & dictionaries |
| **Evil-WinRM** | RubyGem (`gem install`) | CLI (`evil-winrm`) | Ultimate WinRM shell for Windows penetration testing |
| **OWASP ZAP** | Flathub Flatpak | GUI (`zap`) | Open source web application vulnerability scanner |
| **Hack Nerd Font** | GitHub Release (`ryanoasis/nerd-fonts`) | System Fonts | Monospace font with full icons for terminal & prompt |
| **RustScan** | GitHub Release (`bee-san/RustScan`) | CLI (`/usr/local/bin/rustscan`) | Ultra-fast 65k-port scanner piped directly to Nmap |
| **Naabu** | GitHub Release (`projectdiscovery/naabu`) | CLI (`/usr/local/bin/naabu`) | Fast TCP SYN/CONNECT port scanner (ProjectDiscovery) |
| **Kerbrute** | Go Install (`go install github.com/ropnop/kerbrute@v1.0.3`) | CLI (`/usr/local/bin/kerbrute`) | Kerberos username enumeration & brute-forcing for Active Directory |
| **linPEAS** | GitHub Release (`PEASS-ng/PEASS-ng`) | CLI (`/usr/local/bin/linpeas`) | Linux local privilege escalation & security assessment scanner |
| **winPEAS** | GitHub Release (`PEASS-ng/PEASS-ng`) | Binaries (`/usr/local/share/peass`) | Windows local privilege escalation scanners (`winPEASany.exe`, transfer to targets) |
| **Portainer CE** | Docker Container | `https://localhost:9443` | Container management web interface |
| **SysReptor** | Docker Compose Installer | `http://localhost:8000` | Pentest reporting and finding documentation platform |
| **BloodHound CE** | Docker Compose (official SpecterOps compose file) | `http://localhost:8080` | Active Directory attack path analysis & visualization (Portainer manageable) |
| **Dev Tunnels** | Microsoft Official (`aka.ms/TunnelsCliDownload`) | CLI (`devtunnel`) | Microsoft Dev Tunnels CLI for secure tunneling and remote port forwarding |
| **Responder** | GitHub Git Clone (`lgandx/Responder`) + Venv | CLI (`responder`) | LLMNR, NBT-NS, and mDNS poisoner and credential harvester |

## Security & Transparency Notes

**SysReptor — data-at-rest encryption & auto-updates disclosure**: Pendora runs the official SysReptor installer unattended with `SYSREPTOR_ENCRYPT=n`, so SysReptor files and its database are **not encrypted at rest** (no ENCRYPTION_KEYS are generated; anyone with access to the VM's Docker volumes can read stored findings data — acceptable for an isolated lab VM, but enable encryption in deploy/app.env before storing client-confidential material). Automatic updates are declined (`CONFIRM_AUTOUPDATE=n`), so SysReptor only changes when you re-run the installer or follow the vendor's manual update procedure (https://docs.sysreptor.com/setup/updates/). All installer prompts are auto-answered by Pendora (Community Edition license, no telemetry consent changes).

**Pinned artifacts**: binary downloads and installer scripts are pinned and SHA-256-verified against `upstreams/checksums.sha256` (fail-closed). Entries marked 'recorded at pin time' use TOFU (trust-on-first-use) hashes where the vendor publishes no checksums; review the diff on the release page before rotating those pins.

## Usage

```bash
# Dry run check for all upstreams
./install-upstreams.sh --dry-run all

# Install specific tools
./install-upstreams.sh portainer sysreptor bloodhound devtunnel responder

# Install all upstream tools non-interactively
./install-upstreams.sh --yes all
```
