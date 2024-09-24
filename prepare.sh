#!/bin/bash

set -e

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or using sudo."
    exit 1
fi

# Update the system and install necessary packages
echo "Updating system and installing required packages..."
apt update
apt upgrade -y
apt install -y build-essential git wget curl sudo jq rauc casync btrfs-progs squashfs-tools cpio python3 python3-pip openssl

# Create working directory
WORKDIR=~/fauxlo
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Variables
echo "Fetching information about the latest SteamOS version..."

# URL of the JSON file with the latest version info
JSON_URL="https://steamdeck-atomupd.steamos.cloud/meta/steamos/amd64/snapshot/steamdeck.json"

# Download and parse JSON
JSON_DATA=$(curl -s "$JSON_URL")

# Extract data from JSON using jq
IMAGE_URL_BASE="https://steamdeck-images.steamos.cloud"
BUILD_ID=$(echo "$JSON_DATA" | jq -r '.minor.candidates[0].image.buildid')
VERSION=$(echo "$JSON_DATA" | jq -r '.minor.candidates[0].image.version')
UPDATE_PATH=$(echo "$JSON_DATA" | jq -r '.minor.candidates[0].update_path')
IMAGE_URL="$IMAGE_URL_BASE/$UPDATE_PATH"

# Correctly form the CASYNC_STORE_URL
CASYNC_STORE_URL="${IMAGE_URL%.raucb}.castr"

echo "Latest version: $VERSION"
echo "BUILD_ID: $BUILD_ID"
echo "IMAGE_URL: $IMAGE_URL"
echo "CASYNC_STORE_URL: $CASYNC_STORE_URL"

# Save variables to a file for use in other scripts
cat > variables.sh <<EOL
export WORKDIR="$WORKDIR"
export BUILD_ID="$BUILD_ID"
export VERSION="$VERSION"
export IMAGE_URL="$IMAGE_URL"
export CASYNC_STORE_URL="$CASYNC_STORE_URL"
EOL

# Generate certificates and keys if they don't exist
echo "Generating certificates and keys..."
if [ ! -f key.pem ] || [ ! -f cert.pem ] || [ ! -f keyring.pem ]; then
    openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/CN=Custom SteamOS"
    cp cert.pem keyring.pem
fi

# Create 'custom-pacman.conf' file
echo "Creating 'custom-pacman.conf'..."
cat > custom-pacman.conf <<EOL
[options]
Architecture = auto
CheckSpace
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[fauxlo]
Server = https://your-repo-url/\$arch
SigLevel = Never

Include = /etc/pacman.d/mirrorlist
EOL

# Create 'client.conf' file
echo "Creating 'client.conf'..."
cat > client.conf <<EOL
[Server]
QueryUrl = https://your-update-server/updates
ImagesUrl = https://your-update-server/
MetaUrl = https://your-update-server/meta
Variants = rel;rc;beta;bc;main
EOL

# Check if rootfs.img exists
if [ -f rootfs.img ]; then
    echo "File rootfs.img already exists. Skipping casync download."
else
    # Download RAUC bundle
    echo "Downloading RAUC bundle..."
    wget -O rootfs.raucb "$IMAGE_URL"

    if [ ! -f rootfs.raucb ]; then
        echo "Failed to download RAUC bundle."
        exit 1
    fi

    # Remove existing rauc_bundle directory if it exists
    echo "Checking if rauc_bundle directory exists..."
    if [ -d "rauc_bundle" ]; then
        echo "rauc_bundle directory exists. Attempting to remove..."
        rm -rf rauc_bundle
        if [ -d "rauc_bundle" ]; then
            echo "Error: Failed to remove rauc_bundle directory."
            exit 1
        else
            echo "rauc_bundle directory successfully removed."
        fi
    else
        echo "rauc_bundle directory does not exist."
    fi

    # Extract 'rootfs.img.caibx' from RAUC bundle
    echo "Extracting 'rootfs.img.caibx' from RAUC bundle..."
    unsquashfs -d rauc_bundle rootfs.raucb
    cp rauc_bundle/rootfs.img.caibx .

    if [ ! -f rootfs.img.caibx ]; then
        echo "'rootfs.img.caibx' not found!"
        exit 1
    fi

    # Use casync to download the rootfs image
    echo "Starting 'casync extract'..."
    casync -v extract --store="$CASYNC_STORE_URL" rootfs.img.caibx rootfs.img
    echo "'casync extract' completed."
fi

# Randomize filesystem UUID
echo "Randomizing filesystem UUID..."
btrfstune -fu rootfs.img

# Check if rootfs.img is already mounted
if mountpoint -q rootfs; then
    echo "rootfs.img is already mounted. Unmounting..."
    umount -R rootfs
fi

# Mount the filesystem
echo "Mounting filesystem..."
mkdir -p rootfs
mount -o loop,compress=zstd rootfs.img rootfs

# Clear the read-only flag
btrfs property set -ts rootfs ro false

# Mount necessary filesystems
echo "Mounting necessary filesystems..."
mount -t devtmpfs dev rootfs/dev
mount -t proc proc rootfs/proc
mount -t sysfs sysfs rootfs/sys
mount -t tmpfs tmpfs rootfs/tmp
mount -t tmpfs -o mode=755 tmpfs rootfs/run
mount -t tmpfs -o mode=755 tmpfs rootfs/var
mount -t tmpfs -o mode=755 tmpfs rootfs/home

# Copy resolv.conf
echo "Copying resolv.conf..."
mount --bind "$(realpath /etc/resolv.conf)" rootfs/etc/resolv.conf

# Copy custom pacman configuration
echo "Copying custom pacman configuration..."
cp custom-pacman.conf rootfs/etc/pacman.conf

echo "Preparation complete. You can now run 'modify.sh' to make changes."