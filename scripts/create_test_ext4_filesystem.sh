#!/usr/bin/env bash

truncate --size=200M ext4_filesystem.img
dd if=/dev/zero of=ext4_filesystem.img count=409600
sudo mkfs.ext4 ext4_filesystem.img
