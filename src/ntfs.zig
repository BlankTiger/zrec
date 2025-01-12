const std = @import("std");
const Reader = @import("reader.zig").Reader;
const Allocator = std.mem.Allocator;

pub const NTFS = struct {
    alloc: Allocator,
    reader: *Reader,
    buf: []u8,
    mem: []u8,

    const Self = @This();

    pub const Error =
        Allocator.Error
        || std.fs.File.ReadError
        || error{ NotFAT32, InvalidJmpBoot };

    pub fn init(alloc: Allocator, reader: *Reader) Error!Self {
        const buf = try alloc.alloc(u8, 10_000);
        const read = try reader.read(buf);
        const mem = buf[0..read];

        return Self {
            .alloc = alloc,
            .reader = reader,
            .buf = buf,
            .mem = mem,
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.buf);
        self.* = undefined;
    }
};
