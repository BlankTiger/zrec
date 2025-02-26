const std = @import("std");
const log = std.log.scoped(.fs_creator);

pub const FSType = enum {
    fat32,
    ntfs,
    ext2,
};

pub fn init(fs_type: FSType, alloc: std.mem.Allocator) Self {
    var creator = switch (fs_type) {
        .fat32 => fat32_creator,
        .ntfs  => ntfs_creator,
        .ext2  => ext2_creator,
    };
    creator.alloc = alloc;
    creator.cwd = std.fs.cwd();
    creator.fs_type = fs_type;
    return creator;
}

const ext2_creator: Self = .{
    .alloc = undefined,
    .cwd = undefined,
    .fs_type = undefined,
    .path = "filesystems/ext2_filesystem.img",
    .fs_type_str = "ext2",
    .size = 1000,
};

const fat32_creator: Self = .{
    .alloc = undefined,
    .cwd = undefined,
    .fs_type = undefined,
    .path = "filesystems/fat32_filesystem.img",
    .fs_type_str = "vfat",
    .size = 1000,
};

const ntfs_creator: Self = .{
    .alloc = undefined,
    .cwd = undefined,
    .fs_type = undefined,
    .path = "filesystems/ntfs_filesystem.img",
    .fs_type_str = "ntfs",
    .size = 200,
};

alloc: std.mem.Allocator,
cwd: std.fs.Dir,
path: []const u8,
fs_type: FSType,
fs_type_str: []const u8,
/// in Megabytes.
size: usize,

const Self = @This();

fn handle_res(res: std.process.Child.RunResult) void {
    handle_res_exit(res, true);
}

fn handle_res_exit(res: std.process.Child.RunResult, exit: bool) void {
    if (res.stdout.len > 0) log.debug("{s}", .{res.stdout});
    if (res.stderr.len > 0) log.err("{s}", .{res.stderr});
    if (res.term.Exited != 0 and exit) std.process.exit(res.term.Exited);
}

pub fn prepare_workspace(self: Self) !void {
    const res = try std.process.Child.run(
        .{
            .allocator = self.alloc,
            .cwd_dir = self.cwd,
            .argv = &.{
                "mkdir",
                "filesystems",
            }
        }
    );
    handle_res_exit(res, false);

    const res2 = try std.process.Child.run(
        .{
            .allocator = self.alloc,
            .cwd_dir = self.cwd,
            .argv = &.{
                "mkdir",
                "mnt",
            }
        }
    );
    handle_res_exit(res2, false);
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
    handle_res(res);
}

pub fn mkfs(self: Self) !void {
    if (self.fs_type == .ntfs) {
        const res = try std.process.Child.run(
            .{
                .allocator = self.alloc,
                .cwd_dir = self.cwd,
                .argv = &.{
                    "sudo",
                    "mkntfs",
                    "-F",
                    self.path,
                }
            }
        );
        handle_res(res);
        return;
    }
    const res = try std.process.Child.run(
        .{
            .allocator = self.alloc,
            .cwd_dir = self.cwd,
            .argv = &.{
                "sudo",
                "mkfs",
                "-t",
                self.fs_type_str,
                self.path,
            }
        }
    );
    handle_res(res);
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
    handle_res(res);
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
                self.fs_type_str,
                self.path,
                "mnt",
            }
        }
    );
    handle_res(res);
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
    handle_res(res);
}
