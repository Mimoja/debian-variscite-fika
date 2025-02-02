#!/bin/bash
set -eo pipefail

declare    IMAGE_TARGET="sdcard.img"
#declare    IMAGE_TARGET="/dev/sdc"
declare -i IMAGE_SIZE=16 # in GiB

# Bootloader
declare -i BOOTLOADER_START=32 # in KiB
declare -i BOOTLOADER_SIZE=8192 # in KiB
declare -i BOOTLOADER_END=BOOTLOADER_START+BOOTLOADER_SIZE # in KiB
declare -i BOOTLOADER_ENV_START=BOOTLOADER_END # in KiB
declare -i BOOTLOADER_ENV_SIZE=8192 # in KiB
declare -i BOOTLOADER_ENV_END=BOOTLOADER_END+BOOTLOADER_ENV_SIZE # in KiB

# root disks
declare -i ROOT_ALIGNMENT=1024
declare -i ROOT_SIZE=$((5*1024*1024 / ROOT_ALIGNMENT))*ROOT_ALIGNMENT  # in KiB
declare -i ROOT_A_START=$((BOOTLOADER_ENV_END / ROOT_ALIGNMENT + 1))*ROOT_ALIGNMENT
declare -i ROOT_A_END=ROOT_A_START+ROOT_SIZE
declare -i ROOT_B_START=ROOT_A_END
declare -i ROOT_B_END=ROOT_A_END+ROOT_SIZE

# user data
declare -i USER_ALIGNMENT=ROOT_ALIGNMENT
declare -i USER_START=ROOT_B_END
declare -i USER_END=(IMAGE_SIZE*1024*1024)-1-0x10
declare -i USER_SIZE=USER_END-USER_START

echo -e "## Planned paritioning scheme"

# Print partition table for checking
PART_TABLE=$(echo "Number:Name:Start (KiB):Size (KiB):End (KiB):Aling (KiB):Type\n")
PART_TABLE+="$(printf "%d:%s:0x%06x:0x%06x:0x%06x::%s"       1 uboot     ${BOOTLOADER_START}     ${BOOTLOADER_SIZE}     $((${BOOTLOADER_END}-1))                     "raw"  )\n"
PART_TABLE+="$(printf "%d:%s:0x%06x:0x%06x:0x%06x::%s"       2 uboot_env ${BOOTLOADER_ENV_START} ${BOOTLOADER_ENV_SIZE} $((${BOOTLOADER_ENV_END}-1))                 "fat32")\n"
PART_TABLE+="$(printf "%d:%s:0x%06x:0x%06x:0x%06x:0x%02x:%s" 3 root_a    ${ROOT_A_START}         ${ROOT_SIZE}           $((${ROOT_A_END}-1))         $ROOT_ALIGNMENT "ext4" )\n"
PART_TABLE+="$(printf "%d:%s:0x%06x:0x%06x:0x%06x:0x%02x:%s" 4 root_b    ${ROOT_B_START}         ${ROOT_SIZE}           $((${ROOT_B_END}-1))         $ROOT_ALIGNMENT "ext4" )\n"
PART_TABLE+="$(printf "%d:%s:0x%06x:0x%06x:0x%06x:0x%02x:%s" 5 user      ${USER_START}           ${USER_SIZE}           $((${USER_END}-1))           $USER_ALIGNMENT "ext4" )\n"

echo -e $PART_TABLE | column -s: -t --table-right 1,3,4,5

function create_unaligned_partition () {
    START=$1
    END=$2

    parted ${IMAGE_TARGET} mkpart -a none primary ${START}KiB ${END}KiB
}

declare -g PARTITIONS=0

function create_partition () {
    NAME=$1
    START=$2
    END=$3
    FS_TYPE=$4
    declare -i PARTITION_NUMBER=${PARTITIONS}+1

    if [ ! -z $END ]; then
        declare -i SIZE=END-START
    fi

    # Everything below 100M is probably not worth optimizing
    if [ -n "$SIZE" ] && [ $SIZE -lt $((100 * 1024)) ]; then
        printf "%-09s: Creating        unaligned parition (${PARTITION_NUMBER}) from 0x%06x to 0x%06x\n" "$NAME" "${START}" "${END}"
        create_unaligned_partition ${START} ${END}
    else
        if [ -z "$END" ]; then
            printf "%-09s: Creating properly aligned parition (${PARTITION_NUMBER}) from 0x%06x to the end\n" "$NAME" "${START}" "${END}"
            parted ${IMAGE_TARGET} -f mkpart primary ${START}KiB
        else
            printf "%-09s: Creating properly aligned parition (${PARTITION_NUMBER}) from 0x%06x to 0x%06x\n" "$NAME" "${START}" "${END}"
            parted ${IMAGE_TARGET} -f mkpart primary ${START}KiB ${END}KiB
        fi
    fi

    parted ${IMAGE_TARGET} name $PARTITION_NUMBER $NAME
    declare -ig PARTITIONS=PARTITIONS+1
}

