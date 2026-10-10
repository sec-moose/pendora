#!/usr/bin/env bash
#
# pendora - Standalone Upstream Tools Installer
# Installs security tools that require vendor packages, git cloning, or rubygems.
#

set -euo pipefail

DRY_RUN=false
ASSUME_YES=false

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
  seclists        SecLists wordlist collection cloned to /usr/share/wordlists/seclists
  evil-winrm      Evil-WinRM Windows remote management shell (via gem)
  zap             Zed Attack Proxy (via Flathub Flatpak)
  hack-font       Hack Nerd Font (TTF glyphs from official Nerd Fonts release)
  rustscan        RustScan modern 65k-port scanner (via GitHub release -> /usr/local/bin/rustscan)
  naabu           Naabu fast port scanner (via ProjectDiscovery -> /usr/local/bin/naabu)
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
    local cmd="curl -fsSL https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb -o '$tmp_dir/msfinstall' && chmod 755 '$tmp_dir/msfinstall' && sudo '$tmp_dir/msfinstall'; rc=\$?; rm -rf '$tmp_dir'; exit \$rc"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] $cmd"
    else
        bash -c "$cmd"
        log_success "Metasploit installed successfully."
    fi
}

install_burpsuite() {
    log_info "Downloading Burp Suite Community Edition installer..."
    local installer_url="https://portswigger.net/burp/releases/download?product=community&type=linux"
    local dest
    dest="$(mktemp)"
    local varfile
    varfile="$(mktemp)"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] curl -fsSL '$installer_url' -o '$dest' && chmod +x '$dest'"
        echo "  [DRY-RUN] sudo '$dest' -q -dir /opt/BurpSuiteCommunity -overwrite -varfile '$varfile'"
        echo "  [DRY-RUN] sudo ln -sf /opt/BurpSuiteCommunity/BurpSuiteCommunity /usr/local/bin/burpsuite"
    else
        curl -fsSL "$installer_url" -o "$dest"
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
    log_info "Installing SecLists to /usr/share/wordlists/seclists..."
    local target_dir="/usr/share/wordlists/seclists"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo mkdir -p /usr/share/wordlists"
        echo "  [DRY-RUN] sudo git clone --depth 1 https://github.com/danielmiessler/SecLists.git $target_dir"
        echo "  [DRY-RUN] sudo tar -xzf $target_dir/Passwords/Leaked-Databases/rockyou.txt.tar.gz -C $target_dir/Passwords/Leaked-Databases/"
    else
        sudo mkdir -p /usr/share/wordlists
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
        echo "  [DRY-RUN] sudo gem install evil-winrm"
    else
        if ! command -v gem &>/dev/null; then
            log_error "gem command not found. Ensure ruby, rubygems, ruby-devel, and readline-devel are installed."
            return 1
        fi
        # Ensure ruby.h and readline headers are installed for compiling readline-ext native gem
        if ! rpm -q ruby-devel readline-devel &>/dev/null; then
            log_info "Installing missing ruby-devel and readline-devel for native gem compilation..."
            sudo dnf install -y ruby-devel readline-devel
        fi
        sudo gem install evil-winrm
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
    local font_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.tar.xz"
    local font_dir="/usr/local/share/fonts/HackNerdFont"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo mkdir -p '$font_dir'"
        echo "  [DRY-RUN] curl -fsSL '$font_url' | sudo tar -xJ -C '$font_dir'"
        echo "  [DRY-RUN] sudo fc-cache -f"
    else
        sudo mkdir -p "$font_dir"
        curl -fsSL "$font_url" | sudo tar -xJ -C "$font_dir"
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
      - 9443:9443
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
        echo "  [DRY-RUN] Write portainer-compose.yaml (lts image, 9443:9443; socket relabeled :z when SELinux is Enforcing)"
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
            # Rewrite the compose file (picks up SELinux :z etc.) and refresh to the current lts digest.
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
            read -rp "Please copy the Setup Token and URL above. Press [Enter] to continue: " _
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
        echo -e "${YELLOW}  ⚠️  REMINDER: Copy the Setup Token above to unlock initial admin setup at https://localhost:9443!${NC}"
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        echo
        read -rp "Please copy the Setup Token and URL above. Press [Enter] to continue: " _
        log_success "Portainer CE deployed successfully! Web interface: https://localhost:9443"
    fi
}
install_sysreptor() {
    log_info "Configuring Docker and deploying SysReptor pentest reporting platform..."
    local install_dir="/opt/sysreptor"
    local installer_script
    installer_script="$(mktemp)"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo mkdir -p '$install_dir'"
        echo "  [DRY-RUN] sed -i 's/read -p \"Copy your password.*/CONFIRM=\"y\"/g' '$installer_script'"
        echo "  [DRY-RUN] sed -i 's/read -p .*/true/g' '$installer_script'"
        echo "  [DRY-RUN] cd '$install_dir' && sudo env SYSREPTOR_ENCRYPT='n' CONFIRM='y' CONFIRM_AUTOUPDATE='n' bash '$installer_script'"
        echo "  [DRY-RUN] Display credentials banner and prompt user to copy before continuing"
        echo "  [DRY-RUN] SysReptor interface will be accessible at: http://localhost:8000"
    else
        ensure_docker_ready || return 1
        local creds_file="${install_dir}/admin_credentials.txt"

        # If SysReptor container stack is already running, show credentials if available and skip re-installation
        if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^sysreptor-app"; then
            log_success "SysReptor container stack is already running! Web interface: http://localhost:8000"
            if [ -f "$creds_file" ]; then
                local existing_pw
                existing_pw=$(grep -E "^Password:" "$creds_file" 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d '\r\n' || true)
                if [ -n "$existing_pw" ]; then
                    echo
                    echo -e "${GREEN}${BOLD}====================================================${NC}"
                    echo -e "${GREEN}${BOLD}SysReptor Credentials${NC}"
                    echo -e "${GREEN}${BOLD}====================================================${NC}"
                    echo -e "  Web URL:   ${BOLD}http://localhost:8000${NC}"
                    echo -e "  Username:  ${BOLD}reptor${NC}"
                    echo -e "  Password:  ${BOLD}${existing_pw}${NC}"
                    echo -e "  Saved to:  ${creds_file}"
                    echo -e "${YELLOW}  ⚠️  REMINDER: Please change this password on first login!${NC}"
                    echo -e "${GREEN}${BOLD}====================================================${NC}"
                    echo
                    read -rp "Please copy your username and password above. Press [Enter] to continue: " _
                fi
            fi
            return 0
        fi

        sudo mkdir -p "$install_dir"
        log_info "Downloading official SysReptor installer..."
        curl -fsSL https://docs.sysreptor.com/install.sh -o "$installer_script"
        chmod +x "$installer_script"

        # Neutralize all interactive read prompts with automated responses to avoid infinite while-loops
        sed -i 's/read -p "Copy your password.*/CONFIRM="y"/g' "$installer_script"
        sed -i 's/read -p "Backup your encryption.*/CONFIRM="y"/g' "$installer_script"
        sed -i 's/read -p "Enable automatic updates.*/CONFIRM_AUTOUPDATE="n"/g' "$installer_script"
        sed -i 's/read -p "Encrypt files and database.*/SYSREPTOR_ENCRYPT="n"/g' "$installer_script"
        sed -i 's/read -p .*/true/g' "$installer_script"

        log_info "Running SysReptor installer in unattended mode (Community Edition)..."

        local installer_rc=0
        (
            cd "$install_dir"
            sudo env \
                SYSREPTOR_LICENSE="" \
                SYSREPTOR_ENCRYPT="n" \
                CONFIRM="y" \
                CONFIRM_AUTOUPDATE="n" \
                bash "$installer_script"
        ) 2>&1 | sudo tee "$creds_file" || installer_rc=$?
        if [ "$installer_rc" -ne 0 ]; then
            log_warn "SysReptor installer exited with status ${installer_rc}; deployment may be incomplete (see output above and $creds_file)."
        fi
        sudo chmod 600 "$creds_file" || log_warn "Could not restrict permissions on $creds_file (sudo may require re-authentication); run 'sudo chmod 600 $creds_file' manually."

        # Cleanup temporary installer script
        rm -f "$installer_script"

        # Extract generated superuser credentials
        local generated_pw
        generated_pw=$(grep -E "^Password:" "$creds_file" 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d '\r\n' || true)
        [ -z "$generated_pw" ] && generated_pw="Check $creds_file"

        echo
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        echo -e "${GREEN}${BOLD}SysReptor Credentials${NC}"
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        echo -e "  Web URL:   ${BOLD}http://localhost:8000${NC}"
        echo -e "  Username:  ${BOLD}reptor${NC}"
        echo -e "  Password:  ${BOLD}${generated_pw}${NC}"
        echo -e "  Saved to:  ${creds_file}"
        echo -e "${YELLOW}  ⚠️  REMINDER: Please change this password on first login!${NC}"
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        echo
        read -rp "Please copy your username and password above. Press [Enter] to continue: " _
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

        # If BloodHound container stack is already running, show credentials if available and skip re-installation
        if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^bloodhound"; then
            log_success "BloodHound CE container stack is already running! Web interface: http://localhost:8080"
            # Ensure running containers have restart: always enabled for boot persistence
            sudo docker update --restart=always $(sudo docker ps -q --filter "name=bloodhound") 2>/dev/null || true
            sudo docker update --restart=always $(sudo docker ps -q --filter "name=app-db") 2>/dev/null || true
            sudo docker update --restart=always $(sudo docker ps -q --filter "name=graph-db") 2>/dev/null || true
            log_info "BloodHound CE container status:"
            sudo docker ps -a --filter "name=bloodhound" --format '  {{.Names}}: {{.Status}}' 2>/dev/null || true
            if [ -f "$creds_file" ]; then
                local existing_pw
                existing_pw=$(awk '/with this password: /{sub(/.*with this password: /,""); print; exit} /^Password:[[:space:]]+/{sub(/^Password:[[:space:]]+/,""); print; exit}' "$creds_file" 2>/dev/null | tr -d '\r\n' || true)
                if [ -n "$existing_pw" ]; then
                    echo
                    echo -e "${GREEN}${BOLD}====================================================${NC}"
                    echo -e "${GREEN}${BOLD}BloodHound CE Credentials${NC}"
                    echo -e "${GREEN}${BOLD}====================================================${NC}"
                    echo -e "  Web URL:   ${BOLD}http://localhost:8080${NC}"
                    echo -e "  Username:  ${BOLD}admin${NC}"
                    echo -e "  Password:  ${BOLD}${existing_pw}${NC}"
                    echo -e "  Saved to:  ${creds_file}"
                    echo -e "${YELLOW}  ⚠️  REMINDER: You must change this password on first login!${NC}"
                    echo -e "${GREEN}${BOLD}====================================================${NC}"
                    echo
                    read -rp "Please copy your username and password above. Press [Enter] to continue: " _
                fi
            fi
            return 0
        fi

        sudo mkdir -p "$install_dir"
        log_info "Downloading official BloodHound CE docker-compose.yml to $install_dir..."
        sudo curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors -o "$install_dir/docker-compose.yml" \
            https://raw.githubusercontent.com/SpecterOps/BloodHound/main/examples/docker-compose/docker-compose.yml \
            || { log_error "Could not download the BloodHound CE compose file; skipping BloodHound CE deployment."; return 0; }

        # Deterministic initial admin password via the documented config-file mount
        local initial_pw
        initial_pw="$(openssl rand -base64 20 | tr -d '\r\n=')"
        log_info "Writing bloodhound.config.json (sets the initial admin password)..."
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
    "first_name": "BloodHound",
    "last_name": "Admin",
    "email_address": "admin@example.com"
  }
  }
