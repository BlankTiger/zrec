const std = @import("std");
const lib = @import("../lib.zig");
const Reader = lib.Reader;
const Allocator = std.mem.Allocator;

alloc: Allocator,
reader: Reader,
buf: []u8,
mem: []u8,

const Self = @This();

pub const Error =
    Allocator.Error
    || std.fs.File.ReadError
    || error{ NotNTFS, InvalidJmpBoot, UnimplementedCurrently };

pub fn init(alloc: Allocator, reader: *Reader) Error!Self {
    _ = alloc;
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
    self.reader.deinit();
    self.* = undefined;
}

pub fn get_size(self: Self) f64 {
    _ = self;
    unreachable;
}

pub fn get_free_size(self: Self) f64 {
    _ = self;
    unreachable;
}
