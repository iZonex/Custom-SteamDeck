#!/bin/bash

set -e

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or using sudo."
    exit 1
fi

# Load variables
source ./variables.sh

cd "$WORKDIR"

# Check if rootfs.img is mounted
if ! mountpoint -q rootfs; then
    echo "rootfs.img is not mounted. Please run 'prepare.sh' first."
    exit 1
fi

# Install custom packages (modify as needed)
echo "Installing custom packages..."
chroot rootfs pacman -Sy --noconfirm your-custom-package

echo "Modifications complete. You can now run 'finalize.sh' to build the custom image."