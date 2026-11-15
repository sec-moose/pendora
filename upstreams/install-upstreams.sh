#!/usr/bin/env bash
#
# pendora - Standalone Upstream Tools Installer
# Installs security tools that require vendor packages, git cloning, or rubygems.
#

set -euo pipefail

DRY_RUN=false
ASSUME_YES=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKSUMS_FILE="${SCRIPT_DIR}/checksums.sha256"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# SEC-xx: fetch a pinned artifact and fail closed on checksum mismatch.
# Usage: fetch_and_verify <url> <name> <dest> — <name> must be keyed in checksums.sha256.
fetch_and_verify() {
    local url="$1" name="$2" dest="$3"
    if [ ! -f "$CHECKSUMS_FILE" ]; then
        log_error "Checksum manifest missing: $CHECKSUMS_FILE"
        return 1
    fi
    local hash
    hash=$(awk -v n="$name" '$2 == n { print $1; exit }' "$CHECKSUMS_FILE")
    if ! [[ "$hash" =~ ^[0-9a-f]{64}$ ]]; then
        log_error "No checksum pin found for $name in $CHECKSUMS_FILE"
        return 1
    fi
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors '$url' -o <staging>/$name"
        echo "  [DRY-RUN] printf '%s  %s' \"$hash\" \"$name\" | (cd <staging> && sha256sum -c --status -)"
        return 0
    fi
    local staging
    staging="$(mktemp -d -m 0700)" || { log_error "Could not create a staging directory for $name."; return 1; }
    # SEC-xx: guarded curl so set -e does not abort mid-download
    if ! curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors -o "$staging/$name" "$url"; then
        log_error "Download failed for $name from $url."
        rm -rf "$staging"
        return 1
    fi
    if ! printf '%s  %s\n' "$hash" "$name" | (cd "$staging" && sha256sum -c --status -); then
        log_error "Checksum verification FAILED for $name (expected $hash); refusing to install."
        rm -rf "$staging"
        return 1
    fi
    if ! mv "$staging/$name" "$dest"; then
        log_error "Could not move verified $name into place at $dest."
        rm -rf "$staging"
        return 1
    fi
    rm -rf "$staging"
    log_success "$name verified against checksums.sha256 and fetched."
}

show_help() {
    cat <<EOF
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS] [TOOL...]

${BOLD}Options:${NC}
  -h, --help      Show this help message
  -d, --dry-run   Simulate installation commands without executing
  -y, --yes       Assume yes for confirmation prompts

${BOLD}Available Upstream Tools:${NC}
  metasploit      Metasploit Framework (via Rapid7 official omnibus installer)
  burpsuite       Burp Suite Community Edition (via PortSwigger Linux installer)
  seclists        SecLists wordlist collection cloned to /usr/share/seclists
  evil-winrm      Evil-WinRM Windows remote management shell (via gem)
  zap             Zed Attack Proxy (via Flathub Flatpak)
  hack-font       Hack Nerd Font (TTF glyphs from official Nerd Fonts release)
  rustscan        RustScan modern 65k-port scanner (via GitHub release -> /usr/local/bin/rustscan)
  naabu           Naabu fast port scanner (via ProjectDiscovery -> /usr/local/bin/naabu)
  kerbrute        Kerbrute AD username enumeration (via go install -> /usr/local/bin/kerbrute)
  linpeas         linPEAS Linux priv-esc scanner (via PEASS-ng release -> /usr/local/bin/linpeas)
  winpeas         winPEAS Windows priv-esc binaries (via PEASS-ng release -> /usr/local/share/peass)
  portainer       Portainer Community Edition (management UI container on port 9443)
  sysreptor       SysReptor CE pentest reporting platform (via Docker Compose on port 8000)
  bloodhound      BloodHound Community Edition (via Docker Compose on port 8080)
  devtunnel       Microsoft Dev Tunnels CLI (secure tunneling to localhost)
  responder       Responder LLMNR/NBT-NS/mDNS poisoner (via lgandx GitHub + venv)
  all             Install all upstream tools

${BOLD}Examples:${NC}
  $(basename "$0") --dry-run metasploit
  $(basename "$0") seclists evil-winrm
  $(basename "$0") all
EOF
}

install_metasploit() {
    log_info "Installing Metasploit Framework via Rapid7 omnibus installer..."
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    # SEC-xx: the omnibus wrapper is vendored (upstreams/vendor/msfinstall.erb, captured from
    # rapid7/metasploit-omnibus commit 45946ec8c2620d7f9c97d4d5ef3f30a201c48677, 2025-06-23) and
    # hash-pinned in checksums.sha256 as msfinstall.erb - no network fetch of the wrapper itself.
    # The framework packages it installs remain Rapid7-GPG-signed.
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] cp '$SCRIPT_DIR/vendor/msfinstall.erb' '$tmp_dir/msfinstall' && chmod 755 '$tmp_dir/msfinstall'"
        echo "  [DRY-RUN] sudo sh '$tmp_dir/msfinstall'"
    else
        if ! cp "$SCRIPT_DIR/vendor/msfinstall.erb" "$tmp_dir/msfinstall"; then
            log_error "Vendored msfinstall.erb not found at $SCRIPT_DIR/vendor/msfinstall.erb."
            rm -rf "$tmp_dir"
            return 1
        fi
        chmod 755 "$tmp_dir/msfinstall"
        # SEC-xx: fail closed if the vendored wrapper no longer matches its pinned hash
        local msf_hash
        msf_hash=$(awk '$2 == "msfinstall.erb" { print $1; exit }' "$CHECKSUMS_FILE" 2>/dev/null)
        if ! [[ "$msf_hash" =~ ^[0-9a-f]{64}$ ]] || \
           ! (cd "$tmp_dir" && printf '%s  msfinstall\n' "$msf_hash" | sha256sum -c --status -); then
            log_error "Vendored msfinstall.erb does not match its checksums.sha256 pin; refusing to run it."
            rm -rf "$tmp_dir"
            return 1
        fi
        # SEC-xx: guarded so the wrapper's rc is reported and tmp_dir is always cleaned up
        local rc=0
        sudo sh "$tmp_dir/msfinstall" || rc=$?
        rm -rf "$tmp_dir"
        if [ "$rc" -ne 0 ]; then
            log_error "Metasploit omnibus installer exited with status ${rc}."
            return 1
        fi
        log_success "Metasploit installed successfully."
    fi
}

install_burpsuite() {
    log_info "Downloading Burp Suite Community Edition installer..."
    local installer_url="https://portswigger.net/burp/releases/download?product=community&version=2026.10.1&type=linux"
    local dest
    dest="$(mktemp)"
    local varfile
    varfile="$(mktemp)"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] curl -fsSL '$installer_url' -o '$dest' && chmod +x '$dest'"
        echo "  [DRY-RUN] Verify sha256 of '$dest' against checksums.sha256 (burpsuite-community-2026.10.1-linux)"
        echo "  [DRY-RUN] sudo '$dest' -q -dir /opt/BurpSuiteCommunity -overwrite -varfile '$varfile'"
        echo "  [DRY-RUN] sudo ln -sf /opt/BurpSuiteCommunity/BurpSuiteCommunity /usr/local/bin/burpsuite"
    else
        curl -fsSL "$installer_url" -o "$dest"
        # SEC-xx: fail closed on checksum mismatch before executing the downloaded installer
        local burp_hash
        burp_hash=$(awk '$2 == "burpsuite-community-2026.10.1-linux" { print $1; exit }' "$CHECKSUMS_FILE" 2>/dev/null)
        local actual_hash
        actual_hash="$(sha256sum "$dest" | awk '{print $1}')" || actual_hash=""
        if ! [[ "$burp_hash" =~ ^[0-9a-f]{64}$ ]] || [ "$actual_hash" != "$burp_hash" ]; then
            log_error "Burp Suite installer failed checksum verification (expected ${burp_hash:-none}, got $actual_hash); refusing to execute it."
            rm -f "$dest" "$varfile"
            return 1
        fi
        if head -n 1 "$dest" | grep -q "^<"; then
            log_error "PortSwigger returned an HTML error page instead of installer script."
            return 1
        fi
        chmod +x "$dest"

        # Pre-seed install4j response varfile for non-interactive automated installation
        cat > "$varfile" <<'EOF'
