DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

IMAGE_REPO=quay.io/jianzzha/dnsmasq

.PHONY: all
all: image

.PHONY: tftp
tftp:
	@$(DIR)/get-tftp-files

.PHONY: image
image: tftp
	@docker build -t $(IMAGE_REPO):latest .

.PHONY: push
push:
	@docker push $(IMAGE_REPO):latest
