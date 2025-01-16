#!/usr/bin/env bash
set -xe

mkdir -p filesystems/
mkdir -p mnt/
truncate --size=1000M filesystems/fat32_filesystem.img
sudo mkfs -t vfat filesystems/fat32_filesystem.img
sudo mount -o loop -t vfat filesystems/fat32_filesystem.img mnt
sudo cp -rv ./input/* mnt
sudo umount mnt