sys.installationDir=/opt/BurpSuiteCommunity
sys.symlinkDir=/usr/local/bin
EOF

        log_info "Running Burp Suite installer in unattended mode (-q -dir /opt/BurpSuiteCommunity -overwrite)..."
        sudo "$dest" -q -dir /opt/BurpSuiteCommunity -overwrite -varfile "$varfile"

        # Ensure launcher symlinks exist in /usr/local/bin
        if [ -f /opt/BurpSuiteCommunity/BurpSuiteCommunity ]; then
            [ ! -e /usr/local/bin/burpsuite ] && sudo ln -sf /opt/BurpSuiteCommunity/BurpSuiteCommunity /usr/local/bin/burpsuite
            [ ! -e /usr/local/bin/BurpSuiteCommunity ] && sudo ln -sf /opt/BurpSuiteCommunity/BurpSuiteCommunity /usr/local/bin/BurpSuiteCommunity
        fi

        # Clean up temporary installer and varfile
        rm -f "$dest" "$varfile"
        log_success "Burp Suite installed in unattended mode. Symlink ready at /usr/local/bin/burpsuite"
    fi
}

install_seclists() {
    local target_dir="/usr/share/seclists"
    local legacy_dir="/usr/share/seclists"
    log_info "Installing SecLists to $target_dir..."
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] [ -d $legacy_dir/.git ] && sudo mv $legacy_dir $target_dir"
        echo "  [DRY-RUN] sudo git clone --depth 1 https://github.com/danielmiessler/SecLists.git $target_dir"
        echo "  [DRY-RUN] sudo tar -xzf $target_dir/Passwords/Leaked-Databases/rockyou.txt.tar.gz -C $target_dir/Passwords/Leaked-Databases/"
    else
        # Migrate legacy installs: keep the git clone (pull --ff-only still works)
        if [ -d "$legacy_dir/.git" ] && [ ! -d "$target_dir" ]; then
            log_info "Migrating SecLists from $legacy_dir to $target_dir..."
            sudo mv "$legacy_dir" "$target_dir"
        fi
        if [ -d "$target_dir/.git" ]; then
            log_info "SecLists already exists. Pulling latest updates..."
            sudo git -C "$target_dir" pull --ff-only
        else
            sudo git clone --depth 1 https://github.com/danielmiessler/SecLists.git "$target_dir"
        fi
        if [ -f "$target_dir/Passwords/Leaked-Databases/rockyou.txt.tar.gz" ]; then
            log_info "Extracting rockyou.txt..."
            sudo tar -xzf "$target_dir/Passwords/Leaked-Databases/rockyou.txt.tar.gz" -C "$target_dir/Passwords/Leaked-Databases/"
        fi
        log_success "SecLists installed at $target_dir"
    fi
}

install_evil_winrm() {
    log_info "Installing Evil-WinRM via RubyGem..."
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo gem install evil-winrm -v 4.1"
    else
        if ! command -v gem &>/dev/null; then
            log_error "gem command not found. Ensure ruby, rubygems, ruby-devel, and readline-devel are installed."
            return 1
        fi
        # Ensure ruby.h and readline headers are installed for compiling readline-ext native gem
        if ! rpm -q ruby-devel readline-devel redhat-rpm-config &>/dev/null; then
            log_info "Installing missing ruby-devel, readline-devel, and redhat-rpm-config for native gem compilation..."
            sudo dnf install -y ruby-devel readline-devel redhat-rpm-config
        fi
        # SEC-xx: pin the gem version for reproducible installs
        sudo gem install evil-winrm -v 4.1
        log_success "Evil-WinRM installed."
    fi
}

install_zap() {
    log_info "Installing OWASP ZAP (Zed Attack Proxy) via Flatpak..."
    local target_user="${SUDO_USER:-${USER:-$(id -un)}}"
    local flatpak_cmd=(flatpak --user)
    if [ -n "${SUDO_USER:-}" ] && [ "$EUID" -eq 0 ]; then
        flatpak_cmd=(sudo -u "$SUDO_USER" flatpak --user)
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] ${flatpak_cmd[*]} remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
        echo "  [DRY-RUN] ${flatpak_cmd[*]} install -y --noninteractive flathub org.zaproxy.ZAP"
        echo "  [DRY-RUN] Create /usr/local/bin/zap launcher wrapper"
    else
        if ! command -v flatpak &>/dev/null; then
            log_info "flatpak not found. Installing flatpak via dnf..."
            sudo dnf install -y flatpak || { log_error "Failed to install flatpak"; return 1; }
        fi
        log_info "Configuring Flathub remote in user scope for ${target_user}..."
        "${flatpak_cmd[@]}" remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        log_info "Installing org.zaproxy.ZAP in user scope..."
        "${flatpak_cmd[@]}" install -y --noninteractive flathub org.zaproxy.ZAP

        # Create launcher wrapper in /usr/local/bin/zap
        local wrapper="/usr/local/bin/zap"
        sudo tee "$wrapper" >/dev/null <<'EOF'
#!/bin/sh
exec flatpak run org.zaproxy.ZAP "$@"
EOF
        sudo chmod +x "$wrapper"
        log_success "ZAP Flatpak installed successfully. Launcher ready at $wrapper"
    fi
}
install_hack_font() {
    log_info "Installing Hack Nerd Font from upstream Nerd Fonts release..."
    # SEC-xx: pinned release v3.5.1, checksum-verified via fetch_and_verify (no curl|tar pipe)
    local font_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Hack.tar.xz"
    local font_dir="/usr/local/share/fonts/HackNerdFont"
    if [ "$DRY_RUN" = true ]; then
        fetch_and_verify "$font_url" "Hack.tar.xz" "<mktemp file>" || log_warn "Hack.tar.xz could not be verified (missing manifest/pin)."
        echo "  [DRY-RUN] sudo mkdir -p '$font_dir'"
        echo "  [DRY-RUN] sudo tar -xJf <verified Hack.tar.xz> -C '$font_dir'"
        echo "  [DRY-RUN] sudo fc-cache -f"
    else
        local font_tmp
        font_tmp="$(mktemp)" || { log_error "Could not create a temp file for Hack.tar.xz."; return 1; }
        if ! fetch_and_verify "$font_url" "Hack.tar.xz" "$font_tmp"; then
            rm -f "$font_tmp"
            log_warn "Hack Nerd Font download or verification failed; not installing."
            return 1
        fi
        sudo mkdir -p "$font_dir"
        if ! sudo tar -xJf "$font_tmp" -C "$font_dir"; then
            log_warn "Extraction of Hack Nerd Font failed; not completing installation."
            rm -f "$font_tmp"
            return 1
        fi
        rm -f "$font_tmp"
        sudo fc-cache -f
        log_success "Hack Nerd Font installed to $font_dir"
    fi
}
ensure_docker_ready() {
    local target_user="${SUDO_USER:-${USER:-$(id -un)}}"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo systemctl enable --now docker"
        echo "  [DRY-RUN] sudo usermod -aG docker $target_user"
        return 0
    fi

    if ! command -v docker &>/dev/null; then
        log_error "docker command not found. Please install the Docker package list (pkg-lists/60-docker.list) first."
        return 1
    fi

    log_info "Ensuring Docker service is active and user '$target_user' is in docker group..."
    sudo systemctl enable --now docker 2>/dev/null || true
    sudo usermod -aG docker "$target_user" 2>/dev/null || true
}

