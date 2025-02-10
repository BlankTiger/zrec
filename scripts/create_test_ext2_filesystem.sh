#!/usr/bin/env bash
set -xe

mkdir -p filesystems/
mkdir -p mnt/
truncate --size=1000M filesystems/ext2_filesystem.img
sudo mkfs -t ext2 filesystems/ext2_filesystem.img
sudo mount -o loop -t ext2 filesystems/ext2_filesystem.img mnt
sudo cp -rv ./input/* mnt
sudo umount mnt
