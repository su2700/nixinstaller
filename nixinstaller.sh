#!/bin/bash

#!/bin/bash

# Check if the user provided an app name
if [ -z "$1" ]; then
  echo "Usage: $0 <app-name>"
  exit 1
fi

APP_NAME=$1

echo "Choose installation type:"
echo "1) Permanent (system-wide, configuration.nix)"
echo "2) Temporary (nix-shell)"
read -p "Enter choice [1-2]: " CHOICE

if [ "$CHOICE" == "1" ]; then
  echo "Adding $APP_NAME to /etc/nixos/configuration.nix"
  sudo sed -i "/environment\.systemPackages = with pkgs; \[/a \ \ \ \ $APP_NAME" /etc/nixos/configuration.nix
  echo "Rebuilding NixOS..."
  sudo nixos-rebuild switch
  echo "$APP_NAME has been installed and system has been rebuilt."
elif [ "$CHOICE" == "2" ]; then
  echo "Launching nix-shell with $APP_NAME..."
  nix-shell -p $APP_NAME
else
  echo "Invalid choice. Exiting."
  exit 1
fi
