#!/bin/bash
#
# (c) Copyright 2015 Oussema Harbi <oussema.elharbi@gmail.com>
# Licensed under terms of GPLv2
#
# Based on different scripts provided in meta-bb yocto layer
#

usage() {
   echo -e "\e[97m" #Switch to WHITE colour
   echo $(basename $0)" [OPTIONS] [-d|--drive]device_file"
   echo "Possible options are :"
   echo " --wipe-all      -> Create a new parition table on the sd-card and wipe all previous data"
   echo " --update-rootfs -> Only update rootfs parition with the newly generated rootfs"
   echo " --update-kernel -> Only update kernel with the newly compiled kernel"
   echo " --update-uboot  -> Only update uboot image and env files"
   echo " --image xxx     -> Install image xxx on the sd-card"
   echo " --hostname xxx  -> Use xxx as hostname of the target system"
   echo ""
   echo "Script developed by Oussema Harbi <oussema.elharbi@gmail.com>"
   echo -e "\e[0m" #Switch back to defaul colour
}

#Function to format sd card and create 3 paritions
# Partition_1 for boot
# Partition_2 for rootfs
# Partition_3 for custom usage
format_sd_card() {
	DRIVE=$1
	echo -e "\e[031mFormatting $DRIVE\e[0m\n"

	#make sure that the SD card isn't mounted before we start
	if [ -b ${DRIVE}1 ]; then
		umount ${DRIVE}1
		umount ${DRIVE}2
		umount ${DRIVE}3
	elif [ -b ${DRIVE}p1 ]; then
		umount ${DRIVE}p1
		umount ${DRIVE}p2
		umount ${DRIVE}p3
	else
		umount ${DRIVE}
	fi


	SIZE=`fdisk -l $DRIVE | grep "Disk $DRIVE" | cut -d' ' -f5`

	echo DISK SIZE – $SIZE bytes

	if [ "$SIZE" -lt 3980000000 ]; then
		echo -e "\e[31mA 5GB sd card is or bigger is required for this script to work\e[0m\n"
		exit 1
	fi

	CYLINDERS=`echo $SIZE/255/63/512 | bc`

	echo CYLINDERS – $CYLINDERS

	echo -e "\n\e[97m=== Zeroing the MBR ===\e[0m\n"
	dd if=/dev/zero of=$DRIVE bs=1024 count=1024

	## Standard 2 partitions
	# Sectors are 512 bytes
	# 0-127: 64KB, no partition, MBR then empty
	# 128-131071: ~64 MB, dos partition, MLO, u-boot, kernel
	# 131072-4194303: ~2GB, linux partition, root filesystem
	# 4194304-end: 2GB+, linux partition, no assigned use

	echo -e "\n\e[097m=== Creating 3 partitions ===\e[0m\n"
	{
	echo 128,130944,0x0C,*
	echo 131072,4063232,0x83,-
	echo 4194304,+,0x83,-
	} | sfdisk --force -D -uS -H 255 -S 63 -C $CYLINDERS $DRIVE

	sleep 1
}

