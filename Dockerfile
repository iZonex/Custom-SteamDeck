# syntax=docker/dockerfile:experimental

FROM archlinux:latest

# Обновляем систему и устанавливаем необходимые пакеты
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    git \
    wget \
    curl \
    casync \
    rauc \
    btrfs-progs \
    squashfs-tools \
    caddy \
    python \
    sudo

# Добавляем пользователя для безопасности
RUN useradd -m builder

# Устанавливаем sudo без пароля для пользователя builder
RUN echo 'builder ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Создаем необходимые каталоги и устанавливаем правильные права
RUN mkdir -p /home/builder/fauxlo/bundle && \
    chown -R builder:builder /home/builder/fauxlo

# Устанавливаем рабочую директорию и переключаемся на пользователя builder
WORKDIR /home/builder
USER builder

# Копируем скрипт сборки и другие необходимые файлы в контейнер
COPY --chown=builder:builder build.sh /home/builder/build.sh
COPY --chown=builder:builder custom-pacman.conf /home/builder/custom-pacman.conf
COPY --chown=builder:builder keyring.pem cert.pem key.pem client.conf /home/builder/

# Делаем скрипт исполняемым
RUN chmod +x /home/builder/build.sh

CMD ["/bin/bash"]