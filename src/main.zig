const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const FilesystemHandler = @import("filesystem_handler.zig").FilesystemHandler;

fn is_jpeg(bytes: [3]u8) bool {
    return std.mem.eql(u8, bytes, &[3]u8{ 0xff, 0xd8, 0xff });
}

pub fn main() !void {
    // var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa_state.deinit();
    // const gpa = gpa_state.allocator();

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    assert(args.len > 1);
    const path = args[1];

    var fs_handler = try FilesystemHandler.init(arena, path);
    defer fs_handler.deinit();

    var fs = fs_handler.determine_filesystem() catch |err| {
        switch (err) {
            error.NoFilesystemMatch =>
                log.err("No filesystem matches image that was passed into the program", .{}),
            else => log.err("Unexpected err: {any}", .{err}),
        }
        return err;
    };
    defer fs.deinit();
    switch (fs) {
        .fat32 => |fat32| {
            log.debug("fat32 filesystem found", .{});
            log.debug("jmp_boot: {X}", .{fat32.boot_sector.jmp_boot});
            log.debug("bytes_per_sector: {d}", .{fat32.bios_parameter_block.bytes_per_sector});
            log.debug("sectors_per_cluster: {d}", .{fat32.bios_parameter_block.sectors_per_cluster});
        },
        .ntfs => |ntfs| {
            log.debug("ntfs filesystem found", .{});
            log.debug("some mem: {any}", .{ntfs.mem[0..100]});
        }
    }
}
