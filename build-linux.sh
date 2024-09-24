#!/bin/bash

set -e

# Скрипт для автоматической установки зависимостей и сборки кастомного образа SteamOS на Ubuntu x86_64

# Проверка запуска от root или через sudo
if [ "$EUID" -ne 0 ]
then
    echo "Пожалуйста, запустите этот скрипт от имени root или через sudo."
    exit 1
fi

# Обновление системы и установка базовых инструментов
echo "Обновление системы и установка базовых пакетов..."
apt update
apt upgrade -y
apt install -y build-essential git wget curl sudo

# Установка зависимостей
echo "Установка зависимостей..."

# Установка casync из стандартных репозиториев
echo "Установка casync..."
apt install -y casync

# Установка rauc
echo "Установка rauc..."
apt install -y rauc

# Установка других необходимых пакетов
echo "Установка других необходимых пакетов..."
apt install -y btrfs-progs squashfs-tools cpio python3 python3-pip openssl

# Создание пользователя 'builder' (опционально)
echo "Создание пользователя 'builder'..."
useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD:ALL' | tee /etc/sudoers.d/builder

# Переход под пользователя 'builder'
echo "Переход под пользователя 'builder'..."
sudo -u builder -i bash << EOF

set -e

# Переменные
VERSION="3.5.7"
BUILD_ID=\$(date +%Y%m%d.%H%M%S)
IMAGE_URL="https://steamdeck-images.steamos.cloud/steamdeck/20231122.1/steamdeck-20231122.1-3.5.7.raucb"
CASYNC_STORE_URL="https://steamdeck-images.steamos.cloud/steamdeck/20231122.1/steamdeck-20231122.1-3.5.7.castr"

# Создание рабочего каталога
echo "Создание рабочего каталога..."
mkdir -p \$HOME/fauxlo
cd \$HOME/fauxlo

# Генерация сертификатов и ключей
echo "Генерация сертификатов и ключей..."
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/CN=Custom SteamOS"
cp cert.pem keyring.pem

# Создание файла 'custom-pacman.conf'
echo "Создание 'custom-pacman.conf'..."
cat > custom-pacman.conf << EOL
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

# Создание файла 'client.conf'
echo "Создание 'client.conf'..."
cat > client.conf << EOL
[Server]
QueryUrl = https://your-update-server/updates
ImagesUrl = https://your-update-server/
MetaUrl = https://your-update-server/meta
Variants = rel;rc;beta;bc;main
EOL

# Загрузка RAUC-бандла
echo "Загрузка RAUC-бандла..."
wget -O rootfs.raucb "\$IMAGE_URL"

if [ ! -f rootfs.raucb ]; then
    echo "Не удалось загрузить RAUC-бандл."
    exit 1
fi

# Извлечение 'rootfs.img.caibx' из RAUC-бандла
echo "Извлечение 'rootfs.img.caibx' из RAUC-бандла..."
unsquashfs -d rauc_bundle rootfs.raucb
cp rauc_bundle/rootfs.img.caibx .

if [ ! -f rootfs.img.caibx ]; then
    echo "'rootfs.img.caibx' не найден!"
    exit 1
fi

# Использование casync для загрузки образа rootfs
echo "Начало 'casync extract'..."
casync -v extract --store="\$CASYNC_STORE_URL" rootfs.img.caibx rootfs.img
echo "'casync extract' завершен."

# Рандомизация UUID файловой системы
echo "Рандомизация UUID файловой системы..."
sudo btrfstune -fu rootfs.img

# Монтирование файловой системы
echo "Монтирование файловой системы..."
mkdir rootfs
sudo mount -o loop,compress=zstd rootfs.img rootfs

# Снятие флага только для чтения
sudo btrfs property set -ts rootfs ro false

# Монтирование необходимых файловых систем
echo "Монтирование необходимых файловых систем..."
sudo mount --bind /dev rootfs/dev
sudo mount -t proc /proc rootfs/proc
sudo mount -t sysfs sysfs rootfs/sys
sudo mount -t tmpfs tmpfs rootfs/tmp
sudo mount -t tmpfs tmpfs rootfs/run
sudo mount -t tmpfs tmpfs rootfs/var
sudo mount -t tmpfs tmpfs rootfs/home

# Копирование resolv.conf
sudo cp /etc/resolv.conf rootfs/etc/resolv.conf

# Копирование пользовательского конфигурационного файла pacman
sudo cp custom-pacman.conf rootfs/etc/pacman.conf

# Установка пользовательских пакетов (измените по необходимости)
echo "Установка пользовательских пакетов..."
sudo chroot rootfs pacman -Sy --noconfirm your-custom-package

# Обновление 'manifest.json' и 'os-release'
echo "Обновление 'manifest.json' и 'os-release'..."
sudo sed -i "s/\"buildid\": \".*\"/\"buildid\": \"\$BUILD_ID\"/" rootfs/lib/steamos-atomupd/manifest.json
sudo sed -i "s/BUILD_ID=.*/BUILD_ID=\$BUILD_ID/" rootfs/etc/os-release

# Обновление RAUC keyring и конфигурации клиента
sudo cp keyring.pem rootfs/etc/rauc/keyring.pem
sudo cp client.conf rootfs/etc/steamos-atomupd/client.conf

# Установка флага только для чтения
sudo btrfs property set -ts rootfs ro true

# Размонтирование файловых систем
echo "Размонтирование файловых систем..."
sudo umount -R rootfs

# Обрезка файловой системы
sudo fstrim -v rootfs.img

# Создание casync хранилища и индекса
echo "Создание casync хранилища и индекса..."
mkdir bundle
casync make --store=rootfs.img.castr bundle/rootfs.img.caibx rootfs.img

# Генерация 'manifest.raucm'
echo "Генерация 'manifest.raucm'..."
cat > bundle/manifest.raucm << EOL
[update]
compatible=steamos-amd64
version=\$VERSION

[image.rootfs]
sha256=\$(sha256sum rootfs.img | awk '{ print \$1 }')
size=\$(stat -c %s rootfs.img)
filename=rootfs.img.caibx
EOL

# Генерация файла UUID
blkid -s UUID -o value rootfs.img > bundle/UUID

# Создание RAUC-бандла
echo "Создание RAUC-бандла..."
rauc bundle \
    --signing-keyring=cert.pem \
    --cert=cert.pem \
    --key=key.pem \
    bundle rootfs-custom.raucb

echo "Кастомный образ SteamOS успешно создан!"

EOF

echo "Процесс сборки завершен."