EOF
        # Enable the commented-out config mount in the compose file (docs: custom-installation)
        sudo sed -i 's|^    # volumes:$|    volumes:|; s|^    #   - \./bloodhound\.config\.json:/bloodhound\.config\.json:ro$|      - ./bloodhound.config.json:/bloodhound.config.json:ro|' "$install_dir/docker-compose.yml"
        if ! sudo grep -q '^      - \./bloodhound\.config\.json:/bloodhound\.config\.json:ro$' "$install_dir/docker-compose.yml"; then
            log_error "Could not enable the bloodhound.config.json mount in docker-compose.yml; skipping BloodHound CE deployment."
            return 0
        fi

        log_info "Starting BloodHound CE stack via docker compose (image pulls may take a few minutes)..."
        local compose_rc=1
        local attempt
        for attempt in 1 2 3; do
            if (cd "$install_dir" && sudo docker compose up -d); then
                compose_rc=0
                break
            fi
            if [ "$attempt" -lt 3 ]; then
                log_warn "docker compose up failed (attempt ${attempt}/3, often a transient Docker Hub network error); retrying in 5s..."
                sleep 5
            fi
        done
        if [ "$compose_rc" -ne 0 ]; then
            log_error "BloodHound CE deployment failed after 3 attempts (image pull network error). Check connectivity and re-run 'pendora containers', or deploy manually: cd $install_dir && sudo docker compose up -d"
            return 0
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
        echo -e "  Web URL:   ${BOLD}http://localhost:8080${NC} ${YELLOW}(localhost-only; remote access: ssh -L 8080:localhost:8080 <user>@<this-host>)${NC}"
        echo -e "  Username:  ${BOLD}${parsed_user}${NC}"
        echo -e "  Password:  ${BOLD}${parsed_pw}${NC}"
        echo -e "  Saved to:  ${creds_file}"
        echo -e "${YELLOW}  ⚠️  REMINDER: You must change this password on first login!${NC}"
        echo -e "${GREEN}${BOLD}====================================================${NC}"
        echo
        read -rp "Please copy your username and password above. Press [Enter] to continue: " _

        log_success "BloodHound CE deployed successfully! Web interface: http://localhost:8080"
        log_info "BloodHound stack and volumes are fully manageable in Portainer (https://localhost:9443)."
    fi
}
install_devtunnel() {
    log_info "Installing Microsoft Dev Tunnels CLI (devtunnel)..."
    local dest="/usr/local/bin/devtunnel"
    local download_url="https://aka.ms/TunnelsCliDownload/linux-x64"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] curl -fL --progress-bar '$download_url' -o <mktemp dir>/devtunnel && sudo install -m 755 <tmp>/devtunnel '$dest'"
    else
        log_info "Downloading devtunnel binary (~60 MB)..."
        local tmp_dir
        tmp_dir="$(mktemp -d)"
        curl -fsSL --progress-bar "$download_url" -o "$tmp_dir/devtunnel"
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
    local temp_dir="/tmp/rustscan_install_$$"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] curl -fsSL '$download_url' -o /tmp/rustscan.zip"
        echo "  [DRY-RUN] unzip /tmp/rustscan.zip && tar -xzf x86_64-linux-rustscan.tar.gz"
        echo "  [DRY-RUN] sudo install -m 755 rustscan '$dest'"
    else
        mkdir -p "$temp_dir"
        trap 'rm -rf "$temp_dir"' EXIT
        log_info "Downloading RustScan release archive..."
        curl -fsSL "$download_url" -o "$temp_dir/rustscan.zip"
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
    local download_url="https://github.com/projectdiscovery/naabu/releases/download/v2.6.1/naabu_2.6.1_linux_amd64.zip"
    local temp_dir="/tmp/naabu_install_$$"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] curl -fsSL '$download_url' -o /tmp/naabu.zip"
        echo "  [DRY-RUN] unzip /tmp/naabu.zip naabu"
        echo "  [DRY-RUN] sudo install -m 755 naabu '$dest'"
    else
        mkdir -p "$temp_dir"
        trap 'rm -rf "$temp_dir"' EXIT
        log_info "Downloading Naabu release archive..."
        curl -fsSL "$download_url" -o "$temp_dir/naabu.zip"
        unzip -q -o "$temp_dir/naabu.zip" naabu -d "$temp_dir"
        sudo install -m 755 "$temp_dir/naabu" "$dest"
        rm -rf "$temp_dir"
        trap - EXIT
        log_success "Naabu installed successfully to $dest"
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
    TOOLS=("metasploit" "burpsuite" "seclists" "evil-winrm" "zap" "hack-font" "rustscan" "naabu" "portainer" "sysreptor" "bloodhound" "devtunnel" "responder")
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

for tool in "${TOOLS[@]}"; do
    case "$tool" in
        metasploit)
            install_metasploit
            ;;
        burpsuite)
            install_burpsuite
            ;;
        seclists)
            install_seclists
            ;;
        evil-winrm)
            install_evil_winrm
            ;;
        zap)
            install_zap
            ;;
        hack-font|font)
            install_hack_font
            ;;
        rustscan)
            install_rustscan
            ;;
        naabu)
            install_naabu
            ;;
        portainer)
            install_portainer
            ;;
        sysreptor)
            install_sysreptor
            ;;
        bloodhound)
            install_bloodhound
            ;;
        devtunnel|devtunnels)
            install_devtunnel
            ;;
        responder)
            install_responder
            ;;
        *)
            log_error "Unknown tool: $tool"
            exit 1
            ;;
    esac
done

log_success "All requested upstream tools processed."
