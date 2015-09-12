SUMMARY = "Copy script.sh to image deployment area"
SECTION = "devel"
LICENSE = "GPLv2"
LIC_FILES_CHKSUM = \
"file://${WORKDIR}/create-sdimage.sh;beginline=3;endline=6;md5=8155402deeb8664ea82821f9df65ae25"
SRC_URI = "file://create-sdimage.sh" \
	  "file://uEnv.txt"

#This package doesn't have any files for the rootfs in it, option needed to create an empty
# package so when the rootfs image is made it finds the custom-script_xxx.deb package and
# doesn't complain
FILES_${PN} = ""
ALLOW_EMPTY_${PN} = "1"


do_print_install_steps () {
    echo "To deploy the generated image on an sd-card, please follow these steps :"
    echo "0> cd "${DEPLOY_DIR_IMAGE}
    echo "If this is your first time using the target sd-card, do the following :"
    echo "1> sudo create_sdimage.sh --wipe-all /dev/sdX #where sdX is your sd-card device file"
    echo "else, do the following :"
    echo "1> sudo create_sdimage.sh /dev/sdX #where sdX is your sd-card device file"
    echo "if you want to update only a part of the deployed image, you can pass that"
    echo "as an option via commands (which can be mixed together) :"
    echo "   --update-rootfs"
    echo "   --update-kernel"
    echo "   --update-uboot"
    echo "recipe developed by Oussema Harbi <oussema.elharbi@gmail.com>"
}

# Copy script to the deploy area with u-boot, uImage and rootfs
do_deploy () {
    install -d ${DEPLOY_DIR_IMAGE}
    install -m 0755 ${WORKDIR}/create-sdimage.sh ${DEPLOY_DIR_IMAGE}
    install -m 0555 ${WORKDIR}/uEnv.txt ${DEPLOY_DIR_IMAGE}
}
addtask deploy after do_install
addtask print_install_steps after do_deploy