portainer_write_compose_file() {
    local selinux_block=""
    if [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
        # On enforcing hosts container-selinux denies container_t -> container_runtime_t:unix_stream_socket
        # connectto (the docker.sock connect) regardless of any mount relabel; Red Hat's remedy is
        # --security-opt label=disable (bugzilla #1758227). The container holds the docker socket anyway.
        selinux_block=$'    security_opt:\n      - label:disable'
        log_info "SELinux is Enforcing: disabling SELinux labeling for the Portainer container (label:disable) - without it the Docker socket connect is denied by policy."
    fi
    sudo mkdir -p /opt/portainer
    sudo tee /opt/portainer/portainer-compose.yaml >/dev/null <<EOF || { log_error "Could not write /opt/portainer/portainer-compose.yaml."; return 1; }
services:
  portainer:
    container_name: portainer
    image: portainer/portainer-ce:lts
    restart: always
${selinux_block}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    ports:
      - 127.0.0.1:9443:9443
      # - 8000:8000  # Remove if you do not intend to use Edge Agents

volumes:
  portainer_data:
    name: portainer_data

networks:
  default:
    name: portainer_network
EOF
}

portainer_test_deployment() {
    local test_failures=0
    # The portainer image ships no shell - verify the socket mount from the host via inspect
    if sudo docker inspect portainer --format '{{range .Mounts}}{{.Destination}} {{end}}' 2>/dev/null | grep -q '/var/run/docker.sock'; then
        log_success "Docker socket is mounted into the Portainer container."
    else
        log_error "Docker socket is NOT mounted into the Portainer container."
        test_failures=$((test_failures + 1))
    fi
    local pt_version
    pt_version=$(sudo docker exec portainer /portainer --version 2>&1 | head -n 1 || true)
    if [ -n "$pt_version" ]; then
        log_info "Portainer version: ${pt_version}"
    else
        log_warn "Could not determine the Portainer version."
        test_failures=$((test_failures + 1))
    fi
    local ui_ok=false
    for _ in {1..15}; do
        if curl -ksS -o /dev/null https://127.0.0.1:9443 2>/dev/null; then
            ui_ok=true
            break
        fi
        sleep 2
    done
    if [ "$ui_ok" = true ]; then
        log_success "Portainer UI answers on https://localhost:9443."
    else
        log_error "Portainer UI did not answer on https://localhost:9443 within 30s."
        test_failures=$((test_failures + 1))
    fi
    local env_errs
    env_errs=$(sudo docker logs portainer 2>&1 | grep -icE 'cannot connect|permission denied|operation not permitted' || true)
    if [ "${env_errs:-0}" -gt 0 ]; then
        log_warn "Portainer logs contain ${env_errs} connection/permission errors:"
        sudo docker logs portainer 2>&1 | grep -iE 'cannot connect|permission denied|operation not permitted' | tail -n 3 || true
        if [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
            log_warn "SELinux is Enforcing - inspect denials with: sudo ausearch -m avc -ts recent | grep -i docker"
        fi
        test_failures=$((test_failures + 1))
    else
        log_success "No connection/permission errors in the Portainer logs (CE creates the 'local' environment when the wizard page loads - it reports 'We have connected your local environment' on success)."
    fi
    return "$test_failures"
}

install_portainer() {
    log_info "Configuring Docker service and deploying Portainer CE..."
    local creds_file="/opt/portainer/admin_setup.txt"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo mkdir -p /opt/portainer"
        echo "  [DRY-RUN] Write portainer-compose.yaml (lts image, 9443:9443; security_opt label:disable when SELinux is Enforcing)"
        echo "  [DRY-RUN] cd /opt/portainer && sudo docker compose -f portainer-compose.yaml up -d"
        echo "  [DRY-RUN] Test: socket mounted, UI on https://localhost:9443, version printed, env-connection errors checked"
        echo "  [DRY-RUN] Extract setup_token from container logs"
        echo "  [DRY-RUN] Display setup token banner and prompt user to copy before continuing"
        echo "  [DRY-RUN] Web interface: https://localhost:9443"
    else
        ensure_docker_ready || return 1

        # If Portainer container already exists, start it if stopped, show setup banner and skip re-deployment
        if sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^portainer$"; then
            if ! sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^portainer$"; then
                log_info "Portainer container exists but is stopped. Starting it..."
                sudo docker start portainer || log_warn "Could not start existing Portainer container; continuing."
            fi
            log_success "Portainer CE container is already running! Web interface: https://localhost:9443"
            # Rewrite the compose file (picks up label:disable under SELinux etc.) and refresh to the current lts digest.
            # A foreign (non-compose) container makes 'up -d' fail on the name; the running one is kept then.
            portainer_write_compose_file || true
            if sudo docker compose -f /opt/portainer/portainer-compose.yaml pull 2>/dev/null; then
                if sudo docker compose -f /opt/portainer/portainer-compose.yaml up -d 2>/dev/null; then
                    log_info "Portainer container refreshed to the current configuration."
                else
                    log_warn "Could not refresh the Portainer container (foreign or stale). To recreate it: sudo docker rm -f portainer && sudo docker compose -f /opt/portainer/portainer-compose.yaml up -d"
                fi
            fi
            portainer_test_deployment || log_warn "Portainer deployment tests reported problems above."
            local existing_token=""
            if [ -f "$creds_file" ]; then
                existing_token=$(grep -E "^Setup Token:" "$creds_file" 2>/dev/null | cut -d: -f2- | tr -d ' \r\n' || true)
            fi
            if [ -z "$existing_token" ]; then
                existing_token=$(sudo docker logs portainer 2>&1 | grep -oE "setup_token=[a-zA-Z0-9._-]+" | cut -d= -f2 | head -n 1 | tr -d '\r\n' || true)
            fi
            [ -z "$existing_token" ] && existing_token="Already initialized or check 'sudo docker logs portainer'"

            echo
            echo -e "${GREEN}${BOLD}====================================================${NC}"
            echo -e "${GREEN}${BOLD}Portainer CE Web Dashboard${NC}"
            echo -e "${GREEN}${BOLD}====================================================${NC}"
            echo -e "  Web URL:      ${BOLD}https://localhost:9443${NC}"
            echo -e "  Username:     ${BOLD}admin${NC}"
            echo -e "  Setup Token:  ${BOLD}${existing_token}${NC}"
            echo -e "${YELLOW}  ⚠️  REMINDER: Access https://localhost:9443 to complete admin setup!${NC}"
            echo -e "${GREEN}${BOLD}====================================================${NC}"
            echo
            if [ "$ASSUME_YES" = false ]; then
                read -rp "Please copy the Setup Token and URL above. Press [Enter] to continue: " _ || true
            fi
            return 0
        fi

        log_info "Writing portainer-compose.yaml to /opt/portainer..."
        portainer_write_compose_file || { log_error "Could not write /opt/portainer/portainer-compose.yaml."; return 0; }
        log_info "Deploying Portainer CE via docker compose..."
        local compose_rc=1
        local attempt
        for attempt in 1 2 3; do
            if (cd /opt/portainer && sudo docker compose -f portainer-compose.yaml up -d); then
                compose_rc=0
                break
            fi
            if [ "$attempt" -lt 3 ]; then
                log_warn "Portainer deployment failed (attempt ${attempt}/3, often a transient Docker Hub network error); retrying in 5s..."
                sleep 5
            fi
        done
        if [ "$compose_rc" -ne 0 ]; then
            log_error "Portainer deployment failed after 3 attempts (Docker Hub network error). Check connectivity and re-run 'pendora containers', or deploy manually: cd /opt/portainer && sudo docker compose -f portainer-compose.yaml up -d"
            return 0
        fi

        portainer_test_deployment || log_warn "Portainer deployment tests reported problems above."

        log_info "Waiting for Portainer CE container to initialize and generate setup token..."
        local setup_token=""
        for _ in {1..15}; do
            setup_token=$(sudo docker logs portainer 2>&1 | grep -oE "setup_token=[a-zA-Z0-9._-]+" | cut -d= -f2 | head -n 1 | tr -d '\r\n' || true)
            [ -n "$setup_token" ] && break
            sleep 1
        done
        [ -z "$setup_token" ] && setup_token="Check 'sudo docker logs portainer' for setup_token"

        # SEC-11: pre-create with restrictive mode so the credentials never appear world-readable
        sudo install -m 600 /dev/null "$creds_file" 2>/dev/null || true
        sudo tee "$creds_file" >/dev/null <<EOF || log_warn "Could not write $creds_file; the Setup Token above is still valid."
Web URL:      https://localhost:9443
Username:     admin
Setup Token:  ${setup_token}
Note:         Initial setup must be completed within 5 minutes of first launch.
EOF
        sudo chmod 600 "$creds_file" || log_warn "Could not restrict permissions on $creds_file (sudo may require re-authentication); run 'sudo chmod 600 $creds_file' manually."

        echo
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        echo -e "${GREEN}${BOLD}Portainer CE Initial Setup${NC}"
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        echo -e "  Web URL:      ${BOLD}https://localhost:9443${NC}"
        echo -e "  Username:     ${BOLD}admin${NC}"
        echo -e "  Setup Token:  ${BOLD}${setup_token}${NC}"
        echo -e "  Saved to:     ${creds_file}"
        echo -e "${YELLOW}  ⚠️  REMINDER: Complete the initial admin setup in the web UI within 5 minutes - the Setup Token above expires after that!${NC}"
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        # SEC-08: remind the user that the credentials card is a plaintext bootstrap record
        log_info "${creds_file} is a plaintext bootstrap record: move this token into a password manager and delete the file afterwards (sudo rm ${creds_file})."
        echo
        if [ "$ASSUME_YES" = false ]; then
            read -rp "Please copy the Setup Token and URL above. Press [Enter] to continue: " _ || true
        fi
        log_success "Portainer CE deployed successfully! Web interface: https://localhost:9443"
    fi
}
install_sysreptor() {
    log_info "Configuring Docker and deploying SysReptor pentest reporting platform..."
    local install_dir="/opt/sysreptor"
    local installer_script
    installer_script="$(mktemp)"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Existing stack: start via compose (/opt/sysreptor/sysreptor/deploy); fresh: download + run official installer unattended"
        echo "  [DRY-RUN] Verify installer against checksums.sha256 (sysreptor-install.sh); download + verify pinned setup.tar.gz (2026.102) and point the installer at it via file://"
        echo "  [DRY-RUN] Strip restart policies (no auto-start after reboot) and set containers to restart=no"
        echo "  [DRY-RUN] Reset the reptor password to a fresh generated value (docker compose exec app manage.py shell)"
        echo "  [DRY-RUN] Display credentials banner and prompt user to copy before continuing"
        echo "  [DRY-RUN] SysReptor interface will be accessible at: http://localhost:8000"
    else
        ensure_docker_ready || return 1
        local creds_file="${install_dir}/admin_credentials.txt"

        # Detect a previous SysReptor deployment by its compose file or containers (the compose
        # project is named after the deploy directory, so container names are not stable).
        local deploy_compose="/opt/sysreptor/sysreptor/deploy/docker-compose.yml"
        local preexisting=false
        if [ -f "$deploy_compose" ] || sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qi "sysreptor"; then
            preexisting=true
        fi
        if [ "$preexisting" = true ]; then
            if (cd /opt/sysreptor/sysreptor/deploy && sudo docker compose ps -q app 2>/dev/null | grep -q .); then
                log_success "SysReptor container stack is already running! Web interface: http://localhost:8000"
            else
                log_info "SysReptor stack exists but is stopped - starting it..."
                if (cd /opt/sysreptor/sysreptor/deploy && sudo docker compose up -d) 2>/dev/null; then
                    log_success "SysReptor container stack started! Web interface: http://localhost:8000"
                else
                    log_warn "Could not start the SysReptor stack; start it via Portainer or: cd /opt/sysreptor/sysreptor/deploy && sudo docker compose up -d"
                fi
            fi
        else
            sudo mkdir -p "$install_dir"
            log_info "Downloading official SysReptor installer..."
            curl -fsSL https://docs.sysreptor.com/install.sh -o "$installer_script"
            # SEC-xx: fail closed if the fetched installer no longer matches the manifest snapshot
            local sr_installer_hash
            sr_installer_hash=$(awk '$2 == "sysreptor-install.sh" { print $1; exit }' "$CHECKSUMS_FILE" 2>/dev/null)
            local sr_installer_actual
            sr_installer_actual="$(sha256sum "$installer_script" | awk '{print $1}')" || sr_installer_actual=""
            if ! [[ "$sr_installer_hash" =~ ^[0-9a-f]{64}$ ]] || [ "$sr_installer_actual" != "$sr_installer_hash" ]; then
                log_error "SysReptor installer failed checksum verification against checksums.sha256 (sysreptor-install.sh); refusing to continue."
                rm -f "$installer_script"
                return 0
            fi
            # SEC-xx: pre-download the setup bundle from a pinned release and verify it, so the
            # installer consumes a known-good tarball via file:// instead of an unpinned latest URL
            log_info "Downloading pinned SysReptor setup bundle (2026.102)..."
            if ! curl -fsSL --retry 3 \
                https://github.com/Syslifters/sysreptor/releases/download/2026.102/setup.tar.gz \
                -o "$install_dir/setup.tar.gz"; then
                log_error "Could not download the pinned SysReptor setup bundle; skipping SysReptor deployment."
                rm -f "$installer_script"
                return 0
            fi
            local sr_bundle_actual
            sr_bundle_actual="$(sha256sum "$install_dir/setup.tar.gz" | awk '{print $1}')" || sr_bundle_actual=""
            if [ "$sr_bundle_actual" != "fc7f4b3c0856930ca294a968132f44cbe5530421232511863b7916c33dfba2f7" ]; then
                log_error "SysReptor setup.tar.gz failed checksum verification; refusing to continue."
                rm -f "$install_dir/setup.tar.gz" "$installer_script"
                return 0
            fi
            # Point the installer at the verified local bundle (it runs with cwd=$install_dir).
            # Expand the path here - $install_dir is not defined inside the installer's shell.
            sed -i "s|download_url=https://github.com/syslifters/sysreptor/releases/latest/download/setup.tar.gz|download_url=\"file://${install_dir}/setup.tar.gz\"|g" "$installer_script"
            if ! grep -q 'download_url="file://' "$installer_script"; then
                log_error "Could not redirect the SysReptor installer to the verified local setup bundle; refusing to continue."
                rm -f "$install_dir/setup.tar.gz" "$installer_script"
                return 0
            fi
            chmod +x "$installer_script"

            # Neutralize all interactive read prompts with automated responses to avoid infinite while-loops
            sed -i 's/read -p "Copy your password.*/CONFIRM="y"/g' "$installer_script"
            sed -i 's/read -p "Backup your encryption.*/CONFIRM="y"/g' "$installer_script"
            sed -i 's/read -p "Enable automatic updates.*/CONFIRM_AUTOUPDATE="n"/g' "$installer_script"
            sed -i 's/read -p "Encrypt files and database.*/SYSREPTOR_ENCRYPT="n"/g' "$installer_script"
            sed -i 's/read -p .*/true/g' "$installer_script"

            log_info "Running SysReptor installer in unattended mode (Community Edition)..."

            local installer_rc=0
            # SEC-11: pre-create with restrictive mode so the installer log never appears world-readable
            sudo install -m 600 /dev/null "${install_dir}/admin_install.log" 2>/dev/null || true
            (
                cd "$install_dir"
                sudo env \
                    SYSREPTOR_LICENSE="" \
                    SYSREPTOR_ENCRYPT="n" \
                    CONFIRM="y" \
                    CONFIRM_AUTOUPDATE="n" \
                    bash "$installer_script"
            ) 2>&1 | sudo tee "${install_dir}/admin_install.log" || installer_rc=$?
            sudo chmod 600 "${install_dir}/admin_install.log" 2>/dev/null || true

            # Cleanup temporary installer script
            rm -f "$installer_script"

            if [ "$installer_rc" -ne 0 ]; then
                log_error "SysReptor installer exited with status ${installer_rc} (see ${install_dir}/admin_install.log). If this is 'Old SysReptor volumes exist', the previous data is preserved - removing the old volumes deletes that data; resolve and re-run."
                return 0
            fi
        fi

        # SysReptor must not auto-start after reboot: strip restart policies from the compose
        # files and set the containers to restart=no (the stack is started on demand instead)
        sudo sed -i '/^[[:space:]]*restart:[[:space:]]/d' \
            /opt/sysreptor/sysreptor/deploy/docker-compose.yml \
            /opt/sysreptor/sysreptor/deploy/caddy/docker-compose.yml \
            /opt/sysreptor/sysreptor/deploy/languagetool/docker-compose.yml 2>/dev/null || true
        # SEC-05: pin the published port to loopback. The vendor layout publishes via the app
        # service as ${BIND_PORT:-127.0.0.1:8000:8000} in sysreptor/docker-compose.yml (caddy is
        # only used for FQDN/TLS deployments and is not enabled here). The vendor default is
        # already loopback - pin it in deploy/.env so a future default change cannot silently
        # expose the reporting UI.
        local sr_env="/opt/sysreptor/sysreptor/deploy/.env"
        if ! sudo grep -q '^BIND_PORT=' "$sr_env" 2>/dev/null; then
            echo 'BIND_PORT="127.0.0.1:8000:8000"' | sudo tee -a "$sr_env" >/dev/null 2>&1 || true
        fi
        # Effective check: complain only if a SysReptor container is actually published on all
        # interfaces (recreate once to apply the pin if so); a stopped stack is not an error.
        if sudo docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -Ei 'sysreptor' | grep -qE '0\.0\.0\.0:8000|\[::\]:8000'; then
            log_info "SysReptor port 8000 is published on all interfaces - recreating the stack to apply the loopback binding..."
            (cd /opt/sysreptor/sysreptor/deploy && sudo docker compose up -d 2>/dev/null) || true
        fi
        if sudo docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -Ei 'sysreptor' | grep -qE '0\.0\.0\.0:8000|\[::\]:8000'; then
            log_error 'SysReptor port 8000 is STILL published on all interfaces (check: sudo docker ps --format "{{.Names}} {{.Ports}}")'
        fi
        sudo docker update --restart=no $(cd /opt/sysreptor/sysreptor/deploy 2>/dev/null && sudo docker compose ps -q 2>/dev/null) 2>/dev/null || true

        # Reset the reptor password to a fresh generated value so the banner always shows working
        # cleartext credentials (the installer prints its generated password only once, and older
        # credentials files may no longer contain a valid password)
        local new_pw
        new_pw="$(openssl rand -base64 20 | tr -d '\r\n=')"
        local reset_ok=false
        local attempt
        for attempt in 1 2 3 4 5; do
            if (cd /opt/sysreptor/sysreptor/deploy && sudo docker compose exec -T app python3 manage.py shell -c "from django.contrib.auth import get_user_model; from django.contrib.auth.hashers import make_password; u = get_user_model().objects.filter(username='reptor').first(); u.password = make_password('${new_pw}'); u.save(); print('PASSWORD-RESET-OK')") 2>/dev/null | grep -q "PASSWORD-RESET-OK"; then
                reset_ok=true
                break
            fi
            sleep 3
        done
        if [ "$reset_ok" = true ]; then
            # SEC-11: pre-create with restrictive mode so the credentials never appear world-readable
            sudo install -m 600 /dev/null "$creds_file" 2>/dev/null || true
            printf 'Web URL:   http://localhost:8000\nUsername:  reptor\nPassword:  %s\n' "${new_pw}" | sudo tee "$creds_file" >/dev/null || log_warn "Could not write $creds_file."
            sudo chmod 600 "$creds_file" 2>/dev/null || true
        else
            new_pw="(could not reset automatically - see ${install_dir}/admin_install.log for the installer's original password, or reset with: cd /opt/sysreptor/sysreptor/deploy && sudo docker compose exec app python3 manage.py changepassword reptor)"
        fi


        echo
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        echo -e "${GREEN}${BOLD}SysReptor Credentials${NC}"
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        echo -e "  Web URL:   ${BOLD}http://localhost:8000${NC}"
        echo -e "  Username:  ${BOLD}reptor${NC}"
        echo -e "  Password:  ${BOLD}${new_pw}${NC}"
        echo -e "  Saved to:  ${creds_file}"
        echo -e "${YELLOW}  ⚠️  REMINDER: Please change this password on first login!${NC}"
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        # SEC-08: remind the user that the credentials card is a plaintext bootstrap record
        log_info "${creds_file} is a plaintext bootstrap record: move these credentials into a password manager and delete the file afterwards (sudo rm ${creds_file})."
        echo
        if [ "$ASSUME_YES" = false ]; then
            read -rp "Please copy your username and password above. Press [Enter] to continue: " _ || true
        fi
        log_success "SysReptor deployment completed! Web interface: http://localhost:8000"
    fi
}
install_bloodhound() {
    log_info "Configuring Docker and deploying BloodHound Community Edition (CE)..."
    local install_dir="/opt/bloodhound"
    local creds_file="${install_dir}/admin_credentials.txt"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo mkdir -p '$install_dir'"
        echo "  [DRY-RUN] Download docker-compose.yml from SpecterOps/BloodHound examples to '$install_dir'"
        echo "  [DRY-RUN] Write bloodhound.config.json with a generated initial admin password and enable its compose mount"
        echo "  [DRY-RUN] cd '$install_dir' && sudo docker compose up -d"
        echo "  [DRY-RUN] Wait for http://localhost:8080 to answer, then display the credentials banner"
        echo "  [DRY-RUN] BloodHound CE interface will be accessible at: http://localhost:8080"
        echo "  [DRY-RUN] Stack and volumes fully manageable in Portainer at: https://localhost:9443"
    else
        ensure_docker_ready || return 1

        # Single converging path: every run deploys/refreshes the stack and resets the admin
        # password to a fresh generated value, so the banner credentials always work - even when
        # data volumes predate this deployment (bhe_recreate_default_admin=true makes the app
        # re-create the default admin with the config password on startup).

        sudo mkdir -p "$install_dir"
        if [ ! -f "$install_dir/docker-compose.yml" ]; then
            log_info "Downloading official BloodHound CE docker-compose.yml to $install_dir..."
            # SEC-xx: pin the compose file to release tag v9.9.2 instead of the moving main branch
            sudo curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors -o "$install_dir/docker-compose.yml" \
                https://raw.githubusercontent.com/SpecterOps/BloodHound/v9.9.2/examples/docker-compose/docker-compose.yml \
                || { log_error "Could not download the BloodHound CE compose file; skipping BloodHound CE deployment."; return 0; }
        fi

        # Fresh admin password on EVERY run; bhe_recreate_default_admin=true makes the container
        # re-create the default admin with that password on startup. Each run invalidates the
        # previous generated password (change it in the UI if you want it to stick across runs).
        local initial_pw
        initial_pw="$(openssl rand -base64 20 | tr -d '\r\n=')"
        log_info "Writing bloodhound.config.json + .env (admin password is reset to a fresh value on every run)..."
        # SEC-11: pre-create with restrictive mode so the credentials never appear world-readable
        sudo install -m 600 /dev/null "$install_dir/bloodhound.config.json" 2>/dev/null || true
        sudo tee "$install_dir/bloodhound.config.json" >/dev/null <<EOF || { log_error "Could not write $install_dir/bloodhound.config.json."; return 0; }
{
  "version": 1,
  "bind_addr": "0.0.0.0:8080",
  "metrics_port": ":2112",
  "root_url": "http://127.0.0.1:8080/",
  "work_dir": "/opt/bloodhound/work",
  "log_level": "INFO",
  "graph_driver": "neo4j",
  "tls": {
    "cert_file": "",
    "key_file": ""
  },
  "collectors_base_path": "/etc/bloodhound/collectors",
  "default_password": "$initial_pw",
  "default_admin": {
    "enabled": true,
    "principal_name": "admin",
    "password": "$initial_pw",
    "first_name": "BloodHound",
    "last_name": "Admin",
    "email_address": "admin@example.com"
  }
}
EOF
        # SEC-11: pre-create with restrictive mode so the credentials never appear world-readable
        sudo install -m 600 /dev/null "$install_dir/.env" 2>/dev/null || true
        printf 'bhe_recreate_default_admin=true\n' | sudo tee "$install_dir/.env" >/dev/null || { log_error "Could not write $install_dir/.env."; return 0; }
        sudo chmod 600 "$install_dir/bloodhound.config.json" "$install_dir/.env" 2>/dev/null || true
        sudo chmod 755 "$install_dir" 2>/dev/null || true

        # SEC-04b: pin the published port to loopback. Upstream changed the compose to
        # ${BLOODHOUND_HOST:-127.0.0.1}:${BLOODHOUND_PORT:-8080}:8080 - the old literal
        # '8080:8080' no longer exists, so a literal sed is a silent no-op. Pin
        # BLOODHOUND_HOST explicitly in .env (the --force-recreate below applies it).
        if ! sudo grep -q '^BLOODHOUND_HOST=' "$install_dir/.env" 2>/dev/null; then
            echo 'BLOODHOUND_HOST=127.0.0.1' | sudo tee -a "$install_dir/.env" >/dev/null 2>&1 || true
        fi

        # Enable the commented-out config mount in the compose file (idempotent)
        sudo sed -i 's|^    # volumes:$|    volumes:|; s|^    #   - \./bloodhound\.config\.json:/bloodhound\.config\.json:ro$|      - ./bloodhound.config.json:/bloodhound.config.json:ro|' "$install_dir/docker-compose.yml"
        if ! sudo grep -q '^      - \./bloodhound\.config\.json:/bloodhound\.config\.json:ro$' "$install_dir/docker-compose.yml"; then
            log_error "Could not enable the bloodhound.config.json mount in docker-compose.yml; skipping BloodHound CE deployment."
            return 0
        fi

        log_info "Starting BloodHound CE stack via docker compose (image pulls may take a few minutes)..."
        local compose_rc=1
        local attempt
        for attempt in 1 2 3; do
            if (cd "$install_dir" && sudo docker compose up -d --force-recreate); then
                compose_rc=0
                break
            fi
            if [ "$attempt" -lt 3 ]; then
                log_warn "docker compose up failed (attempt ${attempt}/3, often a transient Docker Hub network error); retrying in 5s..."
                sleep 5
            fi
        done
        if [ "$compose_rc" -ne 0 ]; then
            log_error "BloodHound CE deployment failed after 3 attempts (image pull network error). Check connectivity and re-run 'pendora containers', or deploy manually: cd $install_dir && sudo docker compose up -d --force-recreate"
            return 0
        fi

        # SEC-04b: effective check - fail loudly only if BloodHound is actually published on
        # all interfaces (the pin above plus --force-recreate should make this impossible)
        if sudo docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -i 'bloodhound' | grep -qE '0\.0\.0\.0:8080|\[::\]:8080'; then
            log_error 'BloodHound port 8080 is published on ALL interfaces (check: sudo docker ps --format "{{.Names}} {{.Ports}}")'
        fi

        # Wait for the UI to answer (initial graph analysis can take ~1 minute; exit 137 = out of memory)
        log_info "Waiting for the BloodHound UI to answer on http://localhost:8080..."
        local ui_up=false
        for _ in {1..45}; do
            if curl -fsS -o /dev/null http://127.0.0.1:8080 2>/dev/null; then
                ui_up=true
                break
            fi
            sleep 2
        done
        if [ "$ui_up" = true ]; then
            log_success "BloodHound UI is answering on http://localhost:8080."
        else
            log_warn "BloodHound UI did not answer within 90 seconds."
        fi
        log_info "BloodHound CE container status:"
        sudo docker ps -a --filter "name=bloodhound" --format '  {{.Names}}: {{.Status}}' 2>/dev/null || true
        log_info "If the UI is unreachable, inspect: cd $install_dir && sudo docker compose logs bloodhound --tail 50 (exit 137 = out of memory; 8GB RAM required)"

        local parsed_user="admin"
        local parsed_pw="$initial_pw"

        # Save credentials to /opt/bloodhound/admin_credentials.txt
        # SEC-11: pre-create with restrictive mode so the credentials never appear world-readable
        sudo install -m 600 /dev/null "$creds_file" 2>/dev/null || true
        sudo tee "$creds_file" >/dev/null <<EOF || log_warn "Could not write $creds_file; the credentials above are still valid."
Web URL:   http://localhost:8080
Username:  ${parsed_user}
Password:  ${parsed_pw}
EOF
        sudo chmod 600 "$creds_file" || log_warn "Could not restrict permissions on $creds_file (sudo may require re-authentication); run 'sudo chmod 600 $creds_file' manually."

        echo
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        echo -e "${GREEN}${BOLD}BloodHound CE Credentials${NC}"
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        echo -e "  Web URL:   ${BOLD}http://localhost:8080${NC}"
        echo -e "  Username:  ${BOLD}${parsed_user}${NC}"
        echo -e "  Password:  ${BOLD}${parsed_pw}${NC}"
        echo -e "  Saved to:  ${creds_file}"
        echo -e "${YELLOW}  ⚠️  REMINDER: You must change this password on first login!${NC}"
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        # SEC-08: remind the user that the credentials card is a plaintext bootstrap record
        log_info "${creds_file} is a plaintext bootstrap record: move these credentials into a password manager and delete the file afterwards (sudo rm ${creds_file})."
        echo
        if [ "$ASSUME_YES" = false ]; then
            read -rp "Please copy your username and password above. Press [Enter] to continue: " _ || true
        fi

        log_success "BloodHound CE deployed successfully! Web interface: http://localhost:8080"
        log_info "BloodHound stack and volumes are fully manageable in Portainer (https://localhost:9443)."
    fi
}
install_devtunnel() {
    log_info "Installing Microsoft Dev Tunnels CLI (devtunnel)..."
    local dest="/usr/local/bin/devtunnel"
    # SEC-xx: pin the versioned CLI asset instead of the aka.ms latest redirect
    local download_url="https://tunnelsassetsprod.blob.core.windows.net/cli/1.0.2115+e16833f284/linux-x64-devtunnel"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] curl -fL --progress-bar '$download_url' -o <mktemp dir>/devtunnel"
        echo "  [DRY-RUN] Verify sha256 against checksums.sha256 (devtunnel-linux-x64)"
        echo "  [DRY-RUN] sudo install -m 755 <tmp>/devtunnel '$dest'"
    else
        log_info "Downloading devtunnel binary (~60 MB)..."
        local tmp_dir
        tmp_dir="$(mktemp -d)"
        # SEC-xx: guarded curl so a download failure cleans up tmp_dir instead of aborting under set -e
        if ! curl -fsSL --progress-bar "$download_url" -o "$tmp_dir/devtunnel"; then
            log_error "Download failed for devtunnel from $download_url."
            rm -rf "$tmp_dir"
            return 1
        fi
        # SEC-xx: fail closed on checksum mismatch before installing the binary
        local dt_hash
        dt_hash=$(awk '$2 == "devtunnel-linux-x64" { print $1; exit }' "$CHECKSUMS_FILE" 2>/dev/null)
        local dt_actual
        dt_actual="$(sha256sum "$tmp_dir/devtunnel" | awk '{print $1}')" || dt_actual=""
        if ! [[ "$dt_hash" =~ ^[0-9a-f]{64}$ ]] || [ "$dt_actual" != "$dt_hash" ]; then
            log_error "devtunnel failed checksum verification (expected ${dt_hash:-none}, got $dt_actual); refusing to install."
            rm -rf "$tmp_dir"
            return 1
        fi
        sudo install -m 755 "$tmp_dir/devtunnel" "$dest"
        rm -rf "$tmp_dir"
        log_success "Microsoft Dev Tunnels installed to $dest"
    fi
}
install_responder() {
    log_info "Installing Responder (LLMNR, NBT-NS, and mDNS poisoner)..."
    local install_dir="/opt/responder"
    local wrapper="/usr/local/bin/responder"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo git clone https://github.com/lgandx/Responder.git $install_dir"
        echo "  [DRY-RUN] sudo python3 -m venv $install_dir/venv"
        echo "  [DRY-RUN] sudo $install_dir/venv/bin/pip install -r $install_dir/requirements.txt"
        echo "  [DRY-RUN] Create launcher wrapper at $wrapper"
    else
        if ! command -v python3 &>/dev/null || ! rpm -q python3-devel gcc &>/dev/null; then
            log_info "Ensuring python3, python3-devel, and gcc are installed for Responder dependencies..."
            sudo dnf install -y python3 python3-devel gcc || true
        fi
        sudo mkdir -p /opt
        if [ -d "$install_dir/.git" ]; then
            log_info "Responder already exists. Pulling latest updates..."
            sudo git -C "$install_dir" pull --ff-only || true
        else
            sudo git clone https://github.com/lgandx/Responder.git "$install_dir"
        fi
        log_info "Setting up Python virtual environment for Responder..."
        sudo python3 -m venv "$install_dir/venv"
        sudo "$install_dir/venv/bin/pip" install --upgrade pip
        sudo "$install_dir/venv/bin/pip" install -r "$install_dir/requirements.txt"

        # Create launcher wrapper in /usr/local/bin/responder
        sudo tee "$wrapper" >/dev/null <<'EOF'
#!/bin/sh
exec sudo /opt/responder/venv/bin/python /opt/responder/Responder.py "$@"
EOF
        sudo chmod +x "$wrapper"
        log_success "Responder installed successfully! Launcher ready at $wrapper"
    fi
}
install_rustscan() {
    log_info "Installing RustScan modern fast port scanner..."
    local dest="/usr/local/bin/rustscan"
    local download_url="https://github.com/bee-san/RustScan/releases/download/2.4.1/x86_64-linux-rustscan.tar.gz.zip"
    local temp_dir
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] stage in a private mktemp -d directory: curl -fsSL '$download_url' -o rustscan.zip; verify sha256 (x86_64-linux-rustscan.tar.gz.zip); unzip; tar -xzf"
        echo "  [DRY-RUN] sudo install -m 755 rustscan '$dest'"
    else
        temp_dir="$(mktemp -d)"
        trap 'rm -rf "$temp_dir"' EXIT
        log_info "Downloading RustScan release archive..."
        curl -fsSL "$download_url" -o "$temp_dir/rustscan.zip"
        # SEC-xx: fail closed on checksum mismatch before extracting the archive
        local rs_hash
        rs_hash=$(awk '$2 == "x86_64-linux-rustscan.tar.gz.zip" { print $1; exit }' "$CHECKSUMS_FILE" 2>/dev/null)
        local rs_actual
        rs_actual="$(sha256sum "$temp_dir/rustscan.zip" | awk '{print $1}')" || rs_actual=""
        if ! [[ "$rs_hash" =~ ^[0-9a-f]{64}$ ]] || [ "$rs_actual" != "$rs_hash" ]; then
            log_error "RustScan archive failed checksum verification (expected ${rs_hash:-none}, got $rs_actual); refusing to install."
            rm -rf "$temp_dir"
            return 1
        fi
        unzip -q -o "$temp_dir/rustscan.zip" -d "$temp_dir"
        tar -xzf "$temp_dir/x86_64-linux-rustscan.tar.gz" -C "$temp_dir"
        sudo install -m 755 "$temp_dir/rustscan" "$dest"
        rm -rf "$temp_dir"
        trap - EXIT
        log_success "RustScan installed successfully to $dest"
    fi
}

