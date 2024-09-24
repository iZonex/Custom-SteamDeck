#!/bin/bash

set -e

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or using sudo."
    exit 1
fi

# Set execute permissions for the other scripts
chmod +x prepare.sh modify.sh finalize.sh

# Run the preparation script
echo "Starting preparation script..."
./prepare.sh

# Wait for user input before proceeding to the next step
read -p "Preparation complete. Press Enter to proceed to modification."

# Run the modification script
echo "Starting modification script..."
./modify.sh

# Wait for user input before proceeding to the finalization step
read -p "Modification complete. Press Enter to proceed to finalization."

# Run the finalization script
echo "Starting finalization script..."
./finalize.sh

echo "Process completed."