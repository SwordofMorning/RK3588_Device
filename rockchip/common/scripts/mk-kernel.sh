#!/bin/bash -e
# update_kernel 升级内核
# do_build 编译内核
# usage_hook 功能列表打印 
# clean_hook 清理编译过的内核源码
# init_hook初始化钩子函数
# pre_build_hook 编译功能选择
# pre_build_hook_dry 模拟演练编译
# build_hook 内核的编译，该函数包含上面的do_build
# build_hook_dry 模拟演练编译
# post_build_hook 编译后要操作的步骤,构建linux-headers
# post_build_hook_dry 编译后要操作步骤的演练


KERNELS=$(ls | grep kernel- || true)

# 升级内核
update_kernel()
{
	# Fallback to current kernel
	RK_KERNEL_VERSION=${RK_KERNEL_VERSION:-$(kernel_version)}

	# Fallback to 5.10 kernel
	RK_KERNEL_VERSION=${RK_KERNEL_VERSION:-5.10}

	# Update .config
	KERNEL_CONFIG="RK_KERNEL_VERSION=\"$RK_KERNEL_VERSION\""
	if ! grep -q "^$KERNEL_CONFIG$" "$RK_CONFIG"; then
		sed -i "s/^RK_KERNEL_VERSION=.*/$KERNEL_CONFIG/" "$RK_CONFIG"
		"$SCRIPTS_DIR/mk-config.sh" olddefconfig &>/dev/null
	fi

	[ "$(kernel_version)" != "$RK_KERNEL_VERSION" ] || return 0

	# Update kernel
	KERNEL_DIR=kernel-$RK_KERNEL_VERSION
	echo "switching to $KERNEL_DIR"
	if [ ! -d "$KERNEL_DIR" ]; then
		echo "$KERNEL_DIR not exist!"
		exit 1
	fi

	rm -rf kernel
	ln -rsf $KERNEL_DIR kernel
}

# 编译内核
do_build()
{
	if [ "$DRY_RUN" ]; then
		echo -e "\e[35mCommands of building $1:\e[0m"
	else
		echo "=========================================="
		echo "          Start building $1"
		echo "=========================================="
	fi

	check_config RK_KERNEL_DTS_NAME RK_KERNEL_CFG RK_BOOT_IMG || return 0

	if [ ! "$DRY_RUN" ]; then
		"$SCRIPTS_DIR/check-kernel.sh"
	fi

	run_command $KMAKE $RK_KERNEL_CFG $RK_KERNEL_CFG_FRAGMENTS

	case "$1" in
		kernel-config)
			KERNEL_CONFIG_DIR="kernel/arch/$RK_KERNEL_ARCH/configs"
			run_command $KMAKE menuconfig
			run_command $KMAKE savedefconfig
			run_command mv kernel/defconfig \
				"$KERNEL_CONFIG_DIR/$RK_KERNEL_CFG"
			;;
		kernel*)
			run_command $KMAKE "$RK_KERNEL_DTS_NAME.img"

			# The FIT image for initrd would be packed in rootfs stage
			if [ -n "$RK_BOOT_FIT_ITS" ]; then
				if [ -z "$RK_ROOTFS_INITRD" ]; then
					run_command \
						"$SCRIPTS_DIR/mk-fitimage.sh" \
						"kernel/$RK_BOOT_IMG" \
						"$RK_BOOT_FIT_ITS" \
						"$RK_KERNEL_IMG"
				fi
			fi
			;;
		modules) run_command $KMAKE modules ;;
	esac
}

# 功能列表打印
usage_hook()
{
	for k in $KERNELS; do
		echo -e "$k[:cmds]               \tbuild kernel ${k#kernel-}"
	done

	echo -e "kernel[:cmds]                    \tbuild kernel"
	echo -e "modules[:cmds]                   \tbuild kernel modules"
	#echo -e "linux-headers[:cmds]             \tbuild linux-headers"
	#echo -e "kernel-config[:cmds]             \tmodify kernel defconfig"
}

# 清理编译过的内核源码
clean_hook()
{
	[ ! -d kernel ] || make -C kernel distclean
}

INIT_CMDS="default $KERNELS"