install_naabu() {
    log_info "Installing Naabu fast port scanner (ProjectDiscovery)..."
    local dest="/usr/local/bin/naabu"
    local download_url="https://github.com/projectdiscovery/naabu/releases/download/v2.7.0/naabu_2.7.0_linux_amd64.zip"
    local temp_dir
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] stage in a private mktemp -d directory: curl -fsSL '$download_url' -o naabu.zip; verify sha256 (naabu_2.7.0_linux_amd64.zip); unzip naabu"
        echo "  [DRY-RUN] sudo install -m 755 naabu '$dest'"
    else
        temp_dir="$(mktemp -d)"
        trap 'rm -rf "$temp_dir"' EXIT
        log_info "Downloading Naabu release archive..."
        curl -fsSL "$download_url" -o "$temp_dir/naabu.zip"
        # SEC-xx: fail closed on checksum mismatch before extracting the archive
        local nb_hash
        nb_hash=$(awk '$2 == "naabu_2.7.0_linux_amd64.zip" { print $1; exit }' "$CHECKSUMS_FILE" 2>/dev/null)
        local nb_actual
        nb_actual="$(sha256sum "$temp_dir/naabu.zip" | awk '{print $1}')" || nb_actual=""
        if ! [[ "$nb_hash" =~ ^[0-9a-f]{64}$ ]] || [ "$nb_actual" != "$nb_hash" ]; then
            log_error "Naabu archive failed checksum verification (expected ${nb_hash:-none}, got $nb_actual); refusing to install."
            rm -rf "$temp_dir"
            return 1
        fi
        unzip -q -o "$temp_dir/naabu.zip" naabu -d "$temp_dir"
        sudo install -m 755 "$temp_dir/naabu" "$dest"
        rm -rf "$temp_dir"
        trap - EXIT
        log_success "Naabu installed successfully to $dest"
    fi
}

