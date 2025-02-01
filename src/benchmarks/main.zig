const std = @import("std");
const read_vs_mmap = @import("read_vs_mmap.zig");
const reader_buffer_size = @import("reader_buffer_size.zig");

test {
    std.testing.refAllDecls(read_vs_mmap);
    std.testing.refAllDecls(reader_buffer_size);
}
