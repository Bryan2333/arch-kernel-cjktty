#!/bin/bash

set -euo pipefail

cat /proc/cpuinfo

BUILD_DIR="/build"

function builder_do() {
    sudo -u builduser bash -c "$*"
}

function init_system() {
    pacman-key --init

    pacman-key --populate

    pacman -Syu --noconfirm

    pacman -S --noconfirm --needed base-devel git

    pacman -Scc --noconfirm

    mv "${BUILD_DIR}/makepkg-custom.conf" /etc/makepkg.conf.d/custom.conf
}

function create_normal_user() {
    useradd -m -s /bin/bash builduser

    setfacl -m u:builduser:rwx -R "${BUILD_DIR}"

    passwd -d builduser

    printf 'builduser ALL=(ALL) ALL\n' | tee -a /etc/sudoers

    git config --global --add safe.directory "${BUILD_DIR}"
}

function build_package() {
    cd "${BUILD_DIR}"

    (
        if grep -qE "validpgpkeys" PKGBUILD
        then
            source PKGBUILD

            for key in "${validpgpkeys[@]}"
            do
                builder_do gpg --recv-keys "${key}" || echo "Failed to import key: ${key}"
            done
        fi
    )

    local _makepkg_args=("--syncdeps" "--clean" "--noconfirm")

    builder_do makepkg "${_makepkg_args[*]}"
}

function generate_checksum() {
    cd "${BUILD_DIR}"

    echo "| 文件名 | SHA256 校验值 |" > checksums.md
    echo "|--------|----------------|" >> checksums.md

    for file in *.pkg.tar.zst
    do
        hash="$(sha256sum "${file}" | cut -d ' ' -f 1)"
        echo "| ${file} | ${hash} |" >> checksums.md
    done
}

function main() {
    init_system

    create_normal_user

    build_package

    generate_checksum
}

main
