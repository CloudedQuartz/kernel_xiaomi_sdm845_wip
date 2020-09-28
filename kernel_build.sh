#! /bin/bash
# Copyright (C) 2020 KenHV
# Copyright (C) 2020 Starlight
# Copyright (C) 2021 CloudedQuartz
#

# Config
DEVICE="beryllium"
DEFCONFIG="${DEVICE}_defconfig"
LOG="$HOME/log.txt"

# Export arch and subarch
ARCH="arm64"
SUBARCH="arm64"
export ARCH SUBARCH

KERNEL_IMG=$KERNEL_DIR/out/arch/$ARCH/boot/Image.gz-dtb

TG_CHAT_ID="1139604865"
TG_BOT_TOKEN="$BOT_API_KEY"
# End config

# Function definitions

# tg_pushzip - uploads final zip to telegram
tg_pushzip() {
    curl -F document=@"$1"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
            -F chat_id=$TG_CHAT_ID \
            -F parse_mode=html \
            -F caption="$CAPTION"
}

# tg_failed - uploads build log to telegram
tg_failed() {
    curl -F document=@"$LOG"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
        -F chat_id=$TG_CHAT_ID \
        -F parse_mode=html \
        -F caption="$CAPTION"
}

# build_setup - enter kernel directory and get info for caption.
# also removes the previous kernel image, if one exists.
build_setup() {
    cd "$KERNEL_DIR" || echo -e "\nKernel directory ($KERNEL_DIR) does not exist" || exit 1

    [[ ! -d out ]] && mkdir out
    [[ -f "$KERNEL_IMG" ]] && rm "$KERNEL_IMG"
    COMMIT=$(git log --pretty=format:"%s" -1)
    COMMIT_SHA=$(git rev-parse --short HEAD)
	KERNEL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
}

# build_kernel - builds defconfig and kernel image using llvm tools, while saving the output to a specified log location
# only use after runing build_setup()
build_kernel() {

    make O=out $DEFCONFIG -j$(nproc --all)
    BUILD_START=$(date +"%s")
	echo $TC_DIR
    make -j$(nproc --all) O=out \
                PATH="$TC_DIR/bin:$PATH" \
                CC="clang" \
                CROSS_COMPILE=$TC_DIR/bin/aarch64-linux-gnu- \
                CROSS_COMPILE_ARM32=$TC_DIR/bin/arm-linux-gnueabi- \
                LLVM=llvm- \
                AR=llvm-ar \
                NM=llvm-nm \
                OBJCOPY=llvm-objcopy \
                OBJDUMP=llvm-objdump \
                STRIP=llvm-strip |& tee $LOG

    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
}

# build_end - creates and sends zip
build_end() {
    if ! [ -a "$KERNEL_IMG" ]; then
        echo -e "\n> Build failed, sending logs to Telegram."
        tg_failed &> /dev/null
        exit 1
    fi
    CAPTION=$(echo -e \
"HEAD: <code>$COMMIT_SHA: </code><code>$COMMIT</code>
Branch: <code>$KERNEL_BRANCH</code>
Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code>")

    echo -e "\n> Build successful! generating flashable zip..."
	cd "$AK_DIR" || echo -e "\nAnykernel directory ($AK_DIR) does not exist" || exit 1
	git clean -fd
	mv "$KERNEL_IMG" "$AK_DIR"/zImage
	ZIP_NAME=$KERNELNAME-$DEVICE-$COMMIT_SHA.zip
	zip -r9 "$ZIP_NAME" ./* -x .git README.md ./*placeholder
	tg_pushzip "$ZIP_NAME"
	echo -e "\n> Sent zip through Telegram.\n> File: $ZIP_NAME"

}
# End function definitions
build_setup
build_kernel
build_end

