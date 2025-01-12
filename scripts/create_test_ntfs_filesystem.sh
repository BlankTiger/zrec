#!/usr/bin/env bash

truncate --size=200M ntfs_filesystem.img
dd if=/dev/zero of=ntfs_filesystem.img count=409600
sudo mkfs -t ntfs ntfs_filesystem.img
