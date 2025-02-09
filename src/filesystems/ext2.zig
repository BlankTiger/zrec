const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("../lib.zig");
const Reader = lib.Reader;
const log = std.log.scoped(.ext2);

pub const EXT2 = struct {
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
};
