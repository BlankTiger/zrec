const std = @import("std");
const log = std.log.scoped(.fs_creator);

pub const FSType = enum {
    fat32,
    ntfs,
    ext2,
};

pub fn init(fs_type: FSType, alloc: std.mem.Allocator, cwd: std.fs.Dir) Self {
    var creator = switch (fs_type) {
        .fat32 => fat32_creator,
        .ntfs  => ntfs_creator,
        .ext2  => ext2_creator,
    };
    creator.alloc = alloc;
    creator.cwd = cwd;
    return creator;
}

const ext2_creator: Self = .{
    .alloc = undefined,
    .cwd = undefined,
    .path = "filesystems/ext2_filesystem.img",
    .fs_type = "ext2",
    .size = 1000,
};

const fat32_creator: Self = .{
    .alloc = undefined,
    .cwd = undefined,
    .path = "filesystems/fat32_filesystem.img",
    .fs_type = "vfat",
    .size = 1000,
};

const ntfs_creator: Self = .{
    .alloc = undefined,
    .cwd = undefined,
    .path = "filesystems/ntfs_filesystem.img",
    .fs_type = "ntfs",
    .size = 200,
};

alloc: std.mem.Allocator,
cwd: std.fs.Dir,
path: []const u8,
fs_type: []const u8,
/// in Megabytes.
size: usize,

const Self = @This();

fn log_res(res: std.process.Child.RunResult) void {
    if (res.stdout.len > 0) log.debug("{s}", .{res.stdout});
    if (res.stderr.len > 0) log.err("{s}", .{res.stderr});
}

pub fn truncate(self: Self) !void {
    const res = try std.process.Child.run(
        .{
            .allocator = self.alloc,
            .cwd_dir = self.cwd,
            .argv = &.{
                "truncate",
                try std.fmt.allocPrint(self.alloc, "--size={d}M", .{self.size}),
                self.path,
            }
        }
    );
    log_res(res);
}

pub fn mkfs(self: Self) !void {
    const res = try std.process.Child.run(
        .{
            .allocator = self.alloc,
            .cwd_dir = self.cwd,
            .argv = &.{
                "sudo",
                "mkfs",
                "-t",
                self.fs_type,
                self.path,
            }
        }
    );
    log_res(res);
}

pub fn copy_files(self: Self) !void {
    const command = &.{ "sudo", "cp", "-rv", "input/.", "mnt" };
    const res = try std.process.Child.run(
        .{
            .allocator = self.alloc,
            .cwd_dir = self.cwd,
            .argv = command,
        }
    );
    log_res(res);
}

pub fn mount(self: Self) !void {
    const res = try std.process.Child.run(
        .{
            .allocator = self.alloc,
            .cwd_dir = self.cwd,
            .argv = &.{
                "sudo",
                "mount",
                "-o",
                "loop",
                "-t",
                self.fs_type,
                self.path,
                "mnt",
            }
        }
    );
    log_res(res);
}

pub fn umount(self: Self) !void {
    const res = try std.process.Child.run(
        .{
            .allocator = self.alloc,
            .cwd_dir = self.cwd,
            .argv = &.{
                "sudo",
                "umount",
                "mnt",
            }
        }
    );
    log_res(res);
}