function create_image () {
    echo -e "\n## Creating parition scheme"

    if [ -b ${IMAGE_TARGET} ]; then
        declare -i DD_BLOCK_SIZE=1024*1024
        echo "${IMAGE_TARGET} is a block device, nuking partition table"
        dd if=/dev/zero of=${IMAGE_TARGET} bs=${DD_BLOCK_SIZE} count=32 status=noxfer status=progress 2>/dev/null
    else
        if command -v qemu-img > /dev/null; then
            echo "Using qemu-img to create ${IMAGE_TARGET}"
            qemu-img create -f raw ${IMAGE_TARGET} ${IMAGE_SIZE}G
        else
            echo "qemu-img is not installed, falling back to dd"
            declare -i DD_BLOCK_SIZE=1024*1024
            declare -i IMAGE_BLOCKS=IMAGE_SIZE*1024*1024*1024/DD_BLOCK_SIZE
            dd if=/dev/zero of=${IMAGE_TARGET} bs=${DD_BLOCK_SIZE} count=${IMAGE_BLOCKS} status=noxfer status=progress 2>/dev/null
        fi
    fi

    # Create GPT partition scheme
    parted ${IMAGE_TARGET} mklabel gpt

    # Create uboot partition
    create_partition uboot      ${BOOTLOADER_START}     ${BOOTLOADER_END}
    create_partition uboot_env  ${BOOTLOADER_ENV_START} ${BOOTLOADER_ENV_END}
    declare -i env_partition=${PARTITIONS}
    parted ${IMAGE_TARGET} -f set ${env_partition} boot on
    create_partition root_a     ${ROOT_A_START}         ${ROOT_A_END}
    create_partition root_b     ${ROOT_B_START}         ${ROOT_B_END}
    create_partition user       ${USER_START}           ${USER_END}

    if [ -b ${IMAGE_TARGET} ]; then
        echo "${IMAGE_TARGET} is a block device, rescanning partitions"
        partprobe ${IMAGE_TARGET}
        PARTITION=${IMAGE_TARGET}
    else
        LOOP_DEV=$(losetup --find)
        PARTITION=${LOOP_DEV}p
        losetup -P ${LOOP_DEV} ${IMAGE_TARGET}
    fi

    echo -e "\n## Formating"

    echo "Creating fat32 for u-boot env on ${PARTITION}2"
    mkfs.fat ${PARTITION}2 > /dev/null

    echo "Creating ext4  for   root_a   on ${PARTITION}3"
    mkfs.ext4 ${PARTITION}3 -F -L root_a -q

    echo "Creating ext4  for   root_b   on ${PARTITION}4"
    mkfs.ext4 ${PARTITION}4 -F -L root_b -q

    echo "Creating ext4  for    user    on ${PARTITION}5"
    mkfs.ext4 ${PARTITION}5 -F -L user   -q

    mkdir -p sdcard
    mount ${PARTITION}3 sdcard

    echo -e "\n## Installing"

    echo "Installing u-boot             to ${PARTITION}1"
    dd if=output/imx-boot-sd.bin of=${PARTITION}1 bs=1K status=noxfer status=progress 2>/dev/null

    echo "Installing OS                 to ${PARTITION}3"
    pv output/rootfs.tar.gz | tar -xzp -C sdcard

    echo "Syncing disks..."
    sync
    umount sdcard


    if ! [ -b ${IMAGE_TARGET} ]; then
        losetup --detach ${LOOP_DEV}
        echo -e "\n## Compressing image"
        pigz -kf ${IMAGE_TARGET}
        echo -e "Image can be installed from ${IMAGE_TARGET} or ${IMAGE_TARGET}.gz"#
    fi

    echo -e "\n## Done"

}

create_image
