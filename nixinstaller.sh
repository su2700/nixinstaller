#!/bin/bash

# Simple Nix package installer / uninstaller helper
# Usage: ./nixinstaller.sh [app-name]
# If an app-name is provided, the script will prompt to install it (permanent or temporary).

CONFIG_FILE="/etc/nixos/configuration.nix"

backup_config() {
  if [ -f "$CONFIG_FILE" ]; then
    sudo cp "$CONFIG_FILE" "$CONFIG_FILE".bak.$(date +%s)
  fi
}

list_system_packages() {
  # Extract lines between the environment.systemPackages = ... [ and the closing ];
  if ! grep -q "environment\.systemPackages" "$CONFIG_FILE" 2>/dev/null; then
    return 1
  fi

  sed -n '/environment\.systemPackages/,/];/p' "$CONFIG_FILE" | sed '1d;$d' | \
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/,$//' | grep -v '^$'
}

remove_package_from_config() {
  pkg="$1"
  tmpfile=$(mktemp)

  # Re-write the configuration file, skipping the first matching package line inside the systemPackages block
  awk -v pkg="$pkg" '
  BEGIN{in_block=0; started=0; skipped=0}
  /environment\.systemPackages/ {print; in_block=1; next}
  in_block && /\[/ && !started {print; started=1; next}
  in_block && started && /\]/ {print; in_block=0; next}
  {
    if (in_block && started && !skipped) {
      line=$0
      gsub(/^[ \t]+|[ \t]+$/,"",line)
      sub(/,#.*/,"",line)
      sub(/#.*$/,"",line)
      sub(/,$/,"",line)
      if (line == pkg) { skipped=1; next }
    }
    print
  }
  END{ if (in_block && !skipped) exit 2 }
  ' "$CONFIG_FILE" > "$tmpfile"

  if [ $? -eq 0 ]; then
    sudo mv "$tmpfile" "$CONFIG_FILE"
    return 0
  else
    rm -f "$tmpfile"
    return 2
  fi
}

install_permanent() {
  pkg="$1"
  echo "Adding $pkg to $CONFIG_FILE"
  backup_config
  # Add package right after the opening '[' of environment.systemPackages
  sudo sed -i "/environment\.systemPackages = with pkgs; \[/a \ \ \ \ $pkg" "$CONFIG_FILE"
  echo "Rebuilding NixOS..."
  sudo nixos-rebuild switch
  echo "$pkg has been installed and system has been rebuilt."
}

install_temporary() {
  pkg="$1"
  echo "Launching nix-shell with $pkg..."
  nix-shell -p "$pkg"
}

do_update() {
  echo "Updating channels and rebuilding system..."
  sudo nix-channel --update || true
  sudo nixos-rebuild switch --upgrade
}

main_menu() {
  while true; do
    echo
    echo "Select an action:"
    echo "1) Install package (permanent or temporary)"
    echo "2) Uninstall package (from configuration.nix)"
    echo "3) Update system (channels + rebuild)"
    echo "4) Temporary nix-shell"
    echo "5) Quit"
    read -p "Enter choice [1-5]: " ACTION

    case "$ACTION" in
      1)
        read -p "Package name to install: " PKG
        if [ -z "$PKG" ]; then
          echo "No package name provided."; continue
        fi
        echo "Choose installation type:"
        echo "1) Permanent (system-wide, configuration.nix)"
        echo "2) Temporary (nix-shell)"
        read -p "Enter choice [1-2]: " CHOICE
        if [ "$CHOICE" == "1" ]; then
          install_permanent "$PKG"
        elif [ "$CHOICE" == "2" ]; then
          install_temporary "$PKG"
        else
          echo "Invalid choice.";
        fi
        ;;

      2)
        if [ ! -f "$CONFIG_FILE" ]; then
          echo "$CONFIG_FILE not found. Cannot uninstall."; continue
        fi
        mapfile -t pkgs < <(list_system_packages)
        if [ ${#pkgs[@]} -eq 0 ]; then
          echo "No packages found in environment.systemPackages."; continue
        fi
        echo "Installed packages (from $CONFIG_FILE):"
        for i in "${!pkgs[@]}"; do
          idx=$((i+1))
          echo "$idx) ${pkgs[$i]}"
        done
        read -p "Enter the number of the package to uninstall (or 'c' to cancel): " SEL
        if [ "$SEL" = "c" ] || [ "$SEL" = "C" ]; then
          echo "Cancelled."; continue
        fi
        if ! [[ "$SEL" =~ ^[0-9]+$ ]]; then
          echo "Invalid selection."; continue
        fi
        if [ "$SEL" -lt 1 ] || [ "$SEL" -gt ${#pkgs[@]} ]; then
          echo "Selection out of range."; continue
        fi
        target_pkg=${pkgs[$((SEL-1))]}
        echo "You chose to remove: $target_pkg"
        read -p "Proceed and rebuild system? [y/N]: " CONF
        if [[ "$CONF" =~ ^[Yy]$ ]]; then
          backup_config
          remove_package_from_config "$target_pkg"
          rc=$?
          if [ $rc -eq 0 ]; then
            echo "Package removed from $CONFIG_FILE. Rebuilding system..."
            sudo nixos-rebuild switch
            echo "Done."
          elif [ $rc -eq 2 ]; then
            echo "Package not found inside the systemPackages block; no changes made.";
          else
            echo "Failed to update $CONFIG_FILE.";
          fi
        else
          echo "Aborted by user.";
        fi
        ;;

      3)
        do_update
        ;;

      4)
        read -p "Package name for nix-shell: " PKG
        if [ -z "$PKG" ]; then echo "No package provided."; else install_temporary "$PKG"; fi
        ;;

      5)
        echo "Goodbye."; exit 0
        ;;

      *)
        echo "Invalid choice.";
        ;;
    esac
  done
}

# If an argument is provided, treat it as package name and go straight to install prompt
if [ -n "$1" ]; then
  APP_NAME="$1"
  echo "Package argument provided: $APP_NAME"
  echo "Choose installation type:"
  echo "1) Permanent (system-wide, configuration.nix)"
  echo "2) Temporary (nix-shell)"
  read -p "Enter choice [1-2]: " CHOICE
  if [ "$CHOICE" == "1" ]; then
    install_permanent "$APP_NAME"
    exit 0
  elif [ "$CHOICE" == "2" ]; then
    install_temporary "$APP_NAME"
    exit 0
  else
    echo "Invalid choice. Exiting."; exit 1
  fi
else
  main_menu
fi

