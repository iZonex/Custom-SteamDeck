#!/bin/bash

set -ex

# Переменные
VERSION="3.5.7"
BUILD_ID=$(date +%Y%m%d.%H%M%S)
IMAGE_URL="https://steamdeck-images.steamos.cloud/steamdeck/20231122.1/steamdeck-20231122.1-3.5.7.raucb"
CASYNC_STORE_URL="https://steamdeck-images.steamos.cloud/steamdeck/20231122.1/steamdeck-20231122.1-3.5.7.castr"

# Отладочный вывод
echo "Текущий пользователь: $(whoami)"
echo "UID: $(id -u)"
echo "GID: $(id -g)"
echo "Рабочий каталог: $(pwd)"
echo "Содержимое рабочего каталога:"
ls -la

# Настройка прав доступа
sudo chown -R builder:builder /home/builder

# Создание необходимых директорий
mkdir -p ~/fauxlo/bundle
cd ~/fauxlo

# Загрузка RAUC-бандла
wget -O rootfs.raucb "$IMAGE_URL"
if [ ! -f rootfs.raucb ]; then
    echo "Не удалось загрузить RAUC-бандл."
    exit 1
fi

# Извлечение rootfs.img.caibx из RAUC-бандла
unsquashfs -d rauc_bundle rootfs.raucb
cp rauc_bundle/rootfs.img.caibx .

# Использование casync для загрузки образа rootfs
echo "Начало casync extract"
casync -vv extract --store="$CASYNC_STORE_URL" rootfs.img.caibx rootfs.img
echo "Завершение casync extract"


# Рандомизация UUID файловой системы
sudo btrfstune -fu rootfs.img

# Монтирование файловой системы
mkdir rootfs
sudo mount -o loop,compress=zstd rootfs.img rootfs

# Снятие флага только для чтения
sudo btrfs property set -ts rootfs ro false

# Монтирование необходимых файловых систем
sudo mount -t proc /proc rootfs/proc
sudo mount --bind /dev rootfs/dev
sudo mount -t sysfs sysfs rootfs/sys
sudo mount -t tmpfs tmpfs rootfs/tmp
sudo mount -t tmpfs tmpfs rootfs/run
sudo mount -t tmpfs tmpfs rootfs/var
sudo mount -t tmpfs tmpfs rootfs/home

# Монтирование resolv.conf
sudo mount --bind /etc/resolv.conf rootfs/etc/resolv.conf

# Копирование пользовательского репозитория
sudo cp custom-pacman.conf rootfs/etc/pacman.conf

# Установка пользовательских пакетов
sudo arch-chroot rootfs pacman -Sy --noconfirm your-custom-package

# Обновление manifest.json и os-release
sudo sed -i "s/\"buildid\": \".*\"/\"buildid\": \"$BUILD_ID\"/" rootfs/lib/steamos-atomupd/manifest.json
sudo sed -i "s/BUILD_ID=.*/BUILD_ID=$BUILD_ID/" rootfs/etc/os-release

# Обновление RAUC keyring и конфигурации клиента
sudo cp keyring.pem rootfs/etc/rauc/keyring.pem
sudo cp client.conf rootfs/etc/steamos-atomupd/client.conf

# Установка флага только для чтения
sudo btrfs property set -ts rootfs ro true

# Размонтирование файловых систем
sudo umount -R rootfs

# Обрезка файловой системы
sudo fstrim -v rootfs.img

# Создание casync хранилища и индекса
mkdir bundle
casync make --store=rootfs.img.castr bundle/rootfs.img.caibx rootfs.img

# Генерация manifest.raucm
cat >bundle/manifest.raucm <<EOF
[update]
compatible=steamos-amd64
version=$VERSION

[image.rootfs]
sha256=$(sha256sum rootfs.img | awk '{ print $1 }')
size=$(stat -c %s rootfs.img)
filename=rootfs.img.caibx
EOF

# Генерация файла UUID
blkid -s UUID -o value rootfs.img >bundle/UUID

# Подписывание и создание RAUC-бандла
rauc bundle \
    --signing-keyring=cert.pem \
    --cert=cert.pem \
    --key=key.pem \
    bundle rootfs-custom.raucb

echo "Кастомный образ SteamOS успешно создан!"