#!/bin/bash

set -euo pipefail

cat /proc/cpuinfo

package_to_build="${1:-}"

BUILD_DIR="/build"
ASSETS_DIR="${BUILD_DIR}/assets"
PKG_DIR="${BUILD_DIR}/packages"

function builder_do() {
    sudo -u builduser bash -c "$*"
}

function init_system() {
    pacman-key --init

    pacman-key --populate

    pacman -Syu --noconfirm

    pacman -S --noconfirm --needed base-devel wget git

    pacman -Scc --noconfirm

    mv "${BUILD_DIR}/makepkg-custom.conf" /etc/makepkg.conf.d/custom.conf

    mkdir -p "${ASSETS_DIR}"
}

function create_normal_user() {
    useradd -m -s /bin/bash builduser

    chown builduser:builduser -R "${BUILD_DIR}"

    passwd -d builduser

    printf 'builduser ALL=(ALL) ALL\n' | tee -a /etc/sudoers

    git config --global --add safe.directory "${BUILD_DIR}"
}

function build_package() {
    local _pkg="$1"

    echo "Building package: ${_pkg}"

    cd "${PKG_DIR}" || exit 1

    local _pkgbuild_dir

    _pkgbuild_dir="$(find . -type d -name "${_pkg}" -printf "%f\n" || true)"

    chown builduser:builduser -R "${_pkg}"

    cd "${_pkg}" || exit 1

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

    find . -name "*.pkg.tar.*" -exec mv {} "${ASSETS_DIR}"/ \;
}

function generate_checksum() {
    cd "${ASSETS_DIR}"

     echo "| 文件名 | SHA256 校验值 |" > checksums.md
     echo "|--------|----------------|" >> checksums.md

     for file in *.pkg.tar.zst
     do
         hash=$(sha256sum "$file" | cut -d ' ' -f 1)
         echo "| $file | $hash |" >> checksums.md
     done
}

function main() {
    init_system

    create_normal_user

    build_package "$package_to_build"

    generate_checksum
}

main