#Function to copy uboot files to sd card boot partition
copy_uboot() {
	drive=$1
	if [[ $# > 1 ]];then
		update_only=1
	else
		update_only=0
	fi
	#This script works with machine type beaglebone, not tested with other types
	MACHINE=beaglebone

	if [ ! -d /media/card ]; then
		echo "Mount point /media/card does not exist";
		exit 1
	fi

	if [ -z "$OETMP" ]; then
		echo -e "\nWorking from local directory"
		SRCDIR=.
	else
		echo -e "\nOETMP: $OETMP"

		if [ ! -d ${OETMP}/deploy/images/${MACHINE} ]; then
			echo "Directory not found: ${OETMP}/deploy/images/${MACHINE}"
			exit 1
		fi

		SRCDIR=${OETMP}/deploy/images/${MACHINE}
	fi 

	if [ ! -f ${SRCDIR}/MLO-${MACHINE} ]; then
		echo -e "File not found: ${SRCDIR}/MLO-${MACHINE}\n"
		exit 1
	fi

	if [ ! -f ${SRCDIR}/u-boot-${MACHINE}.img ]; then
		echo -e "File not found: ${SRCDIR}/u-boot-${MACHINE}.img\n"
		exit 1
	fi

	DEV=$drive"1"

	if [ -b $DEV ]; then
		if [[ $update_only -eq 0 ]];then
			echo "Formatting FAT partition on $DEV"
			sudo mkfs.vfat -F 32 ${DEV} -n BOOT
		fi

		echo "Mounting $DEV"
		sudo mount ${DEV} /media/card

		echo "Copying MLO"
		sudo cp ${SRCDIR}/MLO-${MACHINE} /media/card/MLO

		echo "Copying u-boot"
		sudo cp ${SRCDIR}/u-boot-${MACHINE}.img /media/card/u-boot.img

		if [ -f ${SRCDIR}/uEnv.txt ]; then
			echo "Copying ${SRCDIR}/uEnv.txt to /media/card"
			sudo cp ${SRCDIR}/uEnv.txt /media/card
		elif [ -f ./uEnv.txt ]; then
			echo -e "Copying ./uEnv.txt to /media/card"
			sudo cp ./uEnv.txt /media/card
		fi

		echo "Unmounting ${DEV}"
		sudo umount ${DEV}
	else
		echo -e "\n\e[31mBlock device not found: $DEV\e[0m\n"
	fi
}

#Copy rootfs
copy_rootfs() {
	DRIVE=$1
	IMAGE=$2
	HOSTNAME=$3
	MACHINE=beaglebone

	if [ ! -d /media/card ]; then
		echo "Mount point /media/card does not exist"
		exit 1
	fi

	if [ -z "$OETMP" ]; then
		echo -e "\nWorking from local directory"
		SRCDIR=.
	else
		echo -e "\nOETMP: $OETMP"

		if [ ! -d ${OETMP}/deploy/images/${MACHINE} ]; then
			echo "Directory not found: ${OETMP}/deploy/images/${MACHINE}"
			exit 1
		fi

		SRCDIR=${OETMP}/deploy/images/${MACHINE}
	fi 

	if [ ! -f "${SRCDIR}/${IMAGE}-image-${MACHINE}.tar.xz" ]; then
			echo "File not found: ${SRCDIR}/${IMAGE}-image-${MACHINE}.tar.xz"
			exit 1
	fi

	DEV=$DRIVE"2"

	if [ -b $DEV ]; then
	    echo "Unmounting"
	    sudo umount $DEV

		echo "Formatting $DEV as ext4"
		sudo mkfs.ext4 -q -L ROOT $DEV

		echo "Mounting $DEV"
		sudo mount $DEV /media/card

		echo "Extracting ${IMAGE}-image-${MACHINE}.tar.xz to /media/card"
		sudo tar -C /media/card -xJf ${SRCDIR}/${IMAGE}-image-${MACHINE}.tar.xz

		echo "Writing hostname to /etc/hostname"
		export TARGET_HOSTNAME
		sudo -E bash -c 'echo ${HOSTNAME} > /media/card/etc/hostname'        

		if [ -f ${SRCDIR}/interfaces ]; then
			echo "Writing interfaces to /media/card/etc/network/"
			sudo cp ${SRCDIR}/interfaces /media/card/etc/network/interfaces
		fi

		if [ -f ${SRCDIR}/wpa_supplicant.conf ]; then
			echo "Writing wpa_supplicant.conf to /media/card/etc/"
			sudo cp ${SRCDIR}/wpa_supplicant.conf /media/card/etc/wpa_supplicant.conf
		fi

		echo "Unmounting $DEV"
		sudo umount $DEV
	else
		echo "Block device $DEV does not exist"
	fi
}

#Main execution path starts here
if [[ $# < 1 ]]; then
    echo -e "\e[31mPlease provide the sd-card device file path\e[0m" #Error msg in RED
	usage
	exit
fi

#Init configuration
drive=""
reformat=0
update_rootfs=0
update_kernel=0
update_boot=0
image="console"
custom_hostname="bbb"

#Parse command line arguments
while [[ $# > 0 ]]
do

option="$1"
case $option in
	--wipe-all)
	reformat=1
	update_rootfs=1
	update_kernel=1
	update_boot=1
	;;
	--update-rootfs)
	update_rootfs=1
	;;
	--update-kernel)
	update_kernel=1
	;;
	--update-uboot)
	update_boot=1
	;;
	-d|--drive)
	drive=$2
	shift
	;;
	--hostname)
	custom_hostname=$2
	shift
	;;
	--image)
	image=$2
	shift
	;;
	*) #All other possibilities
	echo -e "\e[031mUnrecognized option : $option\e[0m"
	usage
	exit
	;;
esac
shift #get the next argument
done

echo "Using configuration :"
echo " >drive         = "$drive
echo " >reformat      = "$reformat
echo " >update rootfs = "$update_rootfs
echo " >update kernel = "$update_kernel
echo " >update uboot  = "$update_boot
echo " >image type    = "$image
echo " >hostname      = "$custom_hostname

#Format if needed
if [[ $reformat -eq 1 ]];then
	format_sd_card $drive
fi

#Create the mount point to be used for copy
if [[ ! -d /media/card ]];then
	mkdir -p /media/card
fi

#Copy Boot if needed
if  [[ $update_boot -eq 1 ]];then
	copy_uboot $drive
fi

#Copy rootfs if needed
if [[ update_rootfs -eq 1 ]];then
	copy_rootfs $drive $image $custom_hostname
fi

#Unmount everything (A second hand check for security)
echo "Unmounting sd card"
if [ -b ${drive}1 ]; then
	umount ${drive}1
	umount ${drive}2
	umount ${drive}3
elif [ -b ${drive}p1 ]; then
	umount ${drive}p1
	umount ${drive}p2
	umount ${drive}p3
else
	umount ${drive}
fi