# 初始化钩子函数
init_hook()
{
	load_config RK_KERNEL_CFG
	check_config RK_KERNEL_CFG &>/dev/null || return 0

	# Priority: cmdline > custom env > .config > current kernel/ symlink
	if echo $1 | grep -q "^kernel-"; then
		export RK_KERNEL_VERSION=${1#kernel-}
		echo "Using kernel version($RK_KERNEL_VERSION) from cmdline"
	elif [ "$RK_KERNEL_VERSION" ]; then
		export RK_KERNEL_VERSION=${RK_KERNEL_VERSION//\"/}
		echo "Using kernel version($RK_KERNEL_VERSION) from environment"
	else
		load_config RK_KERNEL_VERSION
	fi

	update_kernel
}

PRE_BUILD_CMDS="kernel-config kernel-make kmake"
# 编译功能选择
pre_build_hook()
{
	check_config RK_KERNEL_CFG || return 0

	case "$1" in
		kernel-make | kmake)
			shift;
			if [ ! -r kernel/.config ]; then
				run_command $KMAKE $RK_KERNEL_CFG \
					$RK_KERNEL_CFG_FRAGMENTS
			fi
			run_command $KMAKE $@
			finish_build kmake $@
			;;
		kernel-config)
			do_build $@
			finish_build $@
			;;
	esac
}

# 模拟演练编译前
pre_build_hook_dry()
{
	DRY_RUN=1 pre_build_hook $@
}

BUILD_CMDS="$KERNELS kernel modules"

# 内核的编译
build_hook()
{
	check_config RK_KERNEL_DTS_NAME RK_KERNEL_CFG RK_BOOT_IMG || return 0

	if echo $1 | grep -q "^kernel-"; then
		if [ "$RK_KERNEL_VERSION" != "${1#kernel-}" ]; then
			echo -ne "\e[35m"
			echo "Kernel version overrided: " \
				"$RK_KERNEL_VERSION -> ${1#kernel-}"
			echo -ne "\e[0m"
		fi
	fi

	do_build $@

	[ ! "$DRY_RUN" ] || return 0

	if echo $1 | grep -q "^kernel"; then
		ln -rsf "kernel/$RK_BOOT_IMG" "$RK_FIRMWARE_DIR/boot.img"

		[ -z "$RK_SECURITY" ] || cp "$RK_FIRMWARE_DIR/boot.img" u-boot/

		"$SCRIPTS_DIR/check-power-domain.sh"
	fi

	finish_build build_$1
}

# 模拟演练编译
build_hook_dry()
{
	DRY_RUN=1 build_hook $@
}

POST_BUILD_CMDS="linux-headers"

# 编译后要操作的步骤
post_build_hook()
{
	check_config RK_KERNEL_DTS_NAME RK_KERNEL_CFG RK_BOOT_IMG || return 0

	OUTPUT_DIR="${2:-"$RK_OUTDIR"}"
	HEADER_FILES_SCRIPT=$(mktemp)

	if [ "$DRY_RUN" ]; then
		echo -e "\e[35mCommands of building $1:\e[0m"
	else
		echo "Saving linux-headers to $OUTPUT_DIR"
	fi

	run_command cd kernel

	cat << EOF > "$HEADER_FILES_SCRIPT"
{
	# Based on kernel/scripts/package/builddeb
	find . arch/$RK_KERNEL_ARCH -maxdepth 1 -name Makefile\*
	find include scripts -type f -o -type l
	find arch/$RK_KERNEL_ARCH -name module.lds -o -name Kbuild.platforms -o -name Platform
	find \$(find arch/$RK_KERNEL_ARCH -name include -o -name scripts -type d) -type f
	find arch/$RK_KERNEL_ARCH/include Module.symvers include scripts -type f
	echo .config
} | tar --no-recursion --ignore-failed-read -T - \
	-cf "$OUTPUT_DIR/linux-headers.tar"
EOF

	cat "$HEADER_FILES_SCRIPT"

	if [ -z "$DRY_RUN" ]; then
		. "$HEADER_FILES_SCRIPT"
	fi

	run_command cd "$SDK_DIR"
}

# 编译后要操作步骤的演练
post_build_hook_dry()
{
	DRY_RUN=1 post_build_hook $@
}

source "${BUILD_HELPER:-$(dirname "$(realpath "$0")")/../build-hooks/build-helper}"

case "${1:-kernel}" in
	kernel-config | kernel-make | kmake) pre_build_hook $@ ;;
	kernel* | modules)
		init_hook $@
		build_hook ${@:-kernel}
		;;
	linux-headers) post_build_hook $@ ;;
	*) usage ;;
esac
