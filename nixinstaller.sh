#!/bin/bash

# Check if the user provided an app name
if [ -z "$1" ]; then
  echo "Usage: $0 <app-name>"
  exit 1
fi

# Store the app name in a variable
APP_NAME=$1

# Add the app to the system packages in configuration.nix
echo "Adding $APP_NAME to /etc/nixos/configuration.nix"

# Add the app to the environment.systemPackages array
sudo sed -i "/environment\.systemPackages = with pkgs; \[/a \ \ \ \ $APP_NAME" /etc/nixos/configuration.nix

# Rebuild the NixOS system to apply the changes
echo "Rebuilding NixOS..."
sudo nixos-rebuild switch

echo "$APP_NAME has been installed and system has been rebuilt."
