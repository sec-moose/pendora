#!/usr/bin/env bash
#
# pendora - Fedora Penetration Testing VM Setup Script
# Reads modular package lists from pkg-lists/, pipx-lists/, and upstreams/.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LISTS_DIR="${SCRIPT_DIR}/pkg-lists"
PIPX_DIR="${SCRIPT_DIR}/pipx-lists"
UPSTREAMS_SCRIPT="${SCRIPT_DIR}/upstreams/install-upstreams.sh"

DRY_RUN=false
ASSUME_YES=""
INSTALL_PIPX=false
INSTALL_UPSTREAMS=false
INSTALL_ZSH=false
INSTALL_SWAY=false
INSTALL_ALACRITTY=false
INSTALL_NVIM=false
INSTALL_WALLPAPER=false
INSTALL_DOCKER_CONTAINERS=false
SET_HOSTNAME=false
RUN_ALL=false
RUN_BASIC=false
SERVER_MODE=false
GREETER_TAG="v1.7.0"      # noctalia-greeter upstream pin (not yet in official Fedora repos)
GREETER_COMMIT="af0bf4b1e1c40738db917b04c9c0563b4f718953"  # verified v1.7.0 commit — build refuses re-pointed tags (audit M1)
REBOOT=true
SELECTED_CATEGORIES=()
CUSTOM_FILES=()

# Colors for terminal output
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
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS]

${BOLD}Options:${NC}
  -h, --help               Show this help message and exit
  -l, --list               Display available categories and package counts
  -d, --dry-run            Simulate execution; print commands without installing
  -y, --yes                Pass -y to dnf / assume yes for prompts
  -c, --category <name>    Install specific category (e.g. -c 10-networking -c 30-forensics)
  -f, --file <file>        Install packages from a specific file
  -p, --pipx               Install Python security tools via pipx
  -u, --upstreams          Run standalone upstream installers (Metasploit, Burp, SecLists, etc.)
  -D, --docker, --containers Install Docker engine and deploy container stacks (Portainer, SysReptor, BloodHound)
  -z, --zsh                Deploy Kali-styled .zshrc configuration
  -W, --sway               Install Sway tiling desktop stack, Noctalia shell, Zsh, Neovim, Alacritty & wallpapers
  -S, --server             Phase 1 server profile: Sway desktop stack + display manager (greetd & Noctalia greeter), VM guest fixes & Plymouth spinner splash; run '--all' afterwards for pentest tools
  -T, --alacritty          Deploy Alacritty terminal configuration & Catppuccin Macchiato theme
  -N, --nvim               Deploy Neovim/LazyVim configuration & Catppuccin Macchiato theme
  -H, --hostname           Set system hostname to 'pendora'
  -B, --wallpaper          Deploy and apply Pendora custom wallpaper
  -b, --basic              Basic pentest setup without Sway (00-60 DNF + pipx + upstreams + zsh + alacritty + nvim + wallpaper)
  -a, --all                Full setup including Sway desktop stack & wallpaper
  --no-reboot              Do not reboot system after installation
${BOLD}Examples:${NC}
  $(basename "$0") --list
  $(basename "$0") --dry-run
  $(basename "$0") -c 10-networking -c 20-web
  $(basename "$0") --pipx
  $(basename "$0") --all --dry-run
EOF
}

check_distro() {
    if [ ! -f /etc/fedora-release ]; then
        log_warn "This script is tailored for Fedora Linux. /etc/fedora-release not detected."
        if [ "$DRY_RUN" = false ]; then
            read -rp "Continue anyway? [y/N]: " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
        fi
    fi
}
check_non_root() {
    if [ "$EUID" -eq 0 ] && [ -z "${ALLOW_ROOT:-}" ]; then
        log_warn "You are running this script directly as root or via sudo."
        log_warn "It is recommended to run as your regular user: ./install.sh"
        log_warn "The script internally requests sudo for commands requiring root."
        if [ "$DRY_RUN" = false ]; then
            read -rp "Continue as root anyway? [y/N]: " confirm_root
            [[ "$confirm_root" =~ ^[Yy]$ ]] || exit 1
        fi
    fi
}


# Parse a package list file, filtering out blank lines and comments
parse_package_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        log_error "List file not found: $file"
        return 1
    fi
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$file" | grep -vE '^[[:space:]]*$' || true
}

