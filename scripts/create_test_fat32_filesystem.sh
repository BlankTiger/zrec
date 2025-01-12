#!/usr/bin/env bash

truncate --size=1000M fat32_filesystem.img
sudo mkfs -t vfat fat32_filesystem.img