install_linpeas() {
    log_info "Installing linPEAS Linux privilege escalation scanner (PEASS-ng)..."
    local dest="/usr/local/bin/linpeas"
    local download_url="https://github.com/PEASS-ng/PEASS-ng/releases/download/20261115-ba4890df/linpeas.sh"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] curl -fsSL '$download_url' -o linpeas.sh; verify sha256 (linpeas.sh)"
        echo "  [DRY-RUN] sudo install -m 755 linpeas.sh '$dest'"
    else
        local temp_dir
        temp_dir="$(mktemp -d)"
        trap 'rm -rf "$temp_dir"' EXIT
        log_info "Downloading linpeas.sh release script..."
        curl -fsSL "$download_url" -o "$temp_dir/linpeas.sh"
        # SEC-xx: fail closed on checksum mismatch before installing the script
        local lp_hash
        lp_hash=$(awk '$2 == "linpeas.sh" { print $1; exit }' "$CHECKSUMS_FILE" 2>/dev/null)
        local lp_actual
        lp_actual="$(sha256sum "$temp_dir/linpeas.sh" | awk '{print $1}')" || lp_actual=""
        if ! [[ "$lp_hash" =~ ^[0-9a-f]{64}$ ]] || [ "$lp_actual" != "$lp_hash" ]; then
            log_error "linpeas.sh failed checksum verification (expected ${lp_hash:-none}, got $lp_actual); refusing to install."
            rm -rf "$temp_dir"
            return 1
        fi
        sudo install -m 755 "$temp_dir/linpeas.sh" "$dest"
        rm -rf "$temp_dir"
        trap - EXIT
        log_success "linPEAS installed successfully to $dest (run on Linux targets)"
    fi
}

