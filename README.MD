# Custom SteamOS Image Builder

This project allows you to create a custom SteamOS image by modifying the root filesystem and integrating a bootloader. The process is divided into three steps managed by separate scripts for better control and flexibility.

## Prerequisites

- A Debian-based Linux system (e.g., Ubuntu)
- Root or sudo access
- Internet connection

## Scripts Overview

- **main.sh**: The main script that orchestrates the entire process.
- **prepare.sh**: Prepares the environment, downloads the SteamOS image, and mounts the necessary filesystems.
- **modify.sh**: Performs modifications to the SteamOS image, such as installing additional packages.
- **finalize.sh**: Finalizes the image by installing the bootloader, unmounting filesystems, and creating the final RAUC bundle.

## Usage Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/iZonex/Custom-SteamDeck.git
cd Custom-SteamDeck
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

1. **Preparation**: Downloads and prepares the SteamOS image.
2. **Modification**: Pauses to allow you to modify the image (e.g., install packages).
3. **Finalization**: Creates the final custom SteamOS image with an integrated bootloader.

### 4. Pausing Between Steps

The `main.sh` script will pause after each step, waiting for you to press Enter before proceeding. This allows you to perform any additional actions if needed.

### 5. Customizing the Image

When the script pauses after the preparation step, you can:

- **Modify `modify.sh`**: Edit the script to install specific packages or make changes.
  
  ```bash
  nano modify.sh
  ```
  
  Replace `your-custom-package` with the packages you wish to install:
  
  ```bash
  chroot rootfs pacman -Sy --noconfirm vim nano
  ```

- **Manual Changes**: Optionally, you can manually chroot into the `rootfs` directory to perform additional customizations:
  
  ```bash
  chroot rootfs
  ```

### 6. Finalizing the Image

After making your modifications, press Enter when prompted to proceed to the finalization step. The script will then:

- Install `systemd-boot` as the bootloader.
- Update configuration files.
- Unmount filesystems.
- Create the final RAUC bundle containing your custom SteamOS image.

## Notes

- **Disk Space**: Ensure you have enough disk space to store the SteamOS image and the custom image.
- **Time**: The process may take some time, depending on your internet connection and system performance.
- **Root Privileges**: Always run the scripts with root privileges to avoid permission issues.

## Troubleshooting

- **Permission Denied Errors**: Ensure you're running the scripts with `sudo` or as the root user.
- **Missing Packages**: Install any missing packages indicated in error messages.
- **Internet Connectivity**: Verify that your system has a stable internet connection.
- **Bootloader Issues**: If the image still isn't bootable, ensure that the bootloader was correctly installed and configured. Verify the `steamos.conf` file in `rootfs/boot/loader/entries/` and ensure the paths to `vmlinuz-linux` and `initramfs-linux.img` are correct.

## License

This project is licensed under the MIT License.

## Disclaimer

This tool is intended for educational and development purposes. Use it responsibly and at your own risk.

---

## **Additional Steps to Ensure Bootloader Installation**

If after following the above scripts you still encounter bootloader issues, consider the following additional steps to ensure the bootloader is correctly installed and configured.

### **1. Verify Bootloader Installation**

After running `finalize.sh`, ensure that `systemd-boot` is properly installed in the `/boot` directory of your image.

```bash
ls rootfs/boot/loader/entries/
```

You should see a `steamos.conf` file with the correct configuration.

### **2. Check Boot Entry Configuration**

Ensure that the `steamos.conf` file correctly points to the kernel and initramfs images.

```bash
cat rootfs/boot/loader/entries/steamos.conf
```

It should look something like this:

```ini
title   SteamOS Custom
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=<UUID> rw
```

Replace `<UUID>` with the actual UUID of your `rootfs.img`. You can verify the UUID using:

```bash
blkid rootfs.img
```

### **3. Ensure Kernel and Initramfs Are Present**

Verify that the kernel (`vmlinuz-linux`) and initramfs (`initramfs-linux.img`) are present in the `/boot` directory of your image.

```bash
ls rootfs/vmlinuz-linux rootfs/initramfs-linux.img
```

If they are missing, you may need to install them:

```bash
chroot rootfs pacman -S linux linux-firmware
```

### **4. Re-run Finalization Script**

If you've made any changes, re-run the `finalize.sh` script to ensure all configurations are updated.

```bash
sudo ./finalize.sh
```

### **5. Create a Full Disk Image with ESP (Advanced)**

If you prefer to have a complete disk image with both ESP and rootfs partitions, follow these advanced steps:

1. **Create a Blank Disk Image:**

    ```bash
    dd if=/dev/zero of=custom-steamos.img bs=1M count=2048 # 2GB image
    ```

2. **Create GPT Partition Table and Partitions:**

    ```bash
    parted custom-steamos.img --script mklabel gpt
    parted custom-steamos.img --script mkpart primary fat32 1MiB 512MiB
    parted custom-steamos.img --script mkpart primary btrfs 512MiB 100%
    parted custom-steamos.img --script set 1 esp on
    ```

3. **Associate Image with Loop Devices:**

    ```bash
    LOOP_DEVICE=$(losetup -f --show -P custom-steamos.img)
    ```

4. **Format Partitions:**

    ```bash
    mkfs.fat -F32 "${LOOP_DEVICE}p1" # ESP
    mkfs.btrfs "${LOOP_DEVICE}p2" # rootfs
    ```

5. **Mount Partitions:**

    ```bash
    mkdir -p boot rootfs
    mount "${LOOP_DEVICE}p2" rootfs
    mkdir -p rootfs/boot
    mount "${LOOP_DEVICE}p1" rootfs/boot
    ```

6. **Install systemd-boot into ESP:**

    ```bash
    bootctl --path=rootfs/boot install
    ```

7. **Proceed with Rootfs Modifications:**

    - Copy your customized `rootfs.img` contents into the rootfs partition.
    - Ensure that the `steamos.conf` in `rootfs/boot/loader/entries/` points to the correct kernel and initramfs.

8. **Unmount and Detach Loop Devices:**

    ```bash
    umount -R rootfs
    losetup -d "$LOOP_DEVICE"
    ```

**Note:** Integrating these steps into your scripts requires careful handling of loop devices and partition management. Proceed with caution and ensure you have backups.
