#!/bin/bash -e

SCRIPTS_DIR="${SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"
SDK_DIR="${SDK_DIR:-$SCRIPTS_DIR/../../../..}"
BUILDROOT_DIR="$SDK_DIR/buildroot"

# Buildroot brmake needs unbuffer
if ! which unbuffer >/dev/null 2>&1; then
	echo -e "\e[35m"
	echo "Your unbuffer is missing"
	echo "Please install it:"
	echo "sudo apt-get install expect expect-dev"
	echo -e "\e[0m"
	exit 1
fi

# The new buildroot Makefile needs make (>= 4.0)
if ! "$BUILDROOT_DIR/support/dependencies/check-host-make.sh" 4.0 make \
	> /dev/null; then
	echo -e "\e[35m"
	echo "Your make is too old: $(make -v | head -n 1)"
	echo "Please update it:"
	echo "git clone https://github.com/mirror/make.git --depth 1 -b 4.2"
	echo "cd make"
	echo "git am $BUILDROOT_DIR/package/make/*.patch"
	echo "autoreconf -f -i"
	echo "./configure"
	echo "sudo make install -j8"
	echo -e "\e[0m"
	exit 1
fi

# The buildroot's e2fsprogs doesn't support new features like
# metadata_csum_seed and orphan_file
if grep -wq metadata_csum_seed /etc/mke2fs.conf; then
	echo -e "\e[35m"
	echo "Your mke2fs is too new: $(mke2fs -V 2>&1 | head -n 1)"
	echo "Please downgrade it:"
	"$SCRIPTS_DIR/install-e2fsprogs.sh"
	echo -e "\e[0m"
	exit 1
fi
