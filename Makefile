# Use some sensible default shell settings
SHELL := /bin/bash -o pipefail
.SILENT:
.DEFAULT_GOAL := help

# Default variables
MNT_DEVICE             ?= /dev/mmcblk0
MNT_DEVICE_PART_PREFIX ?= p
MNT_ROOT                = /mnt/raspbernetes/root
MNT_BOOT                = /mnt/raspbernetes/boot
RPI_HOME                = $(MNT_ROOT)/home/pi
OUTPUT_PATH = output

# Raspberry PI host and IP configuration
RPI_NETWORK_TYPE ?= wlan0
RPI_HOSTNAME     ?= rpi-kube-controlplane-01
RPI_IP           ?= 192.168.1.101
RPI_GATEWAY      ?= 192.168.1.1
RPI_DNS          ?= $(RPI_GATEWAY)
RPI_TIMEZONE     ?= Australia/Melbourne

# Kubernetes configuration
KUBE_NODE_TYPE    ?= controlplane
KUBE_MASTER_VIP   ?= 192.168.1.100
KUBE_MASTER_IPS   ?= 192.168.1.101
KUBE_MASTER_PRIO  ?= 50
KUBE_MASTER_NET   ?= flannel

# Wifi details if required
WIFI_SSID     ?=
WIFI_PASSWORD ?=

# Raspbian image configuration
DISTRO_NAME             ?= raspbian_lite
DISTRO_VERSION          ?= raspbian_lite-2020-02-14
DISTRO_IMAGE_VERSION    ?= 2020-02-13-raspbian-buster-lite
DISTRO_IMAGE_EXTENSION  ?= zip

DISTRO_URL				= https://downloads.raspberrypi.org/$(DISTRO_NAME)/images/$(DISTRO_VERSION)/$(DISTRO_IMAGE_VERSION).$(DISTRO_IMAGE_EXTENSION)

ifeq ($(DISTRO_IMAGE_EXTENSION),zip)
	decompress = unzip
	decompress_output = -d ./$(OUTPUT_PATH)/
endif
ifeq ($(DISTRO_IMAGE_EXTENSION),img.xz)
	decompress = xz -d
	decompress_output = 
endif

##@ Build
.PHONY: build
build: prepare format install-conf create-conf clean ## Build SD card with Kubernetes and automated cluster creation
	echo "Created a headless Kubernetes SD card with the following properties:"
	echo "Network:"
	echo "- Hostname: $(RPI_HOSTNAME)"
	echo "- Static IP: $(RPI_IP)"
	echo "- Gateway address: $(RPI_DNS)"
	echo "- Network adapter: $(RPI_NETWORK_TYPE)"
	echo "- Timezone: $(RPI_TIMEZONE)"
	echo "Kubernetes:"
	echo "- Node Type: $(KUBE_NODE_TYPE)"
	echo "- Control Plane Endpoint: $(KUBE_MASTER_VIP)"
	echo "- Control Plane Priority: $(KUBE_MASTER_PRIO)"
	echo "- Control Plane IPs: $(KUBE_MASTER_IPS)"
	echo "- Control Plane Net Provider: $(KUBE_MASTER_NET)"

##@ Configuration Generation
.PHONY: install-conf
install-conf: $(OUTPUT_PATH)/ssh/id_raspbernetes_ed25519 mount ## Copy all configurations and scripts to SD card
	sudo touch $(MNT_BOOT)/ssh
	mkdir -p $(RPI_HOME)/bootstrap/
	cp -r ./raspbernetes/* $(RPI_HOME)/bootstrap/
	mkdir -p $(RPI_HOME)/.ssh
	cp ./$(OUTPUT_PATH)/ssh/id_raspbernetes_ed25519 $(RPI_HOME)/.ssh/
	cp ./$(OUTPUT_PATH)/ssh/id_raspbernetes_ed25519.pub $(RPI_HOME)/.ssh/authorized_keys
	sudo rm -f $(MNT_ROOT)/etc/motd

.PHONY: create-conf
create-conf: $(RPI_NETWORK_TYPE) bootstrap-conf dhcp-conf ## Add default start up script, disable SSH password and enable cgroups on boot
	sudo sed -i "/^exit 0$$/i /home/pi/bootstrap/bootstrap.sh 2>&1 | logger -t kubernetes-bootstrap &" $(MNT_ROOT)/etc/rc.local
	sudo sed -i "s/.*PasswordAuthentication.*/PasswordAuthentication no/g" $(MNT_ROOT)/etc/ssh/sshd_config
	sudo sed -i "s/^/cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory /" $(MNT_BOOT)/cmdline.txt

.PHONY: bootstrap-conf
bootstrap-conf: ## Add node custom configuration file to be sourced on boot
	echo "export RPI_HOSTNAME=$(RPI_HOSTNAME)" >> $(RPI_HOME)/bootstrap/rpi-env
	echo "export RPI_IP=$(RPI_IP)" >> $(RPI_HOME)/bootstrap/rpi-env
	echo "export RPI_DNS=$(RPI_DNS)" >> $(RPI_HOME)/bootstrap/rpi-env
	echo "export RPI_NETWORK_TYPE=$(RPI_NETWORK_TYPE)" >> $(RPI_HOME)/bootstrap/rpi-env
	echo "export RPI_TIMEZONE=$(RPI_TIMEZONE)" >> $(RPI_HOME)/bootstrap/rpi-env
	echo "export KUBE_MASTER_VIP=$(KUBE_MASTER_VIP)" >> $(RPI_HOME)/bootstrap/rpi-env
	echo "export KUBE_MASTER_PRIO=$(KUBE_MASTER_PRIO)" >> $(RPI_HOME)/bootstrap/rpi-env
	echo "export KUBE_NODE_TYPE=$(KUBE_NODE_TYPE)" >> $(RPI_HOME)/bootstrap/rpi-env
	echo "export KUBE_MASTER_IPS=($(KUBE_MASTER_IPS))" >> $(RPI_HOME)/bootstrap/rpi-env
	echo "export KUBE_MASTER_NET=$(KUBE_MASTER_NET)" >> $(RPI_HOME)/bootstrap/rpi-env

