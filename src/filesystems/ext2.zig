const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("../lib.zig");
const Reader = lib.Reader;
const log = std.log.scoped(.ext2);
const set_fields_alignment_in_struct = lib.set_fields_alignment_in_struct;

pub const EXT2 = struct {
    /// 1024 bytes in size, in revision 0 at beginning of every block group.
    /// From revision 1 of EXT2 they can be placed sparsely every other block.
    pub const Superblock = set_fields_alignment_in_struct(_Superblock, 1);
    const _Superblock = extern struct {
        inodes_count: u32,
        blocks_count: u32,
    };

    pub const Error =
        Allocator.Error
        || std.fs.File.ReadError
        || error{
            NotEXT2,
            FileTooSmall,
            UnimplementedCurrently,
        };
    const Self = @This();

    gpa: Allocator,
    reader: *Reader,

    pub fn init(gpa: Allocator, reader: *Reader) Error!Self {
        if (true) return error.UnimplementedCurrently;
        return .{
            .gpa = gpa,
            .reader = reader,
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }

    pub fn calc_size(self: Self) f64 {
        _ = self;
        return 0;
    }
};

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    const FilesystemHandler = lib.FilesystemHandler;
    const EXT2_PATH = "./filesystems/ext2_filesystem.img";
    const t = std.testing;
    const t_alloc = t.allocator;
    const tlog = std.log.scoped(.ext2_tests);

    test "has superblock at offset 1K" {
    }
};
