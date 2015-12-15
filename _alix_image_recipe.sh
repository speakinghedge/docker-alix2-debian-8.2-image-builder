#!/bin/sh
#################################################################

CHROOT_DIR=/tmp/chroot
# set to 0 -> keep image file, don't run debootstrap (useful for debugging the image builder)
NEW_IMAGE=1

DEBIAN_MIRROR=http://httpredir.debian.org/debian/
# keep this unless you know what you do
DEBIAN_BASE_PACKAGES="debconf grub2 busybox initramfs-tools"
# add here what you need
DEBIAN_ADDITIONAL_PACKAGES="apt-utils iproute isc-dhcp-client ifupdown wget sudo nano openssh-client openssh-server pciutils iputils-ping"
# note: 686-pae won't run on the ALIX2 as the AMD Geode doesn't offer PEA (the Debian package info for 3.16.0-4-686-PAE is wrong)
DEBIAN_KERNEL_VERSION="3.16.0-4-586"
# shrink the initrd from 14M to 3.7M
DEBIAN_UPDATE_INITRAMFS=1

# you may set this to larger sizes - eg. 4G (depends on the size of your cf card)
IMAGE_SIZE=1900M
IMAGE_NAME=alix2_debian_jessie.img
IMAGE_PART_OFFSET=1048576

HOST_NAME="alix2"
USER_NAME="user"
USER_PASSWD="user"
# set to 0 if user should not be part of group sudo...
USER_GROUP_SUDO=1
ROOT_PASSWD="root"
GETTY_ON_TTYS0=1

#################################################################

if [ ! -d ${CHROOT_DIR} ] ; then
	mkdir "${CHROOT_DIR}"
fi

if [ ${NEW_IMAGE} -eq 1 ] ; then
	rm -f ${IMAGE_NAME}
	dd if=/dev/zero of="${IMAGE_NAME}" bs=1 count=0 seek=${IMAGE_SIZE}
	parted -s -a optimal "${IMAGE_NAME}" mklabel msdos -- mkpart primary ext4 1 100% set 1 boot on
	if [ $? -ne 0 ]; then
		echo "Failed to create partition on image file. abort."
		exit 1
	fi
fi

echo "create loop device for first partition in image file..."
losetup -o ${IMAGE_PART_OFFSET} -f "${IMAGE_NAME}"
if [ $? -ne 0 ] ; then
	echo "failed to create loop-back-device for first partition in image file '${IMAGE_NAME}'. abort."
	exit 1
fi

partition_loop_dev=$(losetup -j ${IMAGE_NAME} | cut -d : -f 1)
if [ "x" = "x${partition_loop_dev}" ] ; then
	echo "failed to get loop-back-device for image file '${IMAGE_NAME}'. abort."
	exit 1	
fi
echo "use loop-dev '${partition_loop_dev}'."

if [ ${NEW_IMAGE} -eq 1 ] ; then
	/sbin/mkfs.ext4 "${partition_loop_dev}"
	if [ $? -ne 0 ] ; then
		losetup -d "${partition_loop_dev}"
		echo "failed to create ext4 partition on '/dev/loop0'. abort."
		exit 1
	fi
	echo "ext4-root-partition created."
fi

mount -o loop "${partition_loop_dev}" "${CHROOT_DIR}"
if [ $? -ne 0 ] ; then
	losetup -d "${partition_loop_dev}"
	echo "failed to mount for '/dev/loop0'. abort."
	exit 1
fi

if [ ${NEW_IMAGE} -eq 1 ] ; then
	debootstrap --arch i386 --variant=minbase jessie "${CHROOT_DIR}" "${DEBIAN_MIRROR}"
fi

