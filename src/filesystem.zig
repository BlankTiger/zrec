const std       = @import("std");
const Allocator = std.mem.Allocator;
const lib       = @import("lib.zig");
const Reader    = lib.Reader;
const FAT32     = @import("filesystems/FAT.zig");
const NTFS      = @import("filesystems/NTFS.zig");
const EXT2      = @import("filesystems/EXT2.zig");

pub const Filesystem = union(enum) {
    fat32: FAT32,
    ntfs:  NTFS,
    ext2:  EXT2,
    // ext3: EXT3,
    // ext4: EXT4,

    pub const Error = FAT32.Error || EXT2.Error || NTFS.Error;

    const FilesystemEnum = @typeInfo(Filesystem).@"union".tag_type.?;
    pub const EstimationResult = std.EnumMap(FilesystemEnum, f32);

    pub fn estimate(alloc: Allocator, reader: *Reader) EstimationResult {
        var res: EstimationResult = .initFull(0.0);
        inline for (@typeInfo(Filesystem).@"union".fields) |field| {
            const tag = @field(FilesystemEnum, field.name);
            res.put(tag, field.type.estimate(alloc, reader));
        }
        return res;
    }

    pub fn deinit(self: *Filesystem) void {
        switch (self.*) { inline else => |*it| it.deinit() }
        self.* = undefined;
    }

    pub fn name(self: Filesystem) [:0]const u8 {
        return @tagName(self);
    }

    /// Returns size of the filesystem in bytes.
    pub fn get_size(self: Filesystem) f64 {
        return switch (self) { inline else => |*it| it.get_size() };
    }

    /// Returns free size of the filesystem in bytes.
    pub fn get_free_size(self: Filesystem) f64 {
        return switch (self) { inline else => |*it| it.get_free_size() };
    }
};

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    const t_alloc = std.testing.allocator;
    const t = std.testing;

    const PATH = "./filesystems/ext2_filesystem.img";

    fn create_new_reader() !Reader {
        const f = try std.fs.cwd().openFile(PATH, .{});
        return try Reader.init(&f);
    }

    test "RUN estimation" {
        var reader = try create_new_reader();
        defer reader.deinit();
        const estimation = Filesystem.estimate(t_alloc, &reader);
        try t.expectEqual(0, estimation.get(.ext2));
        try t.expectEqual(0, estimation.get(.ntfs));
        try t.expectEqual(0, estimation.get(.fat32));
    }
};
