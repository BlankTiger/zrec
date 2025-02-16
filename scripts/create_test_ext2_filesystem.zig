const std = @import("std");
const log = std.log.scoped(.create_ext2_filesystem);
const FsCreator = @import("FsCreator.zig");

pub fn main() !void {
    var arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer std.debug.assert(arena_state.reset(.free_all));
    const arena = arena_state.allocator();

    const creator: FsCreator = .init(.ext2, arena);
    try creator.prepare_workspace();
    try creator.truncate();
    try creator.mkfs();
    try creator.mount();
    try creator.copy_files();
    try creator.umount();
}
