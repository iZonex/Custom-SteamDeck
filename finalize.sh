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
    echo "rootfs.img is not mounted. Please run 'prepare.sh' and 'modify.sh' first."
    exit 1
fi

# Update 'manifest.json' and 'os-release'
echo "Updating 'manifest.json' and 'os-release'..."
sed -i "s/\"buildid\": \".*\"/\"buildid\": \"$BUILD_ID\"/" rootfs/lib/steamos-atomupd/manifest.json
sed -i "s/BUILD_ID=.*/BUILD_ID=$BUILD_ID/" rootfs/etc/os-release

# Update RAUC keyring and client configuration
echo "Updating RAUC keyring and client configuration..."
cp keyring.pem rootfs/etc/rauc/keyring.pem
cp client.conf rootfs/etc/steamos-atomupd/client.conf

# Set the read-only flag
echo "Setting the filesystem to read-only..."
btrfs property set -ts rootfs ro true

# Trim the filesystem
echo "Trimming the filesystem..."
fstrim -v rootfs

# Unmount filesystems
echo "Unmounting filesystems..."
umount --recursive rootfs

# Create casync store and index
echo "Creating casync store and index..."
mkdir -p bundle
casync make --store=rootfs.img.castr bundle/rootfs.img.caibx rootfs.img

# Generate 'manifest.raucm'
echo "Generating 'manifest.raucm'..."
cat > bundle/manifest.raucm <<EOL
[update]
compatible=steamos-amd64
version=$VERSION

[image.rootfs]
sha256=$(sha256sum rootfs.img | awk '{ print $1 }')
size=$(stat -c %s rootfs.img)
filename=rootfs.img.caibx
EOL

# Generate UUID file
echo "Generating UUID file..."
blkid -s UUID -o value rootfs.img > bundle/UUID

# Create RAUC bundle
echo "Creating RAUC bundle..."
rauc bundle \
    --signing-keyring=cert.pem \
    --cert=cert.pem \
    --key=key.pem \
    bundle rootfs-custom.raucb

echo "Custom SteamOS image successfully created!"