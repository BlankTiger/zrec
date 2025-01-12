const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = @import("reader.zig").Reader;
const FAT32 = @import("fat.zig").FAT32;
const NTFS = @import("ntfs.zig").NTFS;

pub const FilesystemHandler = struct {
    alloc: Allocator,
    file: std.fs.File,
    reader: Reader,

    const Self = @This();

    const Error =
        FAT32.Error
        || NTFS.Error
        || Allocator.Error
        || std.fs.File.ReadError
        || std.fs.File.OpenError
        || error{ NoFilesystemMatch };

    pub fn init(alloc: Allocator, filepath: []u8) Error!Self {
        const f = try std.fs.cwd().openFile(filepath, .{});
        const f_reader = f.reader();
        const b_reader = std.io.bufferedReader(f_reader);
        return Self {
            .alloc = alloc,
            .file = f,
            .reader = b_reader,
        };
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
        self.* = undefined;
    }

    const Filesystem = union(enum) {
        fat32: FAT32,
        ntfs: NTFS,
        // ext4: EXT4,
        // ext3: EXT3,
        // ext2: EXT2,

        pub fn deinit(self: *Filesystem) void {
            switch (self.*) {
                .fat32 => |*fat32| fat32.deinit(),
                .ntfs => |*ntfs| ntfs.deinit(),
            }
            self.* = undefined;
        }
    };

    /// Caller must call deinit on result
    pub fn determine_filesystem(self: *Self) Error!Filesystem {
        if (FAT32.init(self.alloc, &self.reader)) |fat32| return .{ .fat32 = fat32 } else |_| {}
        if (NTFS.init(self.alloc, &self.reader)) |ntfs| return .{ .ntfs = ntfs } else |_| {}
        return Error.NoFilesystemMatch;
    }
};