install_winpeas() {
    log_info "Installing winPEAS Windows privilege escalation binaries (PEASS-ng)..."
    local dest_dir="/usr/local/share/peass"
    local download_url="https://github.com/PEASS-ng/PEASS-ng/releases/download/20261115-ba4890df/winPEASany.exe"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo mkdir -p '$dest_dir'"
        echo "  [DRY-RUN] curl -fsSL '$download_url' -o winPEASany.exe; verify sha256 (winPEASany.exe)"
        echo "  [DRY-RUN] sudo install -m 644 winPEASany.exe '$dest_dir/winPEASany.exe'"
    else
        local temp_dir
        temp_dir="$(mktemp -d)"
        trap 'rm -rf "$temp_dir"' EXIT
        sudo mkdir -p "$dest_dir"
        log_info "Downloading winPEASany.exe release binary..."
        curl -fsSL "$download_url" -o "$temp_dir/winPEASany.exe"
        # SEC-xx: fail closed on checksum mismatch before installing the binary
        local wp_hash
        wp_hash=$(awk '$2 == "winPEASany.exe" { print $1; exit }' "$CHECKSUMS_FILE" 2>/dev/null)
        local wp_actual
        wp_actual="$(sha256sum "$temp_dir/winPEASany.exe" | awk '{print $1}')" || wp_actual=""
        if ! [[ "$wp_hash" =~ ^[0-9a-f]{64}$ ]] || [ "$wp_actual" != "$wp_hash" ]; then
            log_error "winPEASany.exe failed checksum verification (expected ${wp_hash:-none}, got $wp_actual); refusing to install."
            rm -rf "$temp_dir"
            return 1
        fi
        sudo install -m 644 "$temp_dir/winPEASany.exe" "$dest_dir/winPEASany.exe"
        rm -rf "$temp_dir"
        trap - EXIT
        log_success "winPEAS installed successfully to $dest_dir/winPEASany.exe (transfer to Windows targets)"
    fi
}








