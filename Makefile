# Makefile

IMAGE_NAME = steamos-builder
PLATFORM = linux/amd64

.PHONY: all create_builder build init_volume run clean

all: create_builder build init_volume run

create_builder:
	docker buildx create --use --name mybuilder || true

build:
	docker buildx build --platform $(PLATFORM) -t $(IMAGE_NAME) --load .

init_volume:
	docker run --rm -v fauxlo_bundle:/data --platform=$(PLATFORM) alpine sh -c "chown -R 1000:1000 /data"

run:
	docker run --rm --privileged \
		--network=host \
		--ulimit nofile=1024:4096 \
		--platform=$(PLATFORM) \
		-v fauxlo_bundle:/home/builder/fauxlo/bundle \
		-it $(IMAGE_NAME) /home/builder/build.sh

clean:\
	docker rmi $(IMAGE_NAME)
	rm -rf output