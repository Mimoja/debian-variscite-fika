#!/bin/bash

if [ -z $1 ]; then
	echo "Please provide the .png to be used as the new boot logo"
	exit 1
fi

dir=$(dirname $0)

script_path="$(pwd)/${dir}"

old_md5=$(md5sum ${script_path}/src/kernel/drivers/video/logo/logo_meticulous_clut244.ppm | awk '{ print $1 }' )

pngtopnm $1  | ppmquant 224 | pnmnoraw > ${script_path}/src/kernel/drivers/video/logo/logo_meticulous_clut244.ppm

new_md5=$(md5sum ${script_path}/src/kernel/drivers/video/logo/logo_meticulous_clut244.ppm | awk '{ print $1 }' )
echo "Old md5=$old_md5"
echo "New md5=$new_md5"
