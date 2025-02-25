const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn create_directory_with_many_files(alloc: Allocator, dir_name: []const u8, file_count: usize, fs_path: []const u8) !void {
    const mount_result = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "sudo", "mount", "-o", "loop", "-t", "ext2", fs_path, "mnt" },
    });
    alloc.free(mount_result.stdout);
    alloc.free(mount_result.stderr);

    {
        const mkdir_path = try std.fmt.allocPrint(alloc, "mnt/{s}", .{dir_name});
        defer alloc.free(mkdir_path);

        const mkdir_result = try std.process.Child.run(.{
            .allocator = alloc,
            .argv = &.{ "sudo", "mkdir", "-p", mkdir_path },
        });
        alloc.free(mkdir_result.stdout);
        alloc.free(mkdir_result.stderr);

        for (0..file_count) |i| {
            const file_name = try std.fmt.allocPrint(alloc, "mnt/{s}/file_{d}", .{dir_name, i});
            defer alloc.free(file_name);

            const touch_result = try std.process.Child.run(.{
                .allocator = alloc,
                .argv = &.{ "sudo", "touch", file_name },
            });
            alloc.free(touch_result.stdout);
            alloc.free(touch_result.stderr);
        }
    }

    const umount_result = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "sudo", "umount", "mnt" },
    });
    alloc.free(umount_result.stdout);
    alloc.free(umount_result.stderr);
}

pub fn cleanup_directory_with_files(alloc: Allocator, dir_name: []const u8, fs_path: []const u8) !void {
    var is_mounted = false;

    const mount_check = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "mount" },
    });
    is_mounted = std.mem.indexOf(u8, mount_check.stdout, "mnt") != null;
    alloc.free(mount_check.stdout);
    alloc.free(mount_check.stderr);

    if (!is_mounted) {
        const mount_result = try std.process.Child.run(.{
            .allocator = alloc,
            .argv = &.{ "sudo", "mount", "-o", "loop", "-t", "ext2", fs_path, "mnt" },
        });
        alloc.free(mount_result.stdout);
        alloc.free(mount_result.stderr);
    }

    const rm_path = try std.fmt.allocPrint(alloc, "mnt/{s}", .{dir_name});
    defer alloc.free(rm_path);

    const rm_result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "sudo", "rm", "-rf", rm_path },
    });

    if (rm_result) |res| {
        alloc.free(res.stdout);
        alloc.free(res.stderr);
    } else |_| {}

    if (!is_mounted) {
        const umount_result = try std.process.Child.run(.{
            .allocator = alloc,
            .argv = &.{ "sudo", "umount", "mnt" },
        });
        alloc.free(umount_result.stdout);
        alloc.free(umount_result.stderr);
    }
}