list_categories() {
    echo -e "${BOLD}1. Native DNF Package Categories (pkg-lists/):${NC}"
    echo "----------------------------------------------------"
    printf "%-30s %s\n" "Category / File" "Package Count"
    echo "----------------------------------------------------"

    local total=0
    for list_file in "${LISTS_DIR}"/*.list; do
        [ -f "$list_file" ] || continue
        local name
        name="$(basename "$list_file" .list)"
        local count
        count="$(parse_package_file "$list_file" | wc -l)"
        total=$((total + count))
        printf "%-30s %d packages\n" "$name" "$count"
    done
    echo "----------------------------------------------------"
    printf "%-30s %d packages\n" "TOTAL NATIVE DNF" "$total"
    echo

    echo -e "${BOLD}2. Pipx Python Tool Lists (pipx-lists/):${NC}"
    echo "----------------------------------------------------"
    for pfile in "${PIPX_DIR}"/*.list; do
        [ -f "$pfile" ] || continue
        local pname
        pname="$(basename "$pfile")"
        local pcount
        pcount="$(parse_package_file "$pfile" | wc -l)"
        printf "%-30s %d tools\n" "$pname" "$pcount"
    done
    echo

    echo -e "${BOLD}3. Standalone Upstream Installers (upstreams/):${NC}"
    echo "----------------------------------------------------"
    echo "  - metasploit   (Rapid7 Omnibus Installer)"
    echo "  - burpsuite    (PortSwigger Linux Installer)"
    echo "  - seclists     (GitHub git clone -> /usr/share/wordlists/seclists)"
    echo "  - evil-winrm   (RubyGem)"
    echo "  - zap          (OWASP ZAP via Flatpak)"
    echo "  - hack-font    (Hack Nerd Font for terminal and prompt iconography)"
    echo "  - rustscan     (RustScan ultra-fast 65k-port scanner binary in /usr/local/bin)"
    echo "  - naabu        (Naabu fast port scanner by ProjectDiscovery in /usr/local/bin)"
    echo "  - portainer    (Portainer Community Edition UI on port 9443)"
    echo "  - sysreptor    (SysReptor CE pentest reporting platform via Docker on port 8000)"
    echo "  - bloodhound   (BloodHound Community Edition on port 8080 - Portainer manageable)"
    echo "  - devtunnel    (Microsoft Dev Tunnels CLI for secure port forwarding)"
    echo "  - responder    (Responder LLMNR/NBT-NS/mDNS poisoner in /opt/responder)"
    echo "----------------------------------------------------"
}

run_pipx_install() {
    echo
    echo -e "${BOLD}Installing Pipx Security Tools${NC}"
    echo "===================================================="

    local pipx_pkgs=()
    for pfile in "${PIPX_DIR}"/*.list; do
        [ -f "$pfile" ] || continue
        mapfile -t lines < <(parse_package_file "$pfile")
        for line in "${lines[@]}"; do
            pipx_pkgs+=("$line")
        done
    done

    if [ ${#pipx_pkgs[@]} -eq 0 ]; then
        log_warn "No pipx tools listed in ${PIPX_DIR}."
        return 0
    fi
    # Ensure pipx is available (mirrored in dry-run so the plan stays truthful)
    if ! command -v pipx &>/dev/null; then
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] sudo dnf install -y pipx"
        else
            log_info "pipx command not found. Installing pipx via dnf..."
            sudo dnf install -y pipx
        fi
    fi
    local target_user="${SUDO_USER:-$USER}"
    local target_home
    target_home="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)"
    [ -z "$target_home" ] && target_home="$HOME"
    local pipx_bin_dir="${target_home}/.local/bin"

    # Pipx must execute strictly as the standard user (never with root/sudo privileges).
    # When install.sh is invoked via sudo, drop root privileges to the target standard user.
    local pipx_runner=()
    if [ -n "${SUDO_USER:-}" ] && [ "$EUID" -eq 0 ]; then
        pipx_runner=(sudo -u "$target_user" env HOME="$target_home" USER="$target_user" PATH="$PATH:${target_home}/.local/bin")
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] ${pipx_runner[*]} pipx ensurepath"
    else
        "${pipx_runner[@]}" pipx ensurepath 2>/dev/null || true
    fi

    log_info "Total pipx tools to install: ${#pipx_pkgs[@]}"
    for tool in "${pipx_pkgs[@]}"; do
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] ${pipx_runner[*]} pipx install $tool"
        else
            log_info "Running: pipx install $tool (as standard user $target_user)"
            "${pipx_runner[@]}" pipx install "$tool" || \
            "${pipx_runner[@]}" pipx upgrade "$tool" || \
            "${pipx_runner[@]}" pipx install --force "$tool" || \
            log_warn "pipx install failed for: $tool"
        fi
    done
    log_success "Pipx processing complete."
    # Post-process Impacket: create convenience aliases and central /usr/local/bin/impacket launcher
    # target_user and target_home already resolved above

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Create impacket-* convenience symlinks in ~/.local/bin (impacket- prefix only; stale bare aliases removed)"
        echo "  [DRY-RUN] Deploy central /usr/local/bin/impacket CLI launcher"
    else
        if [ -d "$pipx_bin_dir" ]; then
            log_info "Configuring Impacket convenience symlinks (impacket- prefix only) in $pipx_bin_dir..."
            for script in "$pipx_bin_dir"/*.py; do
                [ -f "$script" ] || continue
                local base_name
                base_name="$(basename "$script" .py)"
                # Only create impacket- prefixed aliases (e.g. impacket-secretsdump -> secretsdump.py);
                # bare aliases shadowed system tools (impacket's ping.py used to hijack system ping)
                [ ! -e "${pipx_bin_dir}/impacket-${base_name}" ] && ln -sf "$script" "${pipx_bin_dir}/impacket-${base_name}"
                # Remove stale bare aliases created by older Pendora runs
                if [ -L "${pipx_bin_dir}/${base_name}" ] && [ -f "${pipx_bin_dir}/${base_name}.py" ] && [ -e "${pipx_bin_dir}/impacket-${base_name}" ]; then
                    rm -f "${pipx_bin_dir}/${base_name}"
                fi
            done
            if [ -n "${SUDO_USER:-}" ]; then
                chown -h "${target_user}:${target_user}" "${pipx_bin_dir}"/* 2>/dev/null || true
            fi
        fi

        # Deploy central 'impacket' CLI runner
        sudo tee /usr/local/bin/impacket >/dev/null <<'EOF'
#!/usr/bin/env bash
#
# impacket - Central command runner and helper for Impacket tools suite
#

show_impacket_help() {
    echo -e "\033[1mImpacket Security Suite\033[0m - Network Protocol Testing Framework"
    echo "Usage: impacket <tool> [args...]"
    echo "       impacket-<tool> [args...]"
    echo "       <tool>.py [args...]"
    echo
    echo -e "\033[1mCommon Tools:\033[0m"
    printf "  %-22s %s\n" "secretsdump" "Dump SAM hashes, LSA secrets, and NTDS.dit"
    printf "  %-22s %s\n" "psexec" "PSEXEC-like process execution on remote Windows host"
    printf "  %-22s %s\n" "wmiexec" "Execute non-interactive commands via WMI"
    printf "  %-22s %s\n" "smbclient" "Interactive SMB client (upload/download/explore)"
    printf "  %-22s %s\n" "smbexec" "Interactive SMB execution via service"
    printf "  %-22s %s\n" "ntlmrelayx" "NTLM relay attack suite (HTTP/SMB/LDAP/MSSQL)"
    printf "  %-22s %s\n" "GetNPUsers" "Query AS-REP roasting (accounts with DONT_REQ_PREAUTH)"
    printf "  %-22s %s\n" "GetUserSPNs" "Kerberoast SPN discovery and ticket requester"
    printf "  %-22s %s\n" "ticketConverter" "Convert between ccache and kirbi Kerberos tickets"
    printf "  %-22s %s\n" "goldenPac" "MS14-068 exploit and Kerberos ticket generator"
    printf "  %-22s %s\n" "addcomputer" "Add a new computer account to Active Directory domain"
    printf "  %-22s %s\n" "mimikatz" "Execute Mimikatz via RPC"
    echo
    echo "Run 'impacket <tool> -h' for tool-specific help (e.g. impacket secretsdump -h)"
}

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_impacket_help
    exit 0
fi

TOOL="$1"
shift

# Check candidate paths
for CANDIDATE in "$HOME/.local/bin/${TOOL}.py" "$HOME/.local/bin/${TOOL}" "/usr/local/bin/${TOOL}.py" "${TOOL}.py" "${TOOL}"; do
    if command -v "$CANDIDATE" &>/dev/null; then
        exec "$CANDIDATE" "$@"
    fi
done

echo "Error: Impacket tool '${TOOL}' not found." >&2
echo "Run 'impacket --help' to view available tools." >&2
exit 1
EOF
        sudo chmod +x /usr/local/bin/impacket
        log_success "Impacket launcher and symlinks configured."
    fi
}

run_upstreams_install() {
    echo
    echo -e "${BOLD}Running Standalone Upstream Installers${NC}"
    echo "===================================================="

    if [ ! -x "$UPSTREAMS_SCRIPT" ]; then
        log_error "Upstream installer script not found or not executable: $UPSTREAMS_SCRIPT"
        return 1
    fi

    local upstream_args=()
    [ "$DRY_RUN" = true ] && upstream_args+=("--dry-run")
    [ -n "$ASSUME_YES" ] && upstream_args+=("--yes")
    upstream_args+=("all")

    "$UPSTREAMS_SCRIPT" "${upstream_args[@]}"
}
run_containers_install() {
    echo
    echo -e "${BOLD}Deploying Docker Containers (Portainer, SysReptor, BloodHound)${NC}"
    echo "===================================================="

    if [ ! -x "$UPSTREAMS_SCRIPT" ]; then
        log_error "Upstream installer script not found or not executable: $UPSTREAMS_SCRIPT"
        return 1
    fi

    local upstream_args=()
    [ "$DRY_RUN" = true ] && upstream_args+=("--dry-run")
    [ -n "$ASSUME_YES" ] && upstream_args+=("--yes")
    upstream_args+=("containers")

    "$UPSTREAMS_SCRIPT" "${upstream_args[@]}"
}

stow_module() {
    local module="$1"
    local module_dir="${SCRIPT_DIR}/${module}"
    local target_user="${SUDO_USER:-$USER}"
    local target_home
    target_home="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)"
    [ -z "$target_home" ] && target_home="$HOME"

    if [ ! -d "$module_dir" ]; then
        log_warn "Module directory '$module' not found in $SCRIPT_DIR, skipping."
        return 0
    fi

    # Ensure GNU Stow is installed (mirrored in dry-run so the plan stays truthful)
    if ! command -v stow &>/dev/null; then
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] sudo dnf install -y stow"
        else
            log_info "stow command not found. Installing stow via dnf..."
            sudo dnf install -y stow || true
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] stow -d '$SCRIPT_DIR' -t '$target_home' -R '$module'"
        return 0
    fi

    log_info "Applying ${BOLD}${module}${NC} dotfiles via GNU Stow into $target_home..."
    mkdir -p "$target_home/.config"
    if [ -n "${SUDO_USER:-}" ] && [ "$EUID" -eq 0 ]; then
        chown "${target_user}:$(id -gn "$target_user")" "$target_home/.config"
    fi

    # Back up existing non-symlink targets to prevent Stow conflicts
    case "$module" in
        zsh)
            if [ -f "$target_home/.zshrc" ] && [ ! -L "$target_home/.zshrc" ]; then
                local zsh_bak="$target_home/.zshrc.bak.$(date +%Y%m%d_%H%M%S)"
                log_info "Existing regular .zshrc found. Backing up to $zsh_bak"
                mv "$target_home/.zshrc" "$zsh_bak"
            fi
            ;;
        sway)
            for d in sway hypr noctalia; do
                if [ -d "$target_home/.config/$d" ] && [ ! -L "$target_home/.config/$d" ]; then
                    local d_bak="$target_home/.config/${d}.bak.$(date +%Y%m%d_%H%M%S)"
                    log_info "Existing non-symlink directory $target_home/.config/$d found. Backing up to $d_bak"
                    mv "$target_home/.config/$d" "$d_bak"
                fi
            done
            ;;
        alacritty)
            if [ -d "$target_home/.config/alacritty" ] && [ ! -L "$target_home/.config/alacritty" ]; then
                local a_bak="$target_home/.config/alacritty.bak.$(date +%Y%m%d_%H%M%S)"
                log_info "Existing non-symlink directory $target_home/.config/alacritty found. Backing up to $a_bak"
                mv "$target_home/.config/alacritty" "$a_bak"
            fi
            ;;
        nvim)
            if [ -d "$target_home/.config/nvim" ] && [ ! -L "$target_home/.config/nvim" ]; then
                local n_bak="$target_home/.config/nvim.bak.$(date +%Y%m%d_%H%M%S)"
                log_info "Existing non-symlink directory $target_home/.config/nvim found. Backing up to $n_bak"
                mv "$target_home/.config/nvim" "$n_bak"
            fi
            ;;
    esac

    # Execute stow as the target user to ensure proper symlink ownership;
    # back up conflicting targets to timestamped backups to protect the git repository tree
    local stow_cmd=(stow -d "$SCRIPT_DIR" -t "$target_home")
    if [ -n "${SUDO_USER:-}" ] && [ "$EUID" -eq 0 ]; then
        stow_cmd=(sudo -u "$target_user" stow -d "$SCRIPT_DIR" -t "$target_home")
    fi

    local stow_rc=0
    if ! "${stow_cmd[@]}" -R "$module" 2>/dev/null; then
        # Restow failed due to conflict; scan for conflicting targets and back them up
        log_warn "GNU Stow conflict detected for module '${module}'. Scanning for conflicting targets to back up..."
        local conflict_targets
        conflict_targets=$("${stow_cmd[@]}" -n -v "$module" 2>&1 | grep -E "cannot stow|existing target is" | awk '{print $NF}' | tr -d '*:\"' || true)
        if [ -n "$conflict_targets" ]; then
            while IFS= read -r cfile; do
                [ -z "$cfile" ] && continue
                local full_cpath="${target_home}/${cfile}"
                if [ -e "$full_cpath" ] || [ -L "$full_cpath" ]; then
                    local bak_path="${full_cpath}.bak.$(date +%Y%m%d_%H%M%S)"
                    log_info "Backing up conflicting target: ${full_cpath} -> ${bak_path}"
                    mv "$full_cpath" "$bak_path" 2>/dev/null || true
                fi
            done <<< "$conflict_targets"
        fi
        "${stow_cmd[@]}" -R "$module" 2>/dev/null || stow_rc=$?
    fi
    if [ "$stow_rc" -eq 0 ]; then
        log_success "Stowed module '${module}' successfully (symlinks in $target_home)."
    else
        log_error "Failed to stow module '${module}' (rc=${stow_rc}); resolve conflicts in $target_home and re-run."
    fi
}

ensure_hack_nerd_font() {
    # Hack Nerd Font ships via the official source-foundry-hack-fonts RPM
    # (pkg-lists/00-base.list). The old GitHub 'latest' tarball fetch was removed:
    # it piped curl|tar with errors swallowed by || true, required network at
    # install time, and silently no-oped when fontconfig was absent on minimal
    # hosts (sway audit 2026-10-22, finding A3).
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Verify Hack Nerd Font (source-foundry-hack-fonts RPM)"
        return 0
    fi
    if command -v fc-list &>/dev/null && fc-list 2>/dev/null | grep -qi "Hack Nerd Font"; then
        log_success "Hack Nerd Font available (source-foundry-hack-fonts RPM)."
    else
        log_warn "Hack Nerd Font not in font cache yet. It is installed via the source-foundry-hack-fonts RPM in the package set."
    fi
}

deploy_zsh_config() {
    echo
    echo -e "${BOLD}Deploying Kali-styled Zsh Configuration (GNU Stow)${NC}"
    echo "===================================================="
    local target_user="${SUDO_USER:-$USER}"

    ensure_hack_nerd_font

    if ! command -v zsh &>/dev/null; then
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] sudo dnf install -y zsh zsh-autosuggestions zsh-syntax-highlighting"
        else
            log_info "zsh not found. Installing zsh packages via dnf..."
            sudo dnf install -y zsh zsh-autosuggestions zsh-syntax-highlighting || true
        fi
    fi

    stow_module "zsh"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo usermod -s \$(command -v zsh) \$USER"
    else
        if command -v zsh &>/dev/null; then
            local zsh_bin
            zsh_bin="$(command -v zsh)"
            local current_login_shell
            current_login_shell="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f7)"
            if [ "$current_login_shell" != "$zsh_bin" ]; then
                log_info "Setting default login shell to $zsh_bin for $target_user..."
                sudo usermod -s "$zsh_bin" "$target_user" || true
                log_success "Default login shell updated to $zsh_bin"
            fi
        fi
    fi
}
configure_screensharing_systemd() {
    echo
    echo -e "${BOLD}Configuring Sway Screensharing (Systemd User Target)${NC}"
    echo "===================================================="
    local target_user="${SUDO_USER:-$USER}"
    local target_home
    target_home="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)"
    [ -z "$target_home" ] && target_home="$HOME"
    local target_dir="${target_home}/.config/systemd/user"
    local target_file="${target_dir}/sway-session.target"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] mkdir -p /home/\$USER/.config/systemd/user"
        echo "  [DRY-RUN] Write /home/\$USER/.config/systemd/user/sway-session.target"
        echo "  [DRY-RUN] Enable sway-spice-clipboard-bridge.service via sway-session.target.wants (bus-free)"
        echo "  [DRY-RUN] Enable-only: session services activate via sway-session.target on first login"
    else
        mkdir -p "$target_dir"
        cat > "$target_file" <<'EOF'
[Unit]
Description=Sway session
BindsTo=graphical-session.target
Wants=graphical-session-pre.target
After=graphical-session-pre.target
PropagatesStopTo=graphical-session.target
EOF
        if [ -n "${SUDO_USER:-}" ]; then
            chown -R "${target_user}:${target_user}" "$target_dir"
        fi
        log_success "Created $target_file"

        # Enable-only, headless-safe: there is no user bus or Wayland display at install
        # time, and `systemctl --user enable` would fail against a nonexistent manager.
        # The wants symlink below is bus-free. sway's own `exec systemctl --user start
        # sway-session.target` activates all wanted units on first real login.
        local bridge_wants_dir="${target_dir}/sway-session.target.wants"
        if [ -f "${target_dir}/sway-spice-clipboard-bridge.service" ]; then
            mkdir -p "$bridge_wants_dir"
            ln -sfn ../sway-spice-clipboard-bridge.service "${bridge_wants_dir}/sway-spice-clipboard-bridge.service"
            log_success "sway-spice-clipboard-bridge enabled via sway-session.target.wants (activates on login)."
        else
            log_warn "sway-spice-clipboard-bridge.service not found in ${target_dir}; enable skipped."
        fi
        log_success "Sway session units written; services activate via sway-session.target on first login."
    fi
}

install_noctalia_greeter() {
    # Build noctalia-greeter from a pinned upstream tag. Not yet packaged in the official
    # Fedora repositories (watch item in TODO.md); on any failure the caller keeps
    # tuigreet as the active greeter, so phase 1 always yields a working login screen.
    local greeter_tag="${GREETER_TAG}"
    if command -v noctalia-greeter-session &>/dev/null; then
        log_info "noctalia-greeter already installed, skipping build."
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Install noctalia-greeter build deps; git clone ${greeter_tag}; meson build; meson install"
        return 0
    fi

    log_info "Installing noctalia-greeter build dependencies (official Fedora repositories)..."
    sudo dnf install -y meson gcc-c++ git wayland-devel wayland-protocols-devel \
        wlroots-devel libinput-devel libevdev-devel mesa-libEGL-devel \
        cairo-devel pango-devel harfbuzz-devel freetype-devel fontconfig-devel \
        libxkbcommon-devel glib2-devel tomlplusplus-devel json-devel \
        stb_image_resize2-devel libwebp-devel libjxl-devel librsvg2-devel libxml2-devel \
        || { log_error "Failed to install noctalia-greeter build dependencies."; return 1; }

    log_info "Building noctalia-greeter ${greeter_tag} (Meson; this can take a few minutes)..."
    (
        set -e
        temp_dir="$(mktemp -d -m 0700)"
        trap 'rm -rf "$temp_dir"' EXIT
        git clone --depth 1 --branch "${greeter_tag}" \
            https://github.com/noctalia-dev/noctalia-greeter "${temp_dir}/noctalia-greeter"
        cd "${temp_dir}/noctalia-greeter"
        resolved_commit="$(git rev-parse HEAD)"
        log_info "noctalia-greeter ${greeter_tag} resolved to commit ${resolved_commit}."
        if [ "${resolved_commit}" != "${GREETER_COMMIT}" ]; then
            log_error "Upstream tag ${greeter_tag} does not point at the pinned commit ${GREETER_COMMIT} — refusing to build (supply-chain guard)."
            exit 1
        fi
        meson setup build --prefix=/usr --buildtype=release
        sudo meson install -C build
    ) || { log_error "noctalia-greeter build failed."; return 1; }

    log_success "noctalia-greeter ${greeter_tag} installed."
}

configure_server_login() {
    echo
    echo -e "${BOLD}Configuring Server Login (greetd + Noctalia Greeter)${NC}"
    echo "===================================================="

    # 1. Invisible-cursor fix: virtio-gpu/bochs hardware-cursor plane flips fail under
    #    wlroots in virtual machines (sway audit 2026-10-22).
    if grep -q '^WLR_NO_HARDWARE_CURSORS=' /etc/environment 2>/dev/null; then
        log_info "WLR_NO_HARDWARE_CURSORS already present in /etc/environment."
    elif [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Append WLR_NO_HARDWARE_CURSORS=1 to /etc/environment"
    else
        echo 'WLR_NO_HARDWARE_CURSORS=1' | sudo tee -a /etc/environment >/dev/null
        log_success "WLR_NO_HARDWARE_CURSORS=1 set in /etc/environment."
    fi

    # 2. SPICE guest agent daemon: system service, safe to enable headless. Required for
    #    the clipboard socket /run/spice-vdagentd/spice-vdagent-sock used by the bridge.
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] systemctl enable --now spice-vdagentd"
    else
        if sudo systemctl enable --now spice-vdagentd 2>/dev/null; then
            log_success "spice-vdagentd enabled and started."
        else
            log_warn "Could not enable spice-vdagentd (no SPICE virtual hardware?). Clipboard sharing will not work."
        fi
    fi

    # 3. Display manager: greetd (pkg-lists/70-sway.list) with the Noctalia greeter.
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Build + install noctalia-greeter from pinned upstream tag ${GREETER_TAG} @ ${GREETER_COMMIT} (fallback: tuigreet)"
        echo "  [DRY-RUN] Ensure system user 'greeter' and /var/lib/noctalia-greeter (0750 greeter:greeter)"
        echo "  [DRY-RUN] Write /etc/greetd/config.toml (default_session = noctalia-greeter-session, fallback tuigreet)"
        echo "  [DRY-RUN] Refuse if another display manager (gdm/sddm/lightdm/lxdm/xdm) is enabled or active"
        echo "  [DRY-RUN] systemctl enable --now greetd ; disable getty@tty1 on success"
        return 0
    fi

    if ! command -v greetd &>/dev/null; then
        log_error "greetd is not installed. Ensure pkg-lists/70-sway.list was included (--sway/--server/--all)."
        return 1
    fi

    install_noctalia_greeter || log_warn "Continuing with tuigreet as the active greeter."

    # Greeter user + state directory (required by noctalia-greeter).
    if ! id -u greeter &>/dev/null; then
        sudo useradd -r -d /var/lib/greetd -s /usr/sbin/nologin greeter \
            || { log_error "Failed to create system user 'greeter'."; return 1; }
        log_success "Created system user 'greeter'."
    fi
    sudo mkdir -p /var/lib/noctalia-greeter \
        && sudo chown greeter:greeter /var/lib/noctalia-greeter \
        && sudo chmod 0750 /var/lib/noctalia-greeter \
        || { log_error "Failed to provision /var/lib/noctalia-greeter (0750 greeter:greeter)."; return 1; }

    # greetd configuration: prefer the Noctalia greeter, fall back to tuigreet.
    local greeter_cmd="/usr/bin/tuigreet --time --cmd sway"
    if command -v noctalia-greeter-session &>/dev/null; then
        greeter_cmd="/usr/bin/noctalia-greeter-session"
    else
        log_warn "noctalia-greeter unavailable - using tuigreet."
    fi
    if [ -f /etc/greetd/config.toml ]; then
        sudo cp /etc/greetd/config.toml "/etc/greetd/config.toml.bak.$(date +%s)" \
            || log_warn "Could not back up the existing /etc/greetd/config.toml."
    fi
    printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "%s"\nuser = "greeter"\n' "${greeter_cmd}" \
        | sudo tee /etc/greetd/config.toml >/dev/null \
        || { log_error "Failed to write /etc/greetd/config.toml."; return 1; }
    log_success "Wrote /etc/greetd/config.toml (command = ${greeter_cmd})."

    # Pin the Sway session and initialize the greeter's appearance state.
    if command -v noctalia-greeter-apply-appearance &>/dev/null; then
        sudo noctalia-greeter-apply-appearance --setup-system 2>/dev/null || true
    fi
    if sudo test -f /var/lib/noctalia-greeter/greeter.toml && ! sudo grep -q 'default = "Sway"' /var/lib/noctalia-greeter/greeter.toml 2>/dev/null; then
        printf '\n[session]\ndefault = "Sway"\n' | sudo tee -a /var/lib/noctalia-greeter/greeter.toml >/dev/null
    fi

    # Refuse to fight an existing display manager for VT 1 (audit M5).
    local other_dm dm_taken=false
    for other_dm in gdm sddm lightdm lxdm xdm; do
        if systemctl is-enabled "${other_dm}" &>/dev/null || systemctl is-active "${other_dm}" &>/dev/null; then
            dm_taken=true
            log_error "Display manager '${other_dm}' is enabled or active — disable it before running --server, or use a host without a graphical login manager."
        fi
    done
    if [ "${dm_taken}" = true ]; then
        return 1
    fi

    if sudo systemctl enable --now greetd; then
        log_success "greetd display manager enabled."
        # Retire the tty1 getty only after greetd owns VT 1 — never leave the host
        # without a display manager AND a console (audit M4).
        sudo systemctl disable --now getty@tty1 2>/dev/null || true
    else
        log_error "Failed to enable greetd."
        return 1
    fi
}

configure_boot_splash() {
    # Set the Plymouth boot splash to the 'spinner' theme so the boot sequence
    # hands off cleanly to the Noctalia greeter instead of console text.
    echo
    echo -e "${BOLD}Configuring Boot Splash (Plymouth spinner)${NC}"
    echo "===================================================="

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo dnf install -y plymouth-theme-spinner plymouth-scripts"
        echo "  [DRY-RUN] sudo plymouth-set-default-theme -R spinner"
        return 0
    fi

    if ! command -v plymouth-set-default-theme &>/dev/null; then
        log_info "Installing Plymouth spinner theme..."
        sudo dnf install -y plymouth-theme-spinner plymouth-scripts || { log_error "Failed to install plymouth-theme-spinner."; return 1; }
    fi

    # -R regenerates the initramfs so the spinner theme is embedded for early boot.
    sudo plymouth-set-default-theme -R spinner \
        || { log_error "Failed to set the Plymouth spinner theme."; return 1; }
    log_success "Plymouth boot splash set to spinner (initramfs regenerated)."
}

deploy_sway_config() {
    echo
    echo -e "${BOLD}Deploying Sway & Noctalia Configuration (GNU Stow)${NC}"
    echo "===================================================="
    ensure_hack_nerd_font
    # Pre-create the systemd user dir so stow descends into it instead of tree-folding
    # ~/.config/systemd into a single symlink into the repo worktree, which would make
    # later unit-file writes land inside the git tree (sway audit 2026-10-22, finding A4).
    # Audit M6: unfold a legacy fold symlink first — hosts provisioned by older scripts
    # may have ~/.config/systemd pointing into the repository.
    # Audit M2: mirrored dry-run echo; dry runs must stay side-effect-free.
    local target_user="${SUDO_USER:-$USER}"
    local target_home
    target_home="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)"
    [ -z "$target_home" ] && target_home="$HOME"
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Unfold legacy ~/.config/systemd symlink if present"
        echo "  [DRY-RUN] mkdir -p ${target_home}/.config/systemd/user (+chown ${target_user})"
    else
        if [ -L "${target_home}/.config/systemd" ]; then
            rm "${target_home}/.config/systemd"
            log_info "Unfolded legacy symlink ${target_home}/.config/systemd (previously pointed into the repository)."
        fi
        mkdir -p "${target_home}/.config/systemd/user"
        if [ -n "${SUDO_USER:-}" ]; then
            chown "${target_user}:${target_user}" "${target_home}/.config/systemd/user"
        fi
    fi
    stow_module "sway"

    log_info "Keyboard layout is applied at session start by apply-gnome-keyboard-layout.sh."
}

deploy_alacritty_config() {
    echo
    echo -e "${BOLD}Deploying Alacritty Configuration (GNU Stow)${NC}"
    echo "===================================================="
    ensure_hack_nerd_font
    if ! command -v alacritty &>/dev/null; then
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] sudo dnf install -y alacritty"
        else
            log_info "alacritty not found. Installing alacritty via dnf..."
            sudo dnf install -y alacritty || true
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo dnf install -y zsh (required by alacritty.toml shell)"
    elif ! command -v zsh &>/dev/null; then
        log_info "zsh not found but required by alacritty config. Installing zsh via dnf..."
        sudo dnf install -y zsh || true
    fi
    stow_module "alacritty"
}

deploy_nvim_config() {
    echo
    echo -e "${BOLD}Deploying Neovim / LazyVim Configuration (GNU Stow)${NC}"
    echo "===================================================="
    if ! command -v nvim &>/dev/null; then
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] sudo dnf install -y neovim"
        else
            log_info "neovim not found. Installing neovim via dnf..."
            sudo dnf install -y neovim || true
        fi
    fi
    stow_module "nvim"
}
deploy_wallpaper() {
    echo
    echo -e "${BOLD}Deploying Pendora Desktop Wallpaper & User Profile Logo${NC}"
    echo "===================================================="
    local sys_wp_dir="/usr/share/backgrounds/pendora"
    local target_user="${SUDO_USER:-$USER}"
    local target_home
    target_home="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)"
    [ -z "$target_home" ] && target_home="$HOME"
    local user_wp_dir="${target_home}/Pictures/wallpapers"
    local default_wp="${sys_wp_dir}/wallpaper.svg"

    if [ ! -d "${SCRIPT_DIR}/assets" ]; then
        log_warn "Assets directory not found: ${SCRIPT_DIR}/assets"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo mkdir -p $sys_wp_dir"
        echo "  [DRY-RUN] sudo cp \${SCRIPT_DIR}/assets/wallpaper*.svg $sys_wp_dir/"
        echo "  [DRY-RUN] mkdir -p $user_wp_dir"
        echo "  [DRY-RUN] cp \${SCRIPT_DIR}/assets/wallpaper*.svg $user_wp_dir/"
        echo "  [DRY-RUN] Set GNOME system-wide dconf default background to $default_wp"
        echo "  [DRY-RUN] gsettings set org.gnome.desktop.background picture-uri 'file://$default_wp'"
        echo "  [DRY-RUN] Copy assets/logo.png to /var/lib/AccountsService/icons/\$USER"
        echo "  [DRY-RUN] Update /var/lib/AccountsService/users/\$USER (Icon path)"
        echo "  [DRY-RUN] Copy assets/logo.png to /home/\$USER/.face and .face.icon"
        echo "  [DRY-RUN] Deploy assets/pendora_darkbackground.svg to $sys_wp_dir/"
        echo "  [DRY-RUN] Configure GNOME background-logo-extension to display Pendora watermark"
        echo "  [DRY-RUN] Update /usr/share/fedora-logos/ with Pendora watermark"
        echo "  [DRY-RUN] Set Noctalia shell default wallpaper to $default_wp"
    else
        log_info "Installing wallpapers to system library ($sys_wp_dir)..."
        sudo mkdir -p "$sys_wp_dir"
        sudo cp "${SCRIPT_DIR}/assets"/wallpaper*.svg "$sys_wp_dir"/
        sudo chmod -R 644 "$sys_wp_dir"/*.svg 2>/dev/null || true
        sudo chmod 755 "$sys_wp_dir"

        log_info "Copying wallpapers to user library ($user_wp_dir)..."
        mkdir -p "$user_wp_dir"
        cp "${SCRIPT_DIR}/assets"/wallpaper*.svg "$user_wp_dir"/
        if [ -n "${SUDO_USER:-}" ]; then
            chown -R "${target_user}:${target_user}" "$user_wp_dir"
        fi

        # 1. Apply system-wide default for GNOME via dconf
        local dconf_dir="/etc/dconf/db/local.d"
        sudo mkdir -p "$dconf_dir"
        sudo tee "${dconf_dir}/00-pendora-wallpaper" >/dev/null <<EOF
[org/gnome/desktop/background]
picture-uri='file://${default_wp}'
picture-uri-dark='file://${default_wp}'
picture-options='zoom'
EOF
        sudo dconf update 2>/dev/null || true

        # 2. Apply to current user session via gsettings if desktop session is active
        if command -v gsettings &>/dev/null; then
            gsettings set org.gnome.desktop.background picture-uri "file://${default_wp}" 2>/dev/null || true
            gsettings set org.gnome.desktop.background picture-uri-dark "file://${default_wp}" 2>/dev/null || true
            gsettings set org.gnome.desktop.background picture-options 'zoom' 2>/dev/null || true
        fi

        # 3. Deploy User Profile Picture / Avatar (AccountsService and ~/.face)
        local logo_png="${SCRIPT_DIR}/assets/logo.png"
        if [ -f "$logo_png" ]; then
            log_info "Setting user profile picture to Pendora logo..."
            # AccountsService system icon
            sudo mkdir -p /var/lib/AccountsService/icons /var/lib/AccountsService/users
            sudo cp "$logo_png" "/var/lib/AccountsService/icons/${target_user}"
            sudo chmod 644 "/var/lib/AccountsService/icons/${target_user}"

            # AccountsService user configuration file
            local user_account_file="/var/lib/AccountsService/users/${target_user}"
            if [ -f "$user_account_file" ]; then
                if grep -q "^Icon=" "$user_account_file"; then
                    sudo sed -i "s|^Icon=.*|Icon=/var/lib/AccountsService/icons/${target_user}|" "$user_account_file"
                else
                    echo "Icon=/var/lib/AccountsService/icons/${target_user}" | sudo tee -a "$user_account_file" >/dev/null
                fi
            else
                sudo tee "$user_account_file" >/dev/null <<EOF
[User]
Icon=/var/lib/AccountsService/icons/${target_user}
EOF
            fi
            sudo chmod 600 "$user_account_file" 2>/dev/null || true

            # Display manager & desktop shell fallback (~/.face and ~/.face.icon)
            cp "$logo_png" "${target_home}/.face" 2>/dev/null || true
            cp "$logo_png" "${target_home}/.face.icon" 2>/dev/null || true
            if [ -n "${SUDO_USER:-}" ]; then
                chown "${target_user}:${target_user}" "${target_home}/.face" "${target_home}/.face.icon" 2>/dev/null || true
            fi
            log_success "User profile picture updated for '$target_user'."
        fi

        # 4. Deploy Desktop Corner Watermark (GNOME background-logo-extension)
        local watermark_svg="${SCRIPT_DIR}/assets/pendora_darkbackground.svg"
        if [ -f "$watermark_svg" ]; then
            log_info "Replacing desktop corner watermark with Pendora branding..."
            local dest_watermark="${sys_wp_dir}/pendora_darkbackground.svg"
            sudo cp "$watermark_svg" "$dest_watermark"
            sudo chmod 644 "$dest_watermark"

            # GNOME dconf override for background-logo-extension
            sudo tee "${dconf_dir}/01-pendora-background-logo" >/dev/null <<EOF
[org/fedorahosted/background-logo-extension]
logo-file='${dest_watermark}'
logo-file-dark='${dest_watermark}'
logo-always-visible=true
EOF
            sudo dconf update 2>/dev/null || true

            # Dynamic gsettings update if desktop session is active
            if command -v gsettings &>/dev/null; then
                gsettings set org.fedorahosted.background-logo-extension logo-file-dark "$dest_watermark" 2>/dev/null || true
                gsettings set org.fedorahosted.background-logo-extension logo-file "$dest_watermark" 2>/dev/null || true
                gsettings set org.fedorahosted.background-logo-extension logo-always-visible true 2>/dev/null || true
            fi

            # Direct fallback replacement in /usr/share/fedora-logos if directory exists
            if [ -d /usr/share/fedora-logos ]; then
                [ ! -f /usr/share/fedora-logos/fedora_darkbackground.svg.bak ] && sudo cp /usr/share/fedora-logos/fedora_darkbackground.svg /usr/share/fedora-logos/fedora_darkbackground.svg.bak 2>/dev/null || true
                sudo cp "$watermark_svg" /usr/share/fedora-logos/fedora_darkbackground.svg 2>/dev/null || true
                sudo cp "$watermark_svg" /usr/share/fedora-logos/fedora_lightbackground.svg 2>/dev/null || true
            fi
            log_success "Desktop corner watermark updated to Pendora branding."
        fi

        # 5. Pre-configure Noctalia Shell Wallpaper Override
        local noctalia_state_dir="${target_home}/.local/state/noctalia"
        mkdir -p "$noctalia_state_dir"
        local noctalia_settings="${noctalia_state_dir}/settings.toml"
        if [ -f "$noctalia_settings" ]; then
            if grep -q "\[wallpaper\.default\]" "$noctalia_settings"; then
                sed -i "/\[wallpaper\.default\]/{n;s|path = .*|path = \"${default_wp}\"|}" "$noctalia_settings"
            else
                cat >> "$noctalia_settings" <<EOF

[wallpaper.default]
path = "${default_wp}"
EOF
            fi
        else
            cat > "$noctalia_settings" <<EOF
[wallpaper.default]
path = "${default_wp}"
EOF
        fi
        if [ -n "${SUDO_USER:-}" ]; then
            chown -R "${target_user}:${target_user}" "$noctalia_state_dir" 2>/dev/null || true
        fi

        log_success "Pendora desktop branding deployed successfully."
    fi
}




set_system_hostname() {
    echo
    echo -e "${BOLD}Configuring System Hostname${NC}"
    echo "===================================================="
    local new_host="pendora"
    log_info "Setting system hostname to: ${BOLD}${new_host}${NC}..."
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo hostnamectl set-hostname $new_host"
    else
        sudo hostnamectl set-hostname "$new_host"
        log_success "System hostname updated to: $new_host"
    fi
}



# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            list_categories
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            ASSUME_YES="-y"
            shift
            ;;
        --no-reboot)
            REBOOT=false
            shift
            ;;
        -c|--category)
            if [ -z "${2:-}" ]; then
                log_error "Option $1 requires an argument."
                exit 1
            fi
            SELECTED_CATEGORIES+=("$2")
            shift 2
            ;;
        -p|--pipx)
            INSTALL_PIPX=true
            shift
            ;;
        -u|--upstreams)
            INSTALL_UPSTREAMS=true
            shift
            ;;
        -z|--zsh)
            INSTALL_ZSH=true
            shift
            ;;
        -b|--basic)
            RUN_BASIC=true
            INSTALL_PIPX=true
            INSTALL_UPSTREAMS=true
            INSTALL_ZSH=true
            INSTALL_ALACRITTY=true
            INSTALL_NVIM=true
            INSTALL_WALLPAPER=true
            SET_HOSTNAME=true
            INSTALL_SWAY=false
            shift
            ;;
        -W|--sway)
            INSTALL_SWAY=true
            INSTALL_WALLPAPER=true
            INSTALL_ZSH=true
            INSTALL_NVIM=true
            INSTALL_ALACRITTY=true
            SET_HOSTNAME=true
            shift
            ;;
        -S|--server)
            SERVER_MODE=true
            INSTALL_SWAY=true
            INSTALL_WALLPAPER=true
            INSTALL_ZSH=true
            INSTALL_NVIM=true
            INSTALL_ALACRITTY=true
            SET_HOSTNAME=true
            shift
            ;;
        -T|--alacritty)
            INSTALL_ALACRITTY=true
            shift
            ;;
        -N|--nvim|--neovim)
            INSTALL_NVIM=true
            shift
            ;;
        -B|--wallpaper)
            INSTALL_WALLPAPER=true
            shift
            ;;
        -D|--docker|--containers)
            INSTALL_DOCKER_CONTAINERS=true
            shift
            ;;
        -H|--hostname)
            SET_HOSTNAME=true
            shift
            ;;
        -a|--all)
            RUN_ALL=true
            INSTALL_PIPX=true
            INSTALL_UPSTREAMS=true
            INSTALL_ZSH=true
            INSTALL_SWAY=true
            INSTALL_ALACRITTY=true
            INSTALL_NVIM=true
            INSTALL_WALLPAPER=true
            SET_HOSTNAME=true
            shift
            ;;
        -f|--file)
            if [ -z "${2:-}" ]; then
                log_error "Option $1 requires an argument."
                exit 1
            fi
            CUSTOM_FILES+=("$2")
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Mutually exclusive profiles: --basic excludes the sway stack (greetd, tuigreet)
# that --server configures, which would abort phase 1 mid-run (audit H1).
if [ "$SERVER_MODE" = true ] && [ "$RUN_BASIC" = true ]; then
    log_error "--server and --basic are mutually exclusive: --basic excludes the Sway stack that --server configures."
    exit 1
fi

check_distro
check_non_root

# Resolve files to process
# Determine whether DNF packages should be installed
RUN_PACKAGES=false

if [ "$RUN_ALL" = true ] || [ "$RUN_BASIC" = true ] || [ ${#SELECTED_CATEGORIES[@]} -gt 0 ] || [ ${#CUSTOM_FILES[@]} -gt 0 ] || [ "$INSTALL_SWAY" = true ] || [ "$INSTALL_DOCKER_CONTAINERS" = true ]; then
    RUN_PACKAGES=true
elif [ "$INSTALL_PIPX" = false ] && [ "$INSTALL_UPSTREAMS" = false ] && [ "$INSTALL_ZSH" = false ] && [ "$INSTALL_ALACRITTY" = false ] && [ "$INSTALL_NVIM" = false ] && [ "$INSTALL_WALLPAPER" = false ] && [ "$INSTALL_DOCKER_CONTAINERS" = false ] && [ "$SET_HOSTNAME" = false ]; then
    # Default invocation with no flags: install native packages (00-60)
    RUN_PACKAGES=true
fi

TARGET_FILES=()

if [ "$RUN_PACKAGES" = true ]; then
    if [ ${#CUSTOM_FILES[@]} -gt 0 ]; then
        for f in "${CUSTOM_FILES[@]}"; do
            if [ -f "$f" ]; then
                TARGET_FILES+=("$f")
            elif [ -f "${LISTS_DIR}/${f}" ]; then
                TARGET_FILES+=("${LISTS_DIR}/${f}")
            elif [ -f "${LISTS_DIR}/${f}.list" ]; then
                TARGET_FILES+=("${LISTS_DIR}/${f}.list")
            else
                log_error "Could not resolve file: $f"
                exit 1
            fi
        done
    elif [ ${#SELECTED_CATEGORIES[@]} -gt 0 ]; then
        for cat in "${SELECTED_CATEGORIES[@]}"; do
            matched=false
            for list_file in "${LISTS_DIR}"/*"${cat}"*.list; do
                if [ -f "$list_file" ]; then
                    TARGET_FILES+=("$list_file")
                    matched=true
                fi
            done
            if [ "$matched" = false ]; then
                log_error "No category list matching '$cat' found in ${LISTS_DIR}"
                exit 1
            fi
        done
    elif [ "$RUN_ALL" = true ]; then
        for list_file in "${LISTS_DIR}"/*.list; do
            [ -f "$list_file" ] && TARGET_FILES+=("$list_file")
        done
    elif [ "$INSTALL_SWAY" = true ] && [ "$RUN_BASIC" = false ]; then
        TARGET_FILES+=("${LISTS_DIR}/00-base.list" "${LISTS_DIR}/70-sway.list")
    elif [ "$INSTALL_DOCKER_CONTAINERS" = true ] && [ "$RUN_BASIC" = false ]; then
        TARGET_FILES+=("${LISTS_DIR}/60-docker.list")
    else
        # Default or --basic: process 00-60 (skip 70-*)
        for list_file in "${LISTS_DIR}"/*.list; do
            [[ "$list_file" =~ "70-" ]] && continue
            [ -f "$list_file" ] && TARGET_FILES+=("$list_file")
        done
    fi

    # Ensure Docker packages are included whenever container deployment was requested
    if [ "$INSTALL_DOCKER_CONTAINERS" = true ] && [ "$RUN_BASIC" = false ] && [ "$RUN_ALL" = false ]; then
        case " ${TARGET_FILES[*]-} " in
            *"60-docker"*) ;;
            *) [ -f "${LISTS_DIR}/60-docker.list" ] && TARGET_FILES+=("${LISTS_DIR}/60-docker.list") ;;
        esac
    fi

    # Ensure Base and Sway packages are included whenever Sway installation was requested
    if [ "$INSTALL_SWAY" = true ] && [ "$RUN_BASIC" = false ] && [ "$RUN_ALL" = false ]; then
        case " ${TARGET_FILES[*]-} " in
            *"00-base"*) ;;
            *) [ -f "${LISTS_DIR}/00-base.list" ] && TARGET_FILES+=("${LISTS_DIR}/00-base.list") ;;
        esac
        case " ${TARGET_FILES[*]-} " in
            *"70-sway"*) ;;
            *) [ -f "${LISTS_DIR}/70-sway.list" ] && TARGET_FILES+=("${LISTS_DIR}/70-sway.list") ;;
        esac
    fi

    ALL_PACKAGES=()

    echo -e "${BOLD}Pendora - Native DNF Package Plan${NC}"
    echo "===================================================="

    for file in "${TARGET_FILES[@]}"; do
        filename="$(basename "$file")"
        log_info "Reading: ${BOLD}${filename}${NC}"
        mapfile -t pkgs < <(parse_package_file "$file")
        if [ ${#pkgs[@]} -gt 0 ]; then
            for p in "${pkgs[@]}"; do
                ALL_PACKAGES+=("$p")
            done
            echo "  -> Found ${#pkgs[@]} packages in ${filename}"
        else
            echo "  -> 0 packages in ${filename}"
        fi
    done

    echo "===================================================="
    log_info "Total native DNF packages to process: ${BOLD}${#ALL_PACKAGES[@]}${NC}"


    if [ ${#ALL_PACKAGES[@]} -eq 0 ]; then
        log_warn "No packages resolved from the selected lists; skipping DNF install."
    elif [ "$DRY_RUN" = true ]; then
        log_info "Dry run requested. Planned DNF command:"
        echo
        echo "sudo dnf install ${ASSUME_YES} ${ALL_PACKAGES[*]}"
        echo
    else
        if [ -z "$ASSUME_YES" ]; then
            echo
            read -rp "Proceed with DNF installation? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log_warn "DNF installation aborted by user."
            else
                log_info "Executing: sudo dnf install ${ASSUME_YES} ..."
                sudo dnf install $ASSUME_YES "${ALL_PACKAGES[@]}"
                log_success "DNF packages installed successfully."
            fi
        else
            log_info "Executing: sudo dnf install ${ASSUME_YES} ..."
            sudo dnf install $ASSUME_YES "${ALL_PACKAGES[@]}"
            log_success "DNF packages installed successfully."
        fi
    fi

    # If Docker packages were installed, immediately enable service and add user to docker group
    for f in "${TARGET_FILES[@]}"; do
        if [[ "$f" =~ "60-docker" ]]; then
            target_user="${SUDO_USER:-$USER}"
            log_info "Enabling Docker service and adding '$target_user' to docker group..."
            if [ "$DRY_RUN" = true ]; then
                echo "  [DRY-RUN] sudo systemctl enable --now docker"
                echo "  [DRY-RUN] sudo usermod -aG docker $target_user"
            else
                sudo systemctl enable --now docker 2>/dev/null || true
                sudo usermod -aG docker "$target_user" 2>/dev/null || true
                log_success "Docker service enabled and user '$target_user' added to docker group."
            fi
            break
        fi
    done
fi

# Run Pipx section if requested
if [ "$INSTALL_PIPX" = true ]; then
    run_pipx_install
fi

# Run Upstreams section if requested
if [ "$INSTALL_UPSTREAMS" = true ]; then
    run_upstreams_install
fi

# Deploy Zsh configuration if requested
if [ "$INSTALL_ZSH" = true ]; then
    deploy_zsh_config
fi

# Deploy Sway configuration if requested
if [ "$INSTALL_SWAY" = true ]; then
    deploy_sway_config
fi

# Configure screensharing systemd target after Sway dotfiles are deployed
if [ "$INSTALL_SWAY" = true ]; then
    configure_screensharing_systemd
fi

# Configure display manager & VM guest integration for the --server profile (phase 1)
if [ "$SERVER_MODE" = true ]; then
    configure_server_login
    configure_boot_splash || log_warn "Boot splash configuration failed — continuing without it."
fi

# Deploy Alacritty configuration if requested
if [ "$INSTALL_ALACRITTY" = true ]; then
    deploy_alacritty_config
fi

# Run Docker containers section if requested
if [ "$INSTALL_DOCKER_CONTAINERS" = true ]; then
    run_containers_install
fi

# Deploy Neovim configuration if requested
if [ "$INSTALL_NVIM" = true ]; then
    deploy_nvim_config
fi

# Deploy wallpaper if requested
if [ "$INSTALL_WALLPAPER" = true ]; then
    deploy_wallpaper
fi

# Set system hostname if requested
if [ "$SET_HOSTNAME" = true ]; then
    set_system_hostname
fi

log_success "Pendora execution completed!"

if [ "$SERVER_MODE" = true ]; then
    log_success "Server phase (1/2) complete. Reboot, log in via the Noctalia greeter, then run './install.sh --all' for pentest tools (phase 2/2)."
fi

# Do not prompt for reboot if only wallpaper & profile logo was deployed
if [ "$INSTALL_WALLPAPER" = true ] && [ "$RUN_ALL" = false ] && [ "$RUN_BASIC" = false ] && [ "$RUN_PACKAGES" = false ] && [ "$INSTALL_PIPX" = false ] && [ "$INSTALL_UPSTREAMS" = false ] && [ "$INSTALL_ZSH" = false ] && [ "$INSTALL_SWAY" = false ] && [ "$INSTALL_ALACRITTY" = false ] && [ "$INSTALL_NVIM" = false ] && [ "$INSTALL_DOCKER_CONTAINERS" = false ] && [ "$SET_HOSTNAME" = false ]; then
    REBOOT=false
fi

if [ "$REBOOT" = true ]; then
    echo
    echo -e "${BOLD}System Reboot${NC}"
    echo "===================================================="
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] sudo reboot"
    else
        log_info "A system reboot is required to apply shell changes, group permissions, and session targets."
        if [ -n "$ASSUME_YES" ]; then
            log_info "Rebooting system in 5 seconds (Press Ctrl+C to cancel)..."
            sleep 5
            sudo reboot
        else
            read -rp "Reboot system now? [Y/n]: " do_reboot
            if [[ ! "$do_reboot" =~ ^[Nn]$ ]]; then
                log_info "Rebooting system now..."
                sudo reboot
            else
                log_warn "Reboot deferred. Remember to reboot manually: sudo reboot"
            fi
        fi
    fi
fi
