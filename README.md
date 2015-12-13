# ALIX2 Debian 8.2 image builder

Creates a ready-to-install image for the ALIX2 board using a docker container.

## firmware info

- Debian 8.2 (kernel 3.16.0-4-586)
- init-system: systemd
- one ext4 partition (1900 MByte)
- uses grub2 bootloader (2.02~beta2-22)
- serial console on ttyS0@38400-8n1
- default user: user (pwd: user)
- root pwd: root, user is member of group sudo
- all interfaces using DHCP
- packages installed: apt-utils iproute dhcpcd5 ifupdown wget sudo nano openssh-client openssh-server pciutils iputils-ping

You can change most of these attributes in the head section of *_alix_image_recipe.sh*.

## usage

1. run build
   ```
   >./build.sh
   ...creates docker container if needed
   ...builds image running *_alix_image_recipe.sh* insider the docker container
   ```

2. copy the image on the CF card
   ```
   >dd if=alix2_debian_jessie.img of=<path-to-CF-drive> bs=1M
   ...
   ```
