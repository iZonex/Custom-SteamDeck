#!/bin/bash

# Скрипт для автоматической загрузки последней версии корневой файловой системы SteamOS.

# Проверка наличия необходимых утилит
if ! command -v curl &> /dev/null; then
    echo "Команда curl не найдена. Пожалуйста, установите curl."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Команда jq не найдена. Пожалуйста, установите jq."
    exit 1
fi

if ! command -v unsquashfs &> /dev/null; then
    echo "Команда unsquashfs не найдена. Пожалуйста, установите squashfs-tools."
    exit 1
fi

if ! command -v casync &> /dev/null; then
    echo "Команда casync не найдена. Пожалуйста, установите casync."
    exit 1
fi

echo "Получение информации о последней версии SteamOS..."

# URL JSON-файла с информацией о последней версии
JSON_URL="https://steamdeck-atomupd.steamos.cloud/meta/steamos/amd64/snapshot/steamdeck.json"

# Загрузка и парсинг JSON
JSON_DATA=$(curl -s "$JSON_URL")

# Проверка успешности загрузки JSON
if [ -z "$JSON_DATA" ]; then
    echo "Не удалось загрузить информацию о последней версии."
    exit 1
fi

# Извлечение данных из JSON с помощью jq
IMAGE_URL_BASE="https://steamdeck-images.steamos.cloud"
BUILD_ID=$(echo "$JSON_DATA" | jq -r '.minor.candidates[0].image.buildid')
VERSION=$(echo "$JSON_DATA" | jq -r '.minor.candidates[0].image.version')
UPDATE_PATH=$(echo "$JSON_DATA" | jq -r '.minor.candidates[0].update_path')
IMAGE_URL="$IMAGE_URL_BASE/$UPDATE_PATH"

# Проверка наличия необходимых данных
if [ -z "$BUILD_ID" ] || [ -z "$VERSION" ] || [ -z "$UPDATE_PATH" ]; then
    echo "Не удалось получить необходимую информацию из JSON."
    exit 1
fi

# Формирование URL для хранилища casync
CASTR_URL="${IMAGE_URL%.raucb}.castr"

echo "Последняя версия: $VERSION"
echo "BUILD_ID: $BUILD_ID"
echo "IMAGE_URL: $IMAGE_URL"
echo "CASTR_URL: $CASTR_URL"

# Извлечение имени файла из URL
RAUC_BUNDLE_FILE="${IMAGE_URL##*/}"

# Загрузка RAUC-бандла
echo "Загрузка RAUC-бандла..."
curl -o "$RAUC_BUNDLE_FILE" "$IMAGE_URL"

# Проверка успешности загрузки
if [ $? -ne 0 ] || [ ! -f "$RAUC_BUNDLE_FILE" ]; then
    echo "Не удалось загрузить RAUC-бандл."
    exit 1
fi

# Создание временной директории для извлечения
TMP_DIR=$(mktemp -d)

# Извлечение rootfs.img.caibx из RAUC-бандла
echo "Извлечение rootfs.img.caibx из RAUC-бандла..."

unsquashfs -d "$TMP_DIR" "$RAUC_BUNDLE_FILE" rootfs.img.caibx

# Проверка успешности извлечения
if [ $? -ne 0 ] || [ ! -f "$TMP_DIR/rootfs.img.caibx" ]; then
    echo "Не удалось извлечь rootfs.img.caibx."
    exit 1
fi

# Использование casync для получения образа rootfs.img
echo "Получение rootfs.img с помощью casync..."

casync extract \
    --store="$CASTR_URL" \
    "$TMP_DIR/rootfs.img.caibx" rootfs.img

# Проверка успешности извлечения casync
if [ $? -ne 0 ] || [ ! -f "rootfs.img" ]; then
    echo "Не удалось извлечь rootfs.img с помощью casync."
    exit 1
fi

echo "rootfs.img успешно загружен."

# Очистка временных файлов
rm -rf "$TMP_DIR"
rm "$RAUC_BUNDLE_FILE"

echo "Временные файлы удалены."

exit 0