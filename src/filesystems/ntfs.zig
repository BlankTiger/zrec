const std = @import("std");
const lib = @import("../lib.zig");
const Reader = lib.Reader;
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
        || error{ NotNTFS, InvalidJmpBoot, UnimplementedCurrently };

    pub fn init(alloc: Allocator, buf: []u8, reader: *Reader) Error!Self {
        _ = alloc;
        _ = buf;
        _ = reader;

        return error.UnimplementedCurrently;

        // const read = try reader.read(buf);
        // const mem = buf[0..read];
        //
        // return Self {
        //     .alloc = alloc,
        //     .reader = reader,
        //     .buf = buf,
        //     .mem = mem,
        // };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.buf);
        self.* = undefined;
    }
};
