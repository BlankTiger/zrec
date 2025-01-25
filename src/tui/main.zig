const std = @import("std");
const log = std.log.scoped(.tui_main);
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const lib = @import("zrec");
const Reader = lib.Reader;
const JPEGRecoverer = lib.JPG;
const FilesystemHandler = lib.FilesystemHandler;

pub fn main() !void {
    // var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa_state.deinit();
    // const gpa = gpa_state.allocator();

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    defer std.process.argsFree(arena, args);
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
            const bkp_bpb = fat32.get_backup_bios_parameter_block();
            const bkp_bs = try fat32.get_backup_boot_sector();
            log.debug("fat32 filesystem found", .{});
            log.debug("jmp_boot: {X}", .{fat32.boot_sector.jmp_boot});
            log.debug("bytes_per_sector: {d}", .{fat32.bios_parameter_block.bytes_per_sector});
            log.debug("sectors_per_cluster: {d}", .{fat32.bios_parameter_block.sectors_per_cluster});
            log.debug("fat_size: {d}", .{fat32.bios_parameter_block.fat_size_32});
            log.debug("fat_offset for cluster 0: {d}", .{0 * 4});
            log.debug("fat 0 sector num: {d}", .{fat32.bios_parameter_block.reserved_sector_count + (0 / fat32.bios_parameter_block.bytes_per_sector)});
            log.debug("fat entry offset: {d}", .{try std.math.rem(u16, 0*4, fat32.bios_parameter_block.bytes_per_sector)});

            log.debug("bkp jmp_boot: {X}", .{bkp_bs.jmp_boot});
            log.debug("bkp bytes_per_sector: {d}", .{bkp_bpb.bytes_per_sector});
            log.debug("bkp sectors_per_cluster: {d}", .{bkp_bpb.sectors_per_cluster});
            log.debug("below prints should have identical mem printed", .{});

            log.debug("some mem sector 0: {any}", .{fat32.buf[0..100]});
            log.debug("some mem sector 6: {any}", .{fat32.buf[6*512..6*512+100]});
            log.debug("eql = {any}", .{std.mem.eql(u8, fat32.buf[0..100], fat32.buf[6*512..6*512+100])});
        },
        .ntfs => |ntfs| {
            log.debug("ntfs filesystem found", .{});
            log.debug("some mem: {any}", .{ntfs.mem[0..100]});
        }
    }
}