.PHONY: dhcp-conf
dhcp-conf: ## Add dhcp configuration to set a static IP and gateway
	echo 'allowinterfaces eth0 wlan0 lo' | sudo tee -a $(MNT_ROOT)/etc/dhcpcd.conf >/dev/null
	echo 'denyinterfaces weave datapath docker* veth* vxlan*' | sudo tee -a $(MNT_ROOT)/etc/dhcpcd.conf >/dev/null
	echo "interface $(RPI_NETWORK_TYPE)" | sudo tee -a $(MNT_ROOT)/etc/dhcpcd.conf >/dev/null
	echo "static ip_address=$(RPI_IP)/24" | sudo tee -a $(MNT_ROOT)/etc/dhcpcd.conf >/dev/null
	echo "static routers=$(RPI_GATEWAY)" | sudo tee -a $(MNT_ROOT)/etc/dhcpcd.conf >/dev/null
	echo "static domain_name_servers=$(RPI_DNS)" | sudo tee -a $(MNT_ROOT)/etc/dhcpcd.conf >/dev/null

$(OUTPUT_PATH)/ssh/id_raspbernetes_ed25519: ## Generate SSH keypair to use in cluster communication
	ssh-keygen -t ed25519 -b 4096 -C "pi@raspberry" -f ./$(OUTPUT_PATH)/ssh/id_raspbernetes_ed25519 -q -N ""

##@ Download and SD Card management
.PHONY: format
format: $(OUTPUT_PATH)/$(DISTRO_IMAGE_VERSION).img unmount ## Format the SD card with Raspbian
	echo "Formatting SD card with $(DISTRO_IMAGE_VERSION).img"
	sudo dd bs=4M if=./$(OUTPUT_PATH)/$(DISTRO_IMAGE_VERSION).img of=$(MNT_DEVICE) status=progress conv=fsync

.PHONY: mount
mount: ## Mount the current SD device
	sudo mount $(MNT_DEVICE)$(MNT_DEVICE_PART_PREFIX)1 $(MNT_BOOT)
	sudo mount $(MNT_DEVICE)$(MNT_DEVICE_PART_PREFIX)2 $(MNT_ROOT)

.PHONY: unmount
unmount: ## Unmount the current SD device
	sudo umount $(MNT_DEVICE)$(MNT_DEVICE_PART_PREFIX)1 || true
	sudo umount $(MNT_DEVICE)$(MNT_DEVICE_PART_PREFIX)2 || true

.PHONY: wlan0
wlan0: ## Install wpa_supplicant for auto network join
	test -n "$(WIFI_SSID)"
	test -n "$(WIFI_PASSWORD)"
	sudo cp ./raspbernetes/template/wpa_supplicant.conf $(MNT_BOOT)/wpa_supplicant.conf
	sudo sed -i "s/<WIFI_SSID>/$(WIFI_SSID)/" $(MNT_BOOT)/wpa_supplicant.conf
	sudo sed -i "s/<WIFI_PASSWORD>/$(WIFI_PASSWORD)/" $(MNT_BOOT)/wpa_supplicant.conf

.PHONY: eth0
eth0: ## Nothing to do for eth0

$(OUTPUT_PATH)/$(DISTRO_IMAGE_VERSION).img: ## Download Raspbian image and extract to current directory
	rm -f ./$(OUTPUT_PATH)/$(DISTRO_IMAGE_VERSION).$(DISTRO_IMAGE_EXTENSION)
	echo "Downloading $(DISTRO_IMAGE_VERSION).img..."
	wget $(DISTRO_URL) -P ./$(OUTPUT_PATH)/
	$(decompress) ./$(OUTPUT_PATH)/$(DISTRO_IMAGE_VERSION).$(DISTRO_IMAGE_EXTENSION) $(decompress_output)
	rm -f ./$(OUTPUT_PATH)/$(DISTRO_IMAGE_VERSION).$(DISTRO_IMAGE_EXTENSION)

##@ Misc
.PHONY: help
help: ## Display this help
	awk \
	  'BEGIN { \
	    FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n" \
	  } /^[a-zA-Z_-]+:.*?##/ { \
	    printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 \
	  } /^##@/ { \
	    printf "\n\033[1m%s\033[0m\n", substr($$0, 5) \
	  }' $(MAKEFILE_LIST)

##@ Helpers
.PHONY: prepare
prepare: ## Create all necessary directories to be used in build
	sudo mkdir -p $(MNT_BOOT)
	sudo mkdir -p $(MNT_ROOT)
	mkdir -p ./$(OUTPUT_PATH)/ssh/

.PHONY: clean
clean: ## Unmount and delete all temporary mount directories
	sudo umount $(MNT_DEVICE)$(MNT_DEVICE_PART_PREFIX)1 || true
	sudo umount $(MNT_DEVICE)$(MNT_DEVICE_PART_PREFIX)2 || true
	sudo rm -rf $(MNT_BOOT)
	sudo rm -rf $(MNT_ROOT)
