#! /bin/bash
# Copyright (C) 2020 KenHV
# Copyright (C) 2020 Starlight
# Copyright (C) 2021 CloudedQuartz
#

# Config
DEVICE="beryllium"
DEVICE2="polaris"
DEVICE3="dipper"
DEFCONFIG="${DEVICE}_defconfig"
DEFCONFIG2="${DEVICE2}_defconfig"
DEFCONFIG3="${DEVICE3}_defconfig"
LOG="$HOME/log.txt"

# Export arch and subarch
ARCH="arm64"
SUBARCH="arm64"
export ARCH SUBARCH

KERNEL_IMG=$KERNEL_DIR/out/arch/$ARCH/boot/Image.gz-dtb

TG_CHAT_ID="-1001401278365"
TG_BOT_TOKEN="$BOT_API_KEY"
# End config

# Function definitions

# tg_sendinfo - sends text through telegram
tg_sendinfo() {
	curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
		-F parse_mode=html \
		-F text="${1}" \
		-F chat_id="${TG_CHAT_ID}" &> /dev/null
}

# tg_pushzip - uploads final zip to telegram
tg_pushzip() {
	MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)
	curl -F document=@"$1"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
			-F chat_id=$TG_CHAT_ID \
			-F caption="$2 | <b>MD5 Checksum : </b><code>$MD5CHECK</code>" \
			-F parse_mode=html &> /dev/null
}

# tg_failed - uploads build log to telegram
tg_failed() {
    curl -F document=@"$LOG"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
        -F chat_id=$TG_CHAT_ID \
        -F parse_mode=html &> /dev/null
}

# build_setup - enter kernel directory and get info for caption.
# also removes the previous kernel image, if one exists.
build_setup() {
    cd "$KERNEL_DIR" || echo -e "\nKernel directory ($KERNEL_DIR) does not exist" || exit 1

    [[ ! -d out ]] && mkdir out
    [[ -f "$KERNEL_IMG" ]] && rm "$KERNEL_IMG"
	find . -name "*.dtb" -type f -delete
}

# build_config - builds .config file for device.
build_config() {
	make O=out $1 -j$(nproc --all)
}
# build_kernel - builds defconfig and kernel image using llvm tools, while saving the output to a specified log location
# only use after runing build_setup()
build_kernel() {

    BUILD_START=$(date +"%s")
    make -j $(($(($(nproc) / 2)) + 1))  O=out \
                PATH="$TC_DIR/arm64/bin:$TC_DIR/arm/bin:$PATH" \
                CROSS_COMPILE=$TC_DIR/arm64/bin/aarch64-elf- \
                CROSS_COMPILE_ARM32=$TC_DIR/arm/bin/arm-eabi- |& tee $LOG

    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
}

# build_end - creates and sends zip
build_end() {

	if ! [ -a "$KERNEL_IMG" ]; then
        echo -e "\n> Build failed, sending logs to Telegram."
        tg_failed
        tg_buildtime
        exit 1
    fi

    echo -e "\n> Build successful! generating flashable zip..."
	cd "$AK_DIR" || echo -e "\nAnykernel directory ($AK_DIR) does not exist" || exit 1
	git clean -fd
	mv "$KERNEL_IMG" "$AK_DIR"/zImage
	ZIP_NAME=$KERNELNAME-$1-$COMMIT_SHA-$(date +%Y-%m-%d_%H%M)-UTC
	zip -r9 "$ZIP_NAME".zip ./* -x .git README.md ./*placeholder

	# Sign zip if java is available
	if command -v java > /dev/null 2>&1; then
		curl -sLo zipsigner-3.0.jar https://raw.githubusercontent.com/baalajimaestro/AnyKernel2/master/zipsigner-3.0.jar
		java -jar zipsigner-3.0.jar "$ZIP_NAME".zip "$ZIP_NAME"-signed.zip
		ZIP_NAME="$ZIP_NAME-signed.zip"
	fi

	tg_pushzip "$ZIP_NAME" "Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code>"
	echo -e "\n> Sent zip through Telegram.\n> File: $ZIP_NAME"
}

# End function definitions

COMMIT=$(git log --pretty=format:"%s" -1)
COMMIT_SHA=$(git rev-parse --short HEAD)
KERNEL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

CAPTION=$(echo -e \
"HEAD: <code>$COMMIT_SHA: </code><code>$COMMIT</code>
Branch: <code>$KERNEL_BRANCH</code>")

tg_sendinfo "-- Build Triggered --
$CAPTION"

# Build device 1
build_setup
build_config $DEFCONFIG
build_kernel
build_end $DEVICE

# Build device 2
build_setup
build_config $DEFCONFIG2
build_kernel
build_end $DEVICE2

# Build device 3
build_setup
build_config $DEFCONFIG3
build_kernel
build_end $DEVICE3

# Build old touch fw version for device 1
# Build device 1
build_setup
git apply old_touch_fw.patch
build_config $DEFCONFIG
build_kernel
build_end ${DEVICE}_old_touch_fw

