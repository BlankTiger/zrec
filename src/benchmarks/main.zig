const std = @import("std");
const read_vs_mmap = @import("read_vs_mmap.zig");

test {
    std.testing.refAllDecls(read_vs_mmap);
}
