const std = @import("std");
const FsHandler = @import("../filesystems.zig").FilesystemHandler;
const testing = std.testing;
const t_alloc = testing.allocator;
const _expect = testing.expect;
const log = std.log.scoped(.filetypes_testing_utils);
const assert = std.debug.assert;

pub fn testing_fs_handler() !FsHandler {
    const FAT32_PATH = "./filesystems/fat32_filesystem.img";
    return try FsHandler.init(t_alloc, FAT32_PATH);
}

pub fn testing_original_data(path: []const u8) ![]u8 {
    const original = try std.fs.cwd().openFile(path, .{});
    defer original.close();
    const original_data = try original.readToEndAlloc(t_alloc, 10e6);
    return original_data;
}

pub const Sha1 = std.crypto.hash.Sha1;
pub const Hashes = std.StringHashMap(void);

pub fn hash(data: []u8) ![]u8 {
    const hash_ptr = try t_alloc.alloc(u8, Sha1.digest_length);
    Sha1.hash(data, hash_ptr[0..Sha1.digest_length], .{});
    log.debug("hash: {x}", .{hash_ptr});
    return hash_ptr;
}

pub fn cleanup_hashes(h: *Hashes) void {
    var k_it = h.keyIterator();
    while (k_it.next()) |k| t_alloc.free(k.*);
    h.deinit();
}

pub fn dbg_eql(data_a: []const u8, data_b: []const u8, comptime path: []const u8) !void {
    log.debug("a_len: {d}, b_len: {d}", .{data_a.len, data_b.len});
    try expect(data_a.len == data_b.len, "length not equal for file: " ++ path);
    for (data_a, data_b, 0..) |a, b, idx| {
        if (a != b) {
            log.err("a and b dont match at {d}: {d} != {d}", .{idx, a, b});
            return expect(a != b, "byte not equal for file: " ++ path);
        }
    }
}

pub fn calc_output_paths(comptime len: usize, comptime input_paths: [len][]const u8) [len][]const u8 {
    comptime var output_paths: [len][]const u8 = undefined;
    comptime {
        for (input_paths, 0..) |p, idx| {
            var path_part: []const u8 = undefined;
            var path_iter = std.mem.splitSequence(u8, p, "/");
            assert(path_iter.next() != null);
            path_part = path_iter.next().?;
            const path = "output/" ++ path_part;
            output_paths[idx] = path;
        }
    }
    return output_paths;
}

pub fn expect(ok: bool, msg: []const u8) !void {
    if (!ok) {
        log.err("{s}", .{msg});
        return error.TestUnexpectedResult;
    }
}