install_kerbrute() {
    log_info "Installing Kerbrute Kerberos username enumeration tool (Go build)..."
    local dest="/usr/local/bin/kerbrute"
    local module="github.com/ropnop/kerbrute@v1.0.3" # SEC-xx: pin the module version instead of @latest
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Ensure the Go toolchain (golang, pkg-lists/00-base.list): sudo dnf install -y golang"
        echo "  [DRY-RUN] GOBIN=<mktemp dir> go install -ldflags '-s -w' $module"
        echo "  [DRY-RUN] sudo install -m 755 <mktemp dir>/kerbrute '$dest'"
    else
        if ! command -v go &>/dev/null; then
            if rpm -q golang &>/dev/null; then
                log_error "The golang RPM is installed but 'go' is not on PATH."
                return 1
            fi
            log_info "Installing the Go toolchain via dnf..."
            sudo dnf install -y golang || { log_error "Failed to install golang. Install pkg-lists/00-base.list first, then re-run."; return 1; }
        fi
        local temp_dir
        temp_dir="$(mktemp -d)"
        trap 'rm -rf "$temp_dir"' EXIT
        log_info "Building kerbrute from source via 'go install'..."
        GOBIN="$temp_dir" GOPATH="${GOPATH:-$HOME/go}" go install -ldflags "-s -w" "$module"
        if [ ! -x "$temp_dir/kerbrute" ]; then
            log_error "'go install' did not produce a kerbrute binary."
            return 1
        fi
        sudo install -m 755 "$temp_dir/kerbrute" "$dest"
        rm -rf "$temp_dir"
        trap - EXIT
        log_success "Kerbrute installed successfully to $dest"
    fi
}

