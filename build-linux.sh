#!/bin/bash

set -e

# Проверка запуска от root или через sudo
if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите этот скрипт от имени root или используя sudo."
    exit 1
fi

# Обновление системы и установка базовых инструментов
echo "Обновление системы и установка базовых пакетов..."
apt update
apt upgrade -y
apt install -y build-essential git wget curl sudo jq

# Установка зависимостей
echo "Установка зависимостей..."

# Установка desync
echo "Установка desync..."
wget https://github.com/folbricht/desync/releases/download/v0.9.0/desync_0.9.0_linux_amd64.deb
sudo dpkg -i desync_0.9.0_linux_amd64.deb
sudo apt-get install -f -y  # Установка недостающих зависимостей

# Установка rauc
echo "Установка rauc..."
apt install -y rauc

# Установка других необходимых пакетов
echo "Установка других необходимых пакетов..."
apt install -y btrfs-progs squashfs-tools cpio python3 python3-pip openssl

# Переменные
echo "Получение информации о последней версии SteamOS..."

# URL JSON-файла с информацией о последней версии
JSON_URL="https://steamdeck-atomupd.steamos.cloud/meta/steamos/amd64/snapshot/steamdeck.json"

# Загрузка и парсинг JSON
JSON_DATA=$(curl -s "$JSON_URL")

# Извлечение данных из JSON с помощью jq
IMAGE_URL_BASE="https://steamdeck-images.steamos.cloud"
BUILD_ID=$(echo "$JSON_DATA" | jq -r '.minor.candidates[0].image.buildid')
VERSION=$(echo "$JSON_DATA" | jq -r '.minor.candidates[0].image.version')
UPDATE_PATH=$(echo "$JSON_DATA" | jq -r '.minor.candidates[0].update_path')
IMAGE_URL="$IMAGE_URL_BASE/$UPDATE_PATH"
CASYNC_STORE_URL="${IMAGE_URL_BASE}/${UPDATE_PATH%/*}/$(basename "$IMAGE_URL" .raucb).castr/"

echo "Последняя версия: $VERSION"
echo "BUILD_ID: $BUILD_ID"
echo "IMAGE_URL: $IMAGE_URL"
echo "CASYNC_STORE_URL: $CASYNC_STORE_URL"

# Создание рабочего каталога
echo "Создание рабочего каталога..."
mkdir -p ~/fauxlo
cd ~/fauxlo

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
wget -O rootfs.raucb "$IMAGE_URL"

if [ ! -f rootfs.raucb ]; then
    echo "Не удалось загрузить RAUC-бандл."
    exit 1
fi

# Проверка и удаление существующей директории rauc_bundle
echo "Проверяем, существует ли директория rauc_bundle..."
if [ -d "rauc_bundle" ]; then
    echo "Директория rauc_bundle существует. Пытаемся удалить..."
    rm -rf rauc_bundle
    if [ -d "rauc_bundle" ]; then
        echo "Ошибка: не удалось удалить директорию rauc_bundle"
        exit 1
    else
        echo "Директория rauc_bundle успешно удалена."
    fi
else
    echo "Директория rauc_bundle не существует."
fi

# Извлечение 'rootfs.img.caibx' из RAUC-бандла
echo "Извлечение 'rootfs.img.caibx' из RAUC-бандла..."
unsquashfs -d rauc_bundle rootfs.raucb
cp rauc_bundle/rootfs.img.caibx .

if [ ! -f rootfs.img.caibx ]; then
    echo "'rootfs.img.caibx' не найден!"
    exit 1
fi

# Использование desync для загрузки образа rootfs
echo "Начало 'desync extract'..."
desync -v extract --store "$CASYNC_STORE_URL" rootfs.img.caibx rootfs.img
echo "'desync extract' завершен."

# Рандомизация UUID файловой системы
echo "Рандомизация UUID файловой системы..."
btrfstune -fu rootfs.img

# Монтирование файловой системы
echo "Монтирование файловой системы..."
mkdir rootfs
mount -o loop,compress=zstd rootfs.img rootfs

# Снятие флага только для чтения
btrfs property set -ts rootfs ro false

# Монтирование необходимых файловых систем
echo "Монтирование необходимых файловых систем..."
mount --bind /dev rootfs/dev
mount -t proc /proc rootfs/proc
mount -t sysfs sysfs rootfs/sys
mount -t tmpfs tmpfs rootfs/tmp
mount -t tmpfs tmpfs rootfs/run
mount -t tmpfs tmpfs rootfs/var
mount -t tmpfs tmpfs rootfs/home

# Копирование resolv.conf
cp /etc/resolv.conf rootfs/etc/resolv.conf

# Копирование пользовательского конфигурационного файла pacman
cp custom-pacman.conf rootfs/etc/pacman.conf

# Установка пользовательских пакетов (измените по необходимости)
echo "Установка пользовательских пакетов..."
chroot rootfs pacman -Sy --noconfirm your-custom-package

# Обновление 'manifest.json' и 'os-release'
echo "Обновление 'manifest.json' и 'os-release'..."
sed -i "s/\"buildid\": \".*\"/\"buildid\": \"$BUILD_ID\"/" rootfs/lib/steamos-atomupd/manifest.json
sed -i "s/BUILD_ID=.*/BUILD_ID=$BUILD_ID/" rootfs/etc/os-release

# Обновление RAUC keyring и конфигурации клиента
cp keyring.pem rootfs/etc/rauc/keyring.pem
cp client.conf rootfs/etc/steamos-atomupd/client.conf

# Установка флага только для чтения
btrfs property set -ts rootfs ro true

# Размонтирование файловых систем
echo "Размонтирование файловых систем..."
umount -R rootfs

# Обрезка файловой системы
fstrim -v rootfs.img

# Создание desync хранилища и индекса
echo "Создание desync хранилища и индекса..."
mkdir bundle
desync make --store rootfs.img.castr bundle/rootfs.img.caibx rootfs.img

# Генерация 'manifest.raucm'
echo "Генерация 'manifest.raucm'..."
cat > bundle/manifest.raucm << EOL
[update]
compatible=steamos-amd64
version=$VERSION

[image.rootfs]
sha256=$(sha256sum rootfs.img | awk '{ print $1 }')
size=$(stat -c %s rootfs.img)
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

echo "Процесс сборки завершен."