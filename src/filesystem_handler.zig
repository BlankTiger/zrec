const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = @import("reader.zig").Reader;
const FAT32 = @import("fat.zig").FAT32;
const NTFS = @import("ntfs.zig").NTFS;

pub const FilesystemHandler = struct {
    alloc: Allocator,
    path: []const u8,
    files: std.ArrayList(*std.fs.File),
    readers: std.ArrayList(*Reader),

    const Self = @This();

    const Error =
        FAT32.Error
        || NTFS.Error
        || Allocator.Error
        || std.fs.File.ReadError
        || std.fs.File.OpenError
        || error{ NoFilesystemMatch };

    pub fn init(alloc: Allocator, filepath: []u8) Error!Self {
        return Self {
            .alloc = alloc,
            .path = try alloc.dupe(u8, filepath),
            .files = std.ArrayList(*std.fs.File).init(alloc),
            .readers = std.ArrayList(*Reader).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.path);
        for (self.files.items) |f| {
            f.close();
            self.alloc.destroy(f);
        }
        self.files.deinit();
        for (self.readers.items) |r| self.alloc.destroy(r);
        self.readers.deinit();
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

    /// Caller must call deinit on the resulting Filesystem
    pub fn determine_filesystem(self: *Self) Error!Filesystem {
        if (FAT32.init(self.alloc, try self.create_new_reader())) |fat32| return .{ .fat32 = fat32 } else |_| {}
        if (NTFS.init(self.alloc, try self.create_new_reader())) |ntfs| return .{ .ntfs = ntfs } else |_| {}
        return Error.NoFilesystemMatch;
    }

    fn create_new_reader(self: *Self) Error!*Reader {
        const f = try self.alloc.create(std.fs.File);
        f.* = try std.fs.cwd().openFile(self.path, .{});
        try self.files.append(f);
        const r = f.reader();
        const br = try self.alloc.create(Reader);
        br.* = std.io.bufferedReader(r);
        try self.readers.append(br);
        return br;
    }
};