# copy contents to target
echo "copy contents to target..."
cp -rf contents/* ${CHROOT_DIR}/
# now replace @HOST_NAME@, @USER_NAME@ if needed...
for f in $(cd contents && find . -type f); do
	sed -i "s/@HOST_NAME@/$HOST_NAME/g" "${CHROOT_DIR}/${f}"
	sed -i "s/@USER_NAME@/$USER_NAME/g" "${CHROOT_DIR}/${f}"
done

# prepare script to be run in chroot
cat << EOF > "${CHROOT_DIR}/base_setup.sh"

	echo 'debconf debconf/frontend select noninteractive' | debconf-set-selections

	echo "update apt..."
	apt-get update 1>/dev/null

	apt-get --no-install-recommends -y install  apt-utils debconf

cat << EOF2 | debconf-set-selections
grub-pc grub-pc/install_devices_empty      select yes 
grub-pc grub-pc/install_devices multiselect
EOF2

	echo "install base packages..."
	for package in ${DEBIAN_BASE_PACKAGES} ${DEBIAN_ADDITIONAL_PACKAGES} 
	do
		echo -n "  \${package} ..."
		apt-get --no-install-recommends -y install \$package 1>/dev/null
		echo "done."
	done

	echo "install kernel ${DEBIAN_KERNEL_VERSION}..."
	apt-get --no-install-recommends -y install linux-image-${DEBIAN_KERNEL_VERSION} 1>/dev/null

	echo "setup users (${USER_NAME}:${USER_PASSWD};root:${ROOT_PASSWD})... "
	echo "root:${ROOT_PASSWD}" | chpasswd
	useradd -m -d "/home/${USER_NAME}" "${USER_NAME}" 1>/dev/null 2>&1
	echo "${USER_NAME}:${USER_PASSWD}" | chpasswd
	chsh -s /bin/bash "${USER_NAME}"
	if [ ${USER_GROUP_SUDO} -ne 0 ] ; then
		usermod -a -G sudo "${USER_NAME}"
	fi

	rm -f /base_setup.sh
EOF

echo "bind-mount special directories..."
for special_dir in dev dev/pts proc run sys ; do
	mount -o bind "/${special_dir}" "${CHROOT_DIR}/${special_dir}" 1>/dev/null
done

echo "chroot and execute base setup..."
chmod a+x "${CHROOT_DIR}/base_setup.sh"
chroot "${CHROOT_DIR}/" "/base_setup.sh"

# kill processes stared in the chroot (eg. sshd - if installed)
if [ $(lsof "${CHROOT_DIR}/" 2>/dev/null | tail -n+2 | wc -l) -gt 0 ] ; then
	echo "kill processes started in chroot..."
	last_pid=0
	while [ $(lsof "${CHROOT_DIR}/" 2>/dev/null | tail -n+2 | wc -l) -gt 0 ] ; do

		if [ $last_pid -eq $(lsof "${CHROOT_DIR}/" 2>/dev/null | tail -n+2 | head -n 1 | awk '{ print $2 }' ) ] ; then
			echo "ERROR: Failed to kill process ${last_pid} - umount may fail. check mount after finishing script."
			break
		fi
		last_pid=$(lsof "${CHROOT_DIR}/" 2>/dev/null  | tail -n+2 | head -n 1 | awk '{ print $2 }' )

		lsof ${CHROOT_DIR} | tail -n+2 | head -n 1 | awk '{ print "  kill "$1" (PID: "$2")" }'
		kill -9 "${last_pid}"
	done
fi

echo "create loop dev for whole image file..."
losetup -f "${IMAGE_NAME}"
if [ $? -ne 0 ] ; then
	echo "failed to create loop-back-device for whole image file '${IMAGE_NAME}'. abort."
	exit 1
fi

disk_loop_dev=$(losetup -j ${IMAGE_NAME} -o 0 | cut -d : -f 1)
if [ "x" = "x${disk_loop_dev}" ] ; then
	losetup -d "${partition_loop_dev}"
	echo "failed to get loop-back-device for whole image file '${IMAGE_NAME}'. abort."
	exit 1	
fi
echo "use disk-loop-dev '${disk_loop_dev}'."

echo "setup grub boot loader..."
cat << EOF > ${CHROOT_DIR}/boot/grub/device.map
(hd0) "${disk_loop_dev}"
EOF
echo "install grub into ${disk_loop_dev}..."
grub-install --target=i386-pc --modules="ext2 part_msdos" --root-directory="${CHROOT_DIR}/" --grub-mkdevicemap="${CHROOT_DIR}/boot/grub/device.map" --boot-directory="${CHROOT_DIR}/boot/" "${disk_loop_dev}"

chroot "${CHROOT_DIR}/" /usr/sbin/update-grub2
# the magic of update-grub2 creates a configuration suitable for booting from loop devices
# this is completely valid as this is the current environment update-grub2 is executed in
# but now lets remove the loopback entries cause we are going to boot from real drives
sed -i -e '/^[[:space:]]\+loopback[[:space:]]loop/d' "${CHROOT_DIR}//boot/grub/grub.cfg"
sed -i -e '/^[[:space:]]\+set[[:space:]]root=(loop/d' "${CHROOT_DIR}//boot/grub/grub.cfg"
# .. and the root is not loopX - but sda1
sed -i 's/loop[0-9]/sda1/g' "${CHROOT_DIR}//boot/grub/grub.cfg"

cat << EOF > ${CHROOT_DIR}/boot/grub/device.map
(hd0) /dev/sda
EOF

if [ ${DEBIAN_UPDATE_INITRAMFS} -ne 0 ] ; then
	echo "update initramfs..."

	# force update-initramfs to use our modules list
	chroot "${CHROOT_DIR}/" sed -i 's/MODULES=[a-z]*/MODULES=list/g' /etc/initramfs-tools/initramfs.conf
	chroot "${CHROOT_DIR}/" /usr/sbin/update-initramfs -u -k "${DEBIAN_KERNEL_VERSION}"
fi

if [ ${GETTY_ON_TTYS0} -ne 0 ] ; then
	echo "enable serial console on ttyS0..."
	echo "T0:23:respawn:/sbin/getty -L ttyS0 38400 vt100" >> "${CHROOT_DIR}/etc/inittab"

	if [ $(cat "${CHROOT_DIR}/etc/securetty" | grep -c ttyS0}) -lt 1 ] ; then
		echo "enable root login via ttyS0..."
		echo "ttyS0" >> "${CHROOT_DIR}/etc/securetty"
	fi
fi

echo "umount special directories..."
for special_dir in sys run proc dev/pts dev ; do
	umount "${CHROOT_DIR}/${special_dir}" 1>/dev/null
done

echo "clean up partition mount and loop dev..."
umount "${CHROOT_DIR}"
losetup -d "${partition_loop_dev}"
losetup -d "${disk_loop_dev}"

echo
echo "image created in: ${IMAGE_NAME}"
echo