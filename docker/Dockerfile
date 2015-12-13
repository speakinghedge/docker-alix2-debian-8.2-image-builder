FROM debian:8.2
MAINTAINER hecke@naberius.de
LABEL version="0.1"
LABEL description="build a minimal ALIX Debian 8.2 (jessie) image"

RUN apt-get update && apt-get --no-install-recommends -y install \
	debconf

# the next line is really ugly but currently (afaik) the only way to have a heredoc in a dockerfile...
RUN echo "\n\
grub-pc grub-pc/install_devices_empty      select yes  \n\
grub-pc grub-pc/install_devices multiselect  \n\
" | debconf-set-selections

RUN apt-get --no-install-recommends -y install \
	debootstrap \
	grub2 \
	lsof \
	mount \
	parted

WORKDIR /var/alix_image_builder/
