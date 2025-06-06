#!/bin/bash -e

SCRIPTS_DIR="${SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"
SDK_DIR="${SDK_DIR:-$SCRIPTS_DIR/../../../..}"

BUILDROOT_BOARD=$1
ROOTFS_OUTPUT_DIR="${2:-$SDK_DIR/output/buildroot}"
BUILDROOT_DIR="$SDK_DIR/buildroot"

"$SCRIPTS_DIR/check-buildroot.sh"

BUILDROOT_OUTPUT_DIR="$BUILDROOT_DIR/output/$BUILDROOT_BOARD"
BUILDROOT_CONFIG="$BUILDROOT_OUTPUT_DIR/.config"
BUILDROOT_CONFIG_ORIG="$BUILDROOT_OUTPUT_DIR/.config.orig"

# Handle buildroot make
if [ "$2" = make ]; then
	shift
	shift
	if [ ! -r "$BUILDROOT_CONFIG" ]; then
		make -C "$BUILDROOT_DIR" O="$BUILDROOT_OUTPUT_DIR" \
			${BUILDROOT_BOARD}_defconfig
	fi

	case "$1" in
		external/*)
			TARGET=$1
			unset ARG

			COUNT=$(echo $1 | grep -o '-' | wc -l)
			for I in $(seq 1 $COUNT); do
				TARGET=$(echo $1 | cut -d'-' -f1-$I)
				ARG=$(echo $1 | cut -d'-' -f$(($I + 1))-)

				[ -d "$TARGET" ] || continue
				break
			done

			PKG="$(basename $(dirname \
				$(grep -rwl "$TARGET" \
				"$BUILDROOT_DIR/package")))"
			TARGET="$PKG${ARG:+-$ARG}"
			;;
		*) TARGET="$1" ;;
	esac

	shift
	echo "Buildroot make: $TARGET $@"
	make -C "$BUILDROOT_DIR" O="$BUILDROOT_OUTPUT_DIR" $TARGET $@
	exit
fi

# Save the original .config if exists
if [ -r "$BUILDROOT_CONFIG" ] && [ ! -r "$BUILDROOT_CONFIG_ORIG" ]; then
	cp "$BUILDROOT_CONFIG" "$BUILDROOT_CONFIG_ORIG"
fi

make -C "$BUILDROOT_DIR" O="$BUILDROOT_OUTPUT_DIR" ${BUILDROOT_BOARD}_defconfig

# Warn about config changes
if [ -r "$BUILDROOT_CONFIG_ORIG" ]; then
	if ! diff "$BUILDROOT_CONFIG" "$BUILDROOT_CONFIG_ORIG"; then
		echo -e "\e[35m"
		echo "Buildroot config changed!"
		echo "You might need to clean it before building:"
		echo "rm -rf $BUILDROOT_OUTPUT_DIR"
		echo -e "\e[0m"
		echo
	fi
fi

# Use buildroot images dir as image output dir
IMAGE_DIR="$BUILDROOT_OUTPUT_DIR/images"
rm -rf "$ROOTFS_OUTPUT_DIR"
mkdir -p "$IMAGE_DIR"
ln -rsf "$IMAGE_DIR" "$ROOTFS_OUTPUT_DIR"
cd "${RK_LOG_DIR:-$ROOTFS_OUTPUT_DIR}"

LOG_PREFIX="br-$(basename "$BUILDROOT_OUTPUT_DIR")"
LOG_FILE="$(start_log "$LOG_PREFIX" 2>/dev/null || echo $PWD/$LOG_PREFIX.log)"
ln -rsf "$LOG_FILE" br.log

# Buildroot doesn't like it
unset LD_LIBRARY_PATH

if ! "$BUILDROOT_DIR"/utils/brmake -C "$BUILDROOT_DIR" O="$BUILDROOT_OUTPUT_DIR"; then
	echo "Failed to build $BUILDROOT_BOARD:"
	tail -n 100 "$LOG_FILE"
	echo -e "\e[35m"
	echo "Please check details in $LOG_FILE"
	echo -e "\e[0m"
	exit 1
fi

echo "Log saved on $LOG_FILE"
echo "Generated images:"
ls "$ROOTFS_OUTPUT_DIR"/rootfs.*
