#!/usr/bin/env bash
# usp - LightOS Unified Package Manager (APT + Flatpak --user)
set -e
FLATPAK_USER_DIR="$HOME/.local/share/flatpak"
[ ! -d "$FLATPAK_USER_DIR" ] && flatpak config --user languages="*" &>/dev/null || true
usage() {
    cat <<EOF
usp – LightOS Unified Package Manager
Commands:
  search <term>        Search APT and Flathub
  install <pkg>        Install a package (choose source if both available)
  remove <pkg>         Remove from whatever source installed it
  run <pkg>            Launch an installed application
  update               Update APT and Flatpak user apps
  list                 Show manually installed APT and user Flatpak apps
EOF
    exit 1
}
flatpak_installed() { flatpak list --user --columns=application 2>/dev/null | grep -Fxq "$1"; }
apt_installed() { dpkg -l "$1" 2>/dev/null | grep -q '^ii'; }
find_flatpak_id() { flatpak search --user "$1" 2>/dev/null | head -1 | awk '{print $1}'; }
search() {
    echo -e "\e[1m=== APT Packages ===\e[0m"
    apt-cache search "$1" 2>/dev/null | head -20 || true
    echo -e "\n\e[1m=== Flatpak Applications (Flathub) ===\e[0m"
    flatpak search "$1" 2>/dev/null | head -20 || true
}
install() {
    local pkg="$1"
    local apt_candidate=$(apt-cache search "^${pkg}$" 2>/dev/null | awk '{print $1}' | head -1)
    local fp_id=$(find_flatpak_id "$pkg")
    if [ -z "$apt_candidate" ] && [ -z "$fp_id" ]; then echo "Not found."; exit 1; fi
    if [ -z "$apt_candidate" ]; then
        echo "Installing Flatpak (user): $fp_id"
        flatpak install --user -y flathub "$fp_id"
    elif [ -z "$fp_id" ]; then
        echo "Installing APT: $apt_candidate"
        sudo apt install -y "$apt_candidate"
    else
        echo "Found two options:"
        echo "  1) APT: $apt_candidate"
        echo "  2) Flatpak: $fp_id"
        read -p "Choose [1/2]: " choice
        case "$choice" in
            1) sudo apt install -y "$apt_candidate" ;;
            2) flatpak install --user -y flathub "$fp_id" ;;
            *) echo "Invalid"; exit 1 ;;
        esac
    fi
}
remove() {
    local pkg="$1"
    if apt_installed "$pkg"; then
        sudo apt remove --purge -y "$pkg" && echo "Removed APT: $pkg"
        return
    fi
    local fp_id=$(find_flatpak_id "$pkg")
    if [ -n "$fp_id" ] && flatpak_installed "$fp_id"; then
        flatpak uninstall --user -y "$fp_id" && echo "Removed Flatpak: $fp_id"
        return
    fi
    echo "Not installed."
    exit 1
}
run() {
    local pkg="$1"
    local desktop=$(find /usr/share/applications -name "*${pkg}*.desktop" 2>/dev/null | head -1)
    if [ -n "$desktop" ]; then
        gtk-launch "$(basename "$desktop" .desktop)" 2>/dev/null || exit 1
        return
    fi
    local fp_id=$(find_flatpak_id "$pkg")
    if [ -n "$fp_id" ] && flatpak_installed "$fp_id"; then
        flatpak run --user "$fp_id"
        return
    fi
    echo "No executable found for '$pkg'."
    exit 1
}
update() {
    echo "Updating APT..."; sudo apt update && sudo apt upgrade -y
    echo "Updating Flatpak..."; flatpak update --user -y
}
list() {
    echo "=== APT manual packages ==="
    comm -23 <(apt-mark showmanual | sort) <(gzip -dc /var/log/installer/initial-status.gz | grep '^Package:' | cut -d' ' -f2 | sort) 2>/dev/null || echo "(unknown baseline)"
    echo -e "\n=== Flatpak (user) ==="
    flatpak list --user --columns=application,name 2>/dev/null || echo "none"
}
[ $# -lt 1 ] && usage
cmd="$1"; shift
case "$cmd" in
    search)  search "$@" ;;
    install) install "$@" ;;
    remove)  remove "$@" ;;
    run)     run "$@" ;;
    update)  update ;;
    list)    list ;;
    *) usage ;;
esac