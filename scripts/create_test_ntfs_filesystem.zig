const std = @import("std");
const log = std.log.scoped(.create_ntfs_filesystem);
const FsCreator = @import("FsCreator.zig");

pub fn main() !void {
    var arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer std.debug.assert(arena_state.reset(.free_all));
    const arena = arena_state.allocator();

    const creator: FsCreator = .init(.ntfs, arena);
    try creator.prepare_workspace();
    try creator.truncate();
    _ = try std.process.Child.run(
        .{
            .allocator = arena,
            .cwd_dir = creator.cwd,
            .argv = &.{
                "dd",
                "if=/dev/zero",
                try std.fmt.allocPrint(arena, "of={s}", .{creator.path}),
                "count=409600",
            }
        }
    );
    try creator.mkfs();
}
