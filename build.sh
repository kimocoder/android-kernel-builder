#!/bin/bash
#
# Copyright (C) 2020 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

while [ "${#}" -gt 0 ]; do
	case "${1}" in
		-c | --clean )
			CLEAN="true"
			;;
		--kernel-headers )
			KERNEL_HEADERS="true"
			;;
		* )
			PROJECT="${1}"
			;;
	esac
	shift
done

# Set defaults directories and variables
ROOT_DIR="$(pwd)"
ANYKERNEL_DIR="${ROOT_DIR}/anykernel3"
CONFIGS_DIR="${ROOT_DIR}/configs"
KERNELS_DIR="${ROOT_DIR}/kernels"
OUT_DIR="${ROOT_DIR}/out"
PREBUILTS_DIR="${ROOT_DIR}/prebuilts"
TOOLS_DIR="${ROOT_DIR}/tools"
DATE="$(date +"%m-%d-%y")"

# Source config files
if [ ! -f "${CONFIGS_DIR}/${PROJECT}" ]; then
	echo "Error: project configuration file not found"
	exit
fi

source "${TOOLS_DIR}/functions.sh"
source "${TOOLS_DIR}/variables.sh"
source "${ROOT_DIR}/settings.conf"
source "${CONFIGS_DIR}/${PROJECT}"

KERNEL_DIR="${KERNELS_DIR}/${KERNEL_DIR_NAME}"

# Set kernel source workspace
cd "${KERNEL_DIR}"

KERNEL_LAST_COMMIT=$(git log -1 --format="%h")
if [ ${KERNEL_LAST_COMMIT} = "" ]; then
	KERNEL_LAST_COMMIT="Unknown"
fi
BUILD_START="$(date +'%s')"

create_localversion
print_summary
setup_building_variables

# Clean
if [ "${CLEAN}" = "true" ]; then
	printf "Running command: make clean"
	make ${MAKE_FLAGS} clean &> ${OUT_DIR}/clean_log.txt
	CLEAN_SUCCESS=$?
	if [ "${CLEAN_SUCCESS}" != 0 ]; then
		echo "${red}Error: make clean failed${reset}"
		exit
	else
		echo ": done"
	fi

	printf "Running command: make mrproper"
	make ${MAKE_FLAGS} mrproper &> ${OUT_DIR}/mrproper_log.txt
	MRPROPER_SUCCESS=$?
	if [ "${MRPROPER_SUCCESS}" != 0 ]; then
		echo "${red}Error: make mrproper failed${reset}"
		exit
	else
		echo ": done"
	fi
fi

# Make defconfig
printf "Running command: make ${DEFCONFIG}"
make ${MAKE_FLAGS} ${DEFCONFIG} &> ${OUT_DIR}/defconfig_log.txt

DEFCONFIG_SUCCESS=$?
if [ "${DEFCONFIG_SUCCESS}" != 0 ]; then
	echo "${red}Error: make ${DEFCONFIG} failed, specified a defconfig not present?${reset}"
	exit
else
	echo ": done"
fi

if [ "${KERNEL_HEADERS}" != "true" ]; then
	# Build kernel
	echo "Running command: make"
	make ${MAKE_FLAGS} | tee ${OUT_DIR}/build_log.txt | while read i; do printf "%-${COLUMNS}s\r" "$i"; done
else
	# Build kernel headers
	echo "Running command: make headers_install"
	make ${MAKE_FLAGS} headers_install | tee ${OUT_DIR}/build_log.txt | while read i; do printf "%-${COLUMNS}s\r" "$i"; done
fi

BUILD_SUCCESS=$?
BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))
printf "%-${COLUMNS}s\r"
if [ "${BUILD_SUCCESS}" != 0 ]; then
	echo "${red}Error: Build failed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds${reset}"
	exit
fi

echo ""
echo -e "${green}Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds${reset}"
echo ""

[ "${KERNEL_HEADERS}" = "true" ] && exit

printf "Making flashable zip using anykernel3"

cd "${ROOT_DIR}"

# Always reclone AK3
[ -d "${ANYKERNEL_DIR}" ] && rm -rf "${ANYKERNEL_DIR}"
git clone https://github.com/osm0sis/AnyKernel3 "${ANYKERNEL_DIR}" -q

# Include build artifacts in anykernel3 zip
for i in $BUILD_ARTIFACTS; do
	cp "$OUT_DIR/arch/$ARCH/boot/$i" "$ANYKERNEL_DIR/$i"
done

cd "${ANYKERNEL_DIR}"

create_ak3_config
create_ak3_zip_filename

# Build a flashable zip using anykernel3
zip -r9 "${AK3_ZIP_NAME}" * -x .git/ README.md "${AK3_ZIP_NAME}" > /dev/null

echo ": done"

# Return to initial pwd
cd "${ROOT_DIR}"

echo "${green}All done${reset}"
echo "Flashable zip: ${ANYKERNEL_DIR}/${AK3_ZIP_NAME}"
