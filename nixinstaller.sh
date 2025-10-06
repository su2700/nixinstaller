#!/usr/bin/env bash
# --------------------------------------------------------------
# NixOS Package Manager Helper
# Version: 2.2
# --------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

CONFIG_FILE="/etc/nixos/configuration.nix"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No color

# --- Root Check ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run this script as root (sudo $0)${NC}" >&2
  exit 1
fi

# --- Utility Functions ---
backup_config() {
  if [ -f "$CONFIG_FILE" ]; then
    local backup_name="${CONFIG_FILE}.bak.$(date +%s)"
    cp "$CONFIG_FILE" "$backup_name"
    echo -e "${GREEN}Backup created:${NC} $backup_name"
  fi
}

list_system_packages() {
  if ! grep -q "environment\.systemPackages" "$CONFIG_FILE"; then
    echo -e "${YELLOW}No environment.systemPackages block found.${NC}"
    return 1
  fi

  awk '
    BEGIN { in_block=0; started=0 }
    /environment\.systemPackages/ { in_block=1 }
    in_block && /\[/ && !started { started=1; next }
    in_block && /];/ { exit }
    in_block && started {
      line=$0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      sub(/#.*$/, "", line)
      sub(/,$/, "", line)
      sub(/^pkgs\./, "", line)
      if (length(line) > 0) print line
    }
  ' "$CONFIG_FILE"
}

add_environment_block_if_missing() {
  if ! grep -q "environment\.systemPackages" "$CONFIG_FILE"; then
    echo -e "${YELLOW}Adding environment.systemPackages block...${NC}"
    backup_config
    awk '
      BEGIN { inserted=0 }
      /^}$/ && !inserted {
        print "  environment.systemPackages = with pkgs; ["
        print "    # Add packages here"
        print "  ];"
        inserted=1
      }
      { print }
    ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  fi
}

install_permanent() {
  local pkg="$1"
  add_environment_block_if_missing

  if list_system_packages | grep -qx "$pkg"; then
    echo -e "${YELLOW}Package '$pkg' is already installed.${NC}"
    return
  fi

  backup_config
  echo -e "${BLUE}Adding ${pkg} to ${CONFIG_FILE}...${NC}"

  awk -v pkg="$pkg" '
    BEGIN { added=0 }
    /environment\.systemPackages[[:space:]]*=[[:space:]]*with[[:space:]]*pkgs;[[:space:]]*\[/ {
      print; printf("    %s,\n", pkg); added=1; next
    }
    { print }
    END {
      if (!added) print "Warning: could not add package."
    }
  ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"

  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo -e "${GREEN}Rebuilding NixOS...${NC}"
  nixos-rebuild switch
  echo -e "${GREEN}Installed '$pkg' successfully.${NC}"
}

install_temporary() {
  local pkg="$1"
  echo -e "${BLUE}Launching temporary nix-shell with '${pkg}'...${NC}"
  nix-shell -p "$pkg"
}

remove_package() {
  local pkg="$1"
  echo -e "${BLUE}Removing '$pkg' from all Nix configs...${NC}"
  backup_config

  local found=0
  while IFS= read -r file; do
    if grep -qE "pkgs\.${pkg}|[^a-zA-Z0-9_]${pkg}[^a-zA-Z0-9_]" "$file"; then
      sed -i "/pkgs\.${pkg}/d;/${pkg}[[:space:]]*,$/d;/${pkg}[[:space:]]*$/d" "$file"
      echo "  → Edited: $file"
      found=1
    fi
  done < <(find /etc/nixos -type f -name "*.nix")

  if [ $found -eq 0 ]; then
    echo -e "${YELLOW}Package '${pkg}' not found in configuration.${NC}"
    return
  fi

  echo -e "${GREEN}Rebuilding system...${NC}"
  nixos-rebuild switch
  echo -e "${GREEN}Package '${pkg}' removed and system rebuilt.${NC}"
}

do_update() {
  echo -e "${BLUE}Updating channels and rebuilding system...${NC}"
  nix-channel --update || true
  nixos-rebuild switch --upgrade
  echo -e "${GREEN}System updated successfully.${NC}"
}

view_installed() {
  echo -e "${BLUE}Installed system packages:${NC}"
  local pkgs
  mapfile -t pkgs < <(list_system_packages)
  if [ ${#pkgs[@]} -eq 0 ]; then
    echo -e "${YELLOW}(none found)${NC}"
    return
  fi
  for i in "${!pkgs[@]}"; do
    echo "$((i+1))) ${pkgs[$i]}"
  done
}

# --- Main Menu ---
main_menu() {
  while true; do
    echo
    echo -e "${BLUE}=== NixOS Package Manager Helper ===${NC}"
    echo "1) Install package (permanent or temporary)"
    echo "2) Uninstall package"
    echo "3) Update system"
    echo "4) Temporary nix-shell"
    echo "5) View installed packages"
    echo "6) Quit"
    read -rp "Enter choice [1-6]: " ACTION

    case "$ACTION" in
      1)
        read -rp "Package name to install: " PKG
        [ -z "$PKG" ] && echo "No package name provided." && continue
        echo "1) Permanent"
        echo "2) Temporary"
        read -rp "Enter choice [1-2]: " TYPE
        [[ "$TYPE" == "1" ]] && install_permanent "$PKG" || install_temporary "$PKG"
        ;;
      2)
        local pkgs
        mapfile -t pkgs < <(list_system_packages)
        if [ ${#pkgs[@]} -eq 0 ]; then
          echo -e "${YELLOW}No packages found in systemPackages.${NC}"
          continue
        fi

        echo -e "${BLUE}Installed system packages:${NC}"
        for i in "${!pkgs[@]}"; do
          echo "$((i+1))) ${pkgs[$i]}"
        done
        echo
        read -rp "Enter number of package to uninstall: " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#pkgs[@]}" ]; then
          target_pkg="${pkgs[$((CHOICE-1))]}"
          read -rp "Confirm removal of '$target_pkg'? [y/N]: " CONFIRM
          if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            remove_package "$target_pkg"
          else
            echo "Cancelled."
          fi
        else
          echo -e "${YELLOW}Invalid selection.${NC}"
        fi
        ;;
      3) do_update ;;
      4)
        read -rp "Package name for nix-shell: " PKG
        [ -z "$PKG" ] && continue
        install_temporary "$PKG"
        ;;
      5) view_installed ;;
      6)
        echo -e "${GREEN}Goodbye!${NC}"
        exit 0
        ;;
      *) echo -e "${YELLOW}Invalid choice.${NC}" ;;
    esac
  done
}

# --- CLI Shortcut Mode ---
if [[ "${1:-}" == "-y" && -n "${2:-}" ]]; then
  install_permanent "$2"
  exit 0
elif [ -n "${1:-}" ]; then
  PKG="$1"
  echo "1) Permanent"
  echo "2) Temporary"
  read -rp "Enter choice [1-2]: " CHOICE
  [[ "$CHOICE" == "1" ]] && install_permanent "$PKG" || install_temporary "$PKG"
  exit 0
else
  main_menu
fi
