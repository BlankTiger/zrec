const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("lib.zig");
const Reader = lib.Reader;
const FAT32 = @import("filesystems/fat.zig").FAT32;
const NTFS = @import("filesystems/ntfs.zig").NTFS;

pub const FilesystemHandler = struct {
    alloc: Allocator,
    path: []const u8,
    _files: std.ArrayList(*std.fs.File),
    _readers: std.ArrayList(*Reader),

    const Self = @This();

    const Error =
        FAT32.Error
        || NTFS.Error
        || Allocator.Error
        || std.fs.File.ReadError
        || std.fs.File.OpenError
        || std.posix.MMapError
        || error{ NoFilesystemMatch };

    pub fn init(alloc: Allocator, filepath: []const u8) Error!Self {
        return .{
            .alloc = alloc,
            .path = try alloc.dupe(u8, filepath),
            ._files = std.ArrayList(*std.fs.File).init(alloc),
            ._readers = std.ArrayList(*Reader).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.path);
        for (self._readers.items) |r| {
            r.deinit();
            self.alloc.destroy(r);
        }
        self._readers.deinit();
        for (self._files.items) |f| {
            self.alloc.destroy(f);
        }
        self._files.deinit();
        self.* = undefined;
    }

    pub fn update_path(self: *Self, new_path: []const u8) Allocator.Error!void {
        self.alloc.free(self.path);
        self.path = try self.alloc.dupe(u8, new_path);
    }

    pub const Filesystem = union(enum) {
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

        pub fn name(self: Filesystem) [:0]const u8 {
            return @tagName(self);
        }

        pub fn calc_size(self: Filesystem) usize {
            return switch (self) {
                .fat32 => |*fat32| fat32.calc_size(),
                else => unreachable,
            };
        }

    };

    /// Caller must call deinit on the resulting Filesystem
    pub fn determine_filesystem(self: *Self) Error!Filesystem {
        const buf = try self.alloc.alloc(u8, 10000);

        if (FAT32.init(self.alloc, buf, try self.create_new_reader())) |fat32| return .{ .fat32 = fat32 } else |_| {}
        if (NTFS.init(self.alloc, buf, try self.create_new_reader())) |ntfs| return .{ .ntfs = ntfs } else |_| {}

        self.alloc.free(buf);
        return Error.NoFilesystemMatch;
    }

    pub fn create_new_reader(self: *Self) Error!*Reader {
        const f = try self.alloc.create(std.fs.File);
        errdefer self.alloc.destroy(f);
        f.* = try std.fs.cwd().openFile(self.path, .{});
        try self._files.append(f);

        const custom_reader = try self.alloc.create(Reader);
        errdefer self.alloc.destroy(custom_reader);
        custom_reader.* = try Reader.init(f);
        try self._readers.append(custom_reader);
        return custom_reader;
    }
};

const testing = std.testing;
const t_alloc = testing.allocator;
const assert = std.debug.assert;
const FAT32_PATH = "./filesystems/fat32_filesystem.img";
const log = std.log;

fn custom_slice_and_int_eql(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    inline for (@typeInfo(T).Struct.fields) |field_info| {
        const f_name = field_info.name;
        const f_a = @field(a, f_name);
        const f_b = @field(b, f_name);
        const f_info = @typeInfo(@TypeOf(f_a));
        // std.debug.print("type tag: {s}\n", .{@tagName(f_info)});
        // @compileLog("type tag: " ++ @tagName(f_info));

        switch (f_info) {
            .Pointer => {
                if (!std.mem.eql(u8, f_a, f_b)) {
                    std.debug.print("a: {any} and b: {any} dont match on {s}\n", .{f_a, f_b, f_name});
                    return false;
                }
            },
            .Int => {
                if (f_a != f_b) {
                    std.debug.print("a: {any} and b: {any} dont match on {s}\n", .{f_a, f_b, f_name});
                    return false;
                }
            },
            else => unreachable
        }
    }
    return true;
}

test "create new reader cleans up everything when somethings goes wrong (file access err)" {
    var fs_handler = try FilesystemHandler.init(t_alloc, "this path doesnt exist");
    defer fs_handler.deinit();
    try testing.expectError(error.FileNotFound, fs_handler.create_new_reader());
    try fs_handler.update_path(FAT32_PATH);

}