# Parse options
TOOLS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            ASSUME_YES=true
            shift
            ;;
        *)
            TOOLS+=("$1")
            shift
            ;;
    esac
done

if [ ${#TOOLS[@]} -eq 0 ]; then
    show_help
    exit 0
fi

if [[ " ${TOOLS[*]} " =~ " all " ]]; then
    # hack-font excluded from 'all' (audit M7): the Hack Nerd Font ships via the
    # official source-foundry-hack-fonts RPM in pkg-lists/00-base.list on every
    # profile; the explicit 'hack-font' target remains available opt-in.
    TOOLS=("metasploit" "burpsuite" "seclists" "evil-winrm" "zap" "rustscan" "naabu" "kerbrute" "linpeas" "winpeas" "portainer" "sysreptor" "bloodhound" "devtunnel" "responder")
elif [[ " ${TOOLS[*]} " =~ " containers " ]] || [[ " ${TOOLS[*]} " =~ " docker " ]]; then
    TOOLS=("portainer" "sysreptor" "bloodhound")
fi
echo -e "${BOLD}Pendora - Standalone Upstream Tool Installation${NC}"
echo "========================================================"
log_info "Selected tools: ${TOOLS[*]}"

if [ "$ASSUME_YES" = false ] && [ "$DRY_RUN" = false ]; then
    read -rp "Proceed with installation? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { log_warn "Aborted by user."; exit 0; }
fi

declare -a FAILED_TOOLS=()

for tool in "${TOOLS[@]}"; do
    case "$tool" in
        metasploit)
            install_metasploit || FAILED_TOOLS+=("metasploit")
            ;;
        burpsuite)
            install_burpsuite || FAILED_TOOLS+=("burpsuite")
            ;;
        seclists)
            install_seclists || FAILED_TOOLS+=("seclists")
            ;;
        evil-winrm)
            install_evil_winrm || FAILED_TOOLS+=("evil-winrm")
            ;;
        zap)
            install_zap || FAILED_TOOLS+=("zap")
            ;;
        hack-font|font)
            install_hack_font || FAILED_TOOLS+=("hack-font")
            ;;
        rustscan)
            install_rustscan || FAILED_TOOLS+=("rustscan")
            ;;
        naabu)
            install_naabu || FAILED_TOOLS+=("naabu")
            ;;
        kerbrute)
            install_kerbrute || FAILED_TOOLS+=("kerbrute")
            ;;
        linpeas)
            install_linpeas || FAILED_TOOLS+=("linpeas")
            ;;
        winpeas)
            install_winpeas || FAILED_TOOLS+=("winpeas")
            ;;
        portainer)
            install_portainer || FAILED_TOOLS+=("portainer")
            ;;
        sysreptor)
            install_sysreptor || FAILED_TOOLS+=("sysreptor")
            ;;
        bloodhound)
            install_bloodhound || FAILED_TOOLS+=("bloodhound")
            ;;
        devtunnel|devtunnels)
            install_devtunnel || FAILED_TOOLS+=("devtunnel")
            ;;
        responder)
            install_responder || FAILED_TOOLS+=("responder")
            ;;
        *)
            log_error "Unknown tool: $tool"
            FAILED_TOOLS+=("$tool")
            ;;
    esac
done

if [ ${#FAILED_TOOLS[@]} -gt 0 ]; then
    log_error "The following upstream tool(s) encountered errors: ${FAILED_TOOLS[*]}"
    exit 1
fi

log_success "All requested upstream tools processed successfully."
