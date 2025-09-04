#!/bin/bash

set -e

export LOCAL_DIR
LOCAL_DIR=$(pwd)
export PACKAGE_VERSION="0.1.0"
export PACKAGE_NAME="${LOCAL_DIR##*/}"
export PACKAGE_RELEASE="0"
export REPOSITORY_PATH="adev"
export TARGET_DISTRO
export TARGET_DISTRO_VERSION

TARGET_DISTRO="$(grep -E '^NAME=' /etc/os-release | grep -o "\"[a-z,A-Z]*" | grep -o "[a-z,A-Z]*" | tr "[:upper:]" "[:lower:]")"
if [ "${TARGET_DISTRO}" = 'centos' ] || [ "${TARGET_DISTRO}" = 'rocky' ]; then TARGET_DISTRO="el"; fi
if [ "${TARGET_DISTRO}" = 'fedora' ]; then TARGET_DISTRO="fc"; fi
echo "TARGET_DISTRO=\"${TARGET_DISTRO}\""

if [ "${TARGET_DISTRO}" = 'ubuntu' ] || [ "${TARGET_DISTRO}" = 'debian' ]; then TARGET_DISTRO_VERSION="$(grep -E '^VERSION=' /etc/os-release | grep -o "([a-z,A-Z]*" | grep -o "[a-z,A-Z]*" | tr "[:upper:]" "[:lower:]")"; fi
if [ "${TARGET_DISTRO}" = 'fc' ] || [ "${TARGET_DISTRO}" = 'el' ]; then TARGET_DISTRO_VERSION="$(grep -E '^VERSION=' /etc/os-release | grep -o "\"[0-9]*" | grep -o "[0-9]*")"; fi
echo "TARGET_DISTRO_VERSION=\"${TARGET_DISTRO_VERSION}\""

function apt_install() {
	echo "Criando pacote."
	./make_deb_package
	echo "Instalando pacote."
	apt update
	#apt -y -f install "${LOCAL_DIR}/artifacts/${REPOSITORY_PATH}/${TARGET_DISTRO}/${TARGET_DISTRO_VERSION}/${PACKAGE_NAME}_${PACKAGE_VERSION}-${REPOSITORY_PATH}.${PACKAGE_RELEASE}_amd64.deb"
	dpkg -i "${LOCAL_DIR}/artifacts/${REPOSITORY_PATH}/${TARGET_DISTRO}/${TARGET_DISTRO_VERSION}/${PACKAGE_NAME}_${PACKAGE_VERSION}-${REPOSITORY_PATH}.${PACKAGE_RELEASE}_amd64.deb" || apt -f -y install
	echo "Excluindo artifacts."
	rm -rf artifacts
	rm -Rf ~/debbuild
}

function apt_uninstall() {
	echo "Removendo pacote."
	apt -y autoremove "${PACKAGE_NAME}"
}

function dnf_install() {
	echo "Criando pacote."
	./make_rpm_package
	echo "Instalando pacote."
	dnf -y install "artifacts/${REPOSITORY_PATH}/${TARGET_DISTRO}/${TARGET_DISTRO_VERSION}/${PACKAGE_NAME}-${PACKAGE_VERSION}-${REPOSITORY_PATH}.${PACKAGE_RELEASE}.${TARGET_DISTRO}${TARGET_DISTRO_VERSION}.x86_64.rpm"
	echo "Excluindo artifacts."
	rm -rf artifacts
	rm -Rf ~/rpmbuild
}

function dnf_uninstall() {
	echo "Removendo pacote."
	dnf -y remove --skip-broken "${PACKAGE_NAME}"
}

function yum_install() {
	echo "Criando pacote."
	./make_rpm_package
	echo "Instalando pacote."
	yum -y --nogpgcheck localinstall "artifacts/${REPOSITORY_PATH}/${TARGET_DISTRO}/${TARGET_DISTRO_VERSION}/${PACKAGE_NAME}-${PACKAGE_VERSION}-${REPOSITORY_PATH}.${PACKAGE_RELEASE}.${TARGET_DISTRO}${TARGET_DISTRO_VERSION}.x86_64.rpm"
	echo "Excluindo artifacts."
	rm -rf artifacts
	rm -Rf ~/rpmbuild
}

function yum_uninstall() {
	echo "Removendo pacote."
	yum -y remove "${PACKAGE_NAME}"; yum -y autoremove
}

if apt --version; then
	if [[ "${1}" != "uninstall" ]]; then
		apt_install
	else
		apt_uninstall
	fi
else
	if dnf --version; then
		if [[ "${1}" != "uninstall" ]]; then
			dnf_install
		else
			dnf_uninstall
		fi
	else
		if [[ "${1}" != "uninstall" ]]; then
			yum_install
		else
			yum_uninstall
		fi
	fi
fi

echo "Fim!!!"
