# Custom SteamOS Image Builder

This project allows you to create a custom SteamOS image by modifying the root filesystem and repackaging it. The process is divided into three steps managed by separate scripts for better control and flexibility.

## Prerequisites

- A Debian-based Linux system (e.g., Ubuntu)
- Root or sudo access
- Internet connection

## Scripts Overview

- **main.sh**: The main script that orchestrates the entire process.
- **prepare.sh**: Prepares the environment, downloads the SteamOS image, and mounts the necessary filesystems.
- **modify.sh**: Allows you to make modifications to the SteamOS image, such as installing additional packages.
- **finalize.sh**: Finalizes the image by applying updates, unmounting filesystems, and creating the final RAUC bundle.

## Usage Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/your-repo/custom-steamos-builder.git
cd custom-steamos-builder
```

### 2. Update Configuration Files

Before running the scripts, update the following files with your custom configurations:

- **custom-pacman.conf**: Update the `[fauxlo]` repository URL.
- **client.conf**: Update the server URLs.

### 3. Run the Main Script

Execute the main script with root privileges:

```bash
sudo ./main.sh
```

The script will perform the following steps:

- **Preparation**: Downloads and prepares the SteamOS image.
- **Modification**: Pauses to allow you to modify the image (e.g., install packages).
- **Finalization**: Creates the final custom SteamOS image.

### 4. Pausing Between Steps

The `main.sh` script will pause after each step, waiting for you to press Enter before proceeding. This allows you to perform any additional actions if needed.

### 5. Customizing the Image

When the script pauses after the preparation step, you can:

- Modify the `modify.sh` script to install specific packages or make changes.
- Manually chroot into the `rootfs` directory to make additional changes.

### 6. Finalizing the Image

After making your modifications, press Enter when prompted to proceed to the finalization step. The script will then create the final RAUC bundle containing your custom SteamOS image.

## Notes

- Ensure you have enough disk space to store the SteamOS image and the custom image.
- The process may take some time, depending on your internet connection and system performance.
- Always run the scripts with root privileges to avoid permission issues.

## Troubleshooting

- **Permission Denied Errors**: Ensure you're running the scripts with `sudo` or as the root user.
- **Missing Packages**: Install any missing packages indicated in error messages.
- **Internet Connectivity**: Verify that your system has a stable internet connection.

## License

This project is licensed under the MIT License.

## Disclaimer

This tool is intended for educational and development purposes. Use it responsibly and at your own risk.
