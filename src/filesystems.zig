const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = @import("reader.zig").Reader;
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
        || error{ NoFilesystemMatch };

    pub fn init(alloc: Allocator, filepath: []const u8) Error!Self {
        return Self {
            .alloc = alloc,
            .path = try alloc.dupe(u8, filepath),
            ._files = std.ArrayList(*std.fs.File).init(alloc),
            ._readers = std.ArrayList(*Reader).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.path);
        for (self._files.items) |f| {
            f.close();
            self.alloc.destroy(f);
        }
        self._files.deinit();
        for (self._readers.items) |r| self.alloc.destroy(r);
        self._readers.deinit();
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

    pub fn create_new_reader(self: *Self) Error!*Reader {
        const f = try self.alloc.create(std.fs.File);
        f.* = try std.fs.cwd().openFile(self.path, .{});
        try self._files.append(f);
        const r = f.reader();
        const br = try self.alloc.create(Reader);
        br.* = std.io.bufferedReader(r);
        try self._readers.append(br);
        return br;
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

// TODO: move this to fat.zig and make it more fat32 specific
test "fresh fat32 is read as expected with all backup info in sector 6" {
    var fs_handler = try FilesystemHandler.init(t_alloc, FAT32_PATH);
    defer fs_handler.deinit();
    var fs = try fs_handler.determine_filesystem();
    defer fs.deinit();

    switch (fs) {
        .fat32 => |fat32| {
            const bkp_bs = try fat32.get_backup_boot_sector();
            const bkp_bpb = fat32.get_backup_bios_parameter_block();
            assert(custom_slice_and_int_eql(fat32.boot_sector, bkp_bs));
            assert(custom_slice_and_int_eql(fat32.bios_parameter_block, bkp_bpb));
        },
        else => unreachable
    }
}
