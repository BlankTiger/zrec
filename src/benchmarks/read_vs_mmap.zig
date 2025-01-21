const std = @import("std");
const testing = std.testing;
const lib = @import("../lib.zig");
const reader = lib.reader;
const log = std.log.scoped(.read_vs_mmap);

test {
    log.info("hello", .{});
}
