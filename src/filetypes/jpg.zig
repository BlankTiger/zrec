const std = @import("std");
const log = std.log.scoped(.jpg);
const Allocator = std.mem.Allocator;
const Reader = @import("../lib.zig").Reader;
const assert = std.debug.assert;

pub const JPGRecoverer = struct {
    pub const JPEG = struct {
        alloc: Allocator,
        data: []u8,

        pub fn init(alloc: Allocator, data: []u8) JPEG {
            return .{
                .alloc = alloc,
                .data = data,
            };
        }

        pub fn deinit(self: JPEG) void {
            self.alloc.free(self.data);
        }

        pub fn write_to_file(self: JPEG, path: []const u8) !void {
            const f = try std.fs.cwd().createFile(path, .{});
            defer f.close();
            try f.writer().writeAll(self.data);
        }
    };

    alloc: Allocator,
    reader: *Reader,
    max_size: usize = 20e6,
    stride: usize = 512,
    debug: bool = false,

    const Self = @This();

    pub fn init(alloc: Allocator, reader: *Reader) Self {
        return Self {
            .alloc = alloc,
            .reader = reader,
        };
    }

    fn is_jpg_start(bytes: []const u8) bool {
        return std.mem.eql(u8, bytes, &[3]u8{ 0xff, 0xd8, 0xff });
    }

    fn is_jpg_end(bytes: []const u8) bool {
        return std.mem.eql(u8, bytes, &[2]u8{ 0xff, 0xd9 });
    }

    pub fn find_next(self: *Self) !?JPEG {
        const buf = try self.alloc.alloc(u8, self.stride);
        defer self.alloc.free(buf);
        var img_data = try self.alloc.alloc(u8, self.max_size);
        errdefer self.alloc.free(img_data);

        var jpg_mem_copied: usize = 0;
        var jpg_started = false;
        var idx_jpg_start: usize = 0;
        var idx_jpg_end: usize = 0;
        var embedded_jpeg_count: usize = 0;
        var jpg_ends_found: usize = 0;

        var read_bytes = try self.reader.read(buf);
        var bytes_left: usize = 0;
        var bytes_left_buf: [2]u8 = undefined;
        while (read_bytes > 0) : ({
            read_bytes = try self.reader.read(buf);
        }) {
            var idx: usize = 0;
            bytes_left = 0;
            while (idx < read_bytes) {
                bytes_left = read_bytes - idx;
                // ensure that the next read won't possibly miss
                // a jpg start or jpg end
                if (bytes_left < 3 and read_bytes < self.stride and is_jpg_end(buf[idx..idx + 2])) {
                    jpg_ends_found += 1;
                    idx += 2;
                    idx_jpg_end = idx;
                    break;
                } else if (bytes_left < 3 and read_bytes > 3) {
                    if (self.debug) log.debug("going back by {d} bytes, next bytes should be {x}", .{bytes_left, buf[buf.len-bytes_left..]});
                    try self.reader.seek_by(-@as(i64, @intCast(bytes_left)));
                    break;
                }

                if (!jpg_started and is_jpg_start(buf[idx..idx + 3])) {
                    idx_jpg_start = idx;
                    idx += 3;
                    jpg_started = true;
                } else if (jpg_started and is_jpg_start(buf[idx..idx + 3])) {
                    embedded_jpeg_count += 1;
                    if (self.debug) log.debug("embedded_jpeg_count: {d}", .{embedded_jpeg_count});
                    idx += 3;
                } else if (jpg_started and is_jpg_end(buf[idx..idx + 2])) {
                    jpg_ends_found += 1;
                    if (self.debug) log.debug("embedded_jpeg_count: {d}, ends_found: {d}", .{embedded_jpeg_count, jpg_ends_found});
                    idx += 2;
                    if (embedded_jpeg_count < jpg_ends_found) {
                        idx_jpg_end = idx;
                        try self.reader.seek_by(-@as(i64, @intCast(read_bytes - idx_jpg_end)));
                        break;
                    }
                } else {
                    idx += 1;
                }
            }

            if (jpg_started and idx_jpg_end == 0) {
                const for_copy = buf[idx_jpg_start..buf.len - bytes_left];
                @memcpy(img_data[jpg_mem_copied..jpg_mem_copied + for_copy.len], for_copy);
                jpg_mem_copied += for_copy.len;
                // has to be reset for it to copy correct bytes on the next read
                idx_jpg_start = 0;
                if (self.debug) {
                    @memcpy(&bytes_left_buf, buf[buf.len-bytes_left..]);
                    log.debug("last copied bytes: {x}, left bytes: {x}", .{img_data[jpg_mem_copied-bytes_left..jpg_mem_copied], buf[buf.len-bytes_left..]});
                }
            } else if (jpg_started and idx_jpg_end != 0) {
                const for_copy = buf[idx_jpg_start..idx_jpg_end];
                @memcpy(img_data[jpg_mem_copied..jpg_mem_copied + for_copy.len], for_copy);
                jpg_mem_copied += for_copy.len;

                // free unused memory from the img_data buffer
                img_data = try self.alloc.realloc(img_data, jpg_mem_copied);
                return JPEG.init(self.alloc, img_data);
            }
        }
        return null;
    }
};

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    const expect = std.testing.expect;
    const testing = std.testing;
    const t_alloc = testing.allocator;
    const FsHandler = @import("../filesystems.zig").FilesystemHandler;

    fn testing_fs_handler() !FsHandler {
        const FAT32_PATH = "./filesystems/fat32_filesystem.img";
        return try FsHandler.init(t_alloc, FAT32_PATH);
    }

    fn testing_original_jpg_data(path: []const u8) ![]u8 {
        const original_jpg = try std.fs.cwd().openFile(path, .{});
        defer original_jpg.close();
        const original_data = try original_jpg.readToEndAlloc(t_alloc, 10e6);
        return original_data;
    }

    const Sha1 = std.crypto.hash.Sha1;
    const Hashes = std.StringHashMap(void);

    fn hash(data: []u8) ![]u8 {
        const hash_ptr = try t_alloc.alloc(u8, Sha1.digest_length);
        Sha1.hash(data, hash_ptr[0..Sha1.digest_length], .{});
        log.debug("hash: {any}", .{hash_ptr});
        return hash_ptr;
    }

    const TestExample = enum {
        @"input/example1.jpg",
        @"input/example2.jpg",
        @"input/example3.jpg",
        @"input/example4.jpg",

        const paths = p: {
            const self_type_info = @typeInfo(TestExample).Enum;
            const len = self_type_info.fields.len;
            var ps: [len][]const u8 = undefined;
            for (self_type_info.fields, 0..) |f, idx| {
                ps[idx] = f.name;
                // @compileLog(std.fmt.comptimePrint("field_name: {s}\n", .{f.name}));
            }
            break :p ps;
        };

        fn hashes() !Hashes {
            var hs = Hashes.init(t_alloc);
            for (paths) |p| {
                const data = try testing_original_jpg_data(p);
                defer t_alloc.free(data);
                const hash_ptr = try hash(data);
                try hs.put(hash_ptr, {});
            }
            return hs;
        }

        fn cleanup_hashes(h: *Hashes) void {
            var k_it = h.keyIterator();
            while (k_it.next()) |k| t_alloc.free(k.*);
            h.deinit();
        }
    };

    fn dbg_eql(data_a: []const u8, data_b: []const u8) bool {
        log.debug("a_len: {d}, b_len: {d}", .{data_a.len, data_b.len});
        for (data_a, data_b, 0..) |a, b, idx| {
            if (a != b) {
                log.debug("a and b dont match at {d}: {d} != {d}", .{idx, a, b});
                return false;
            }
        }
        return true;
    }

    test "jpgs read straight from the disk are interpreted via reader as the same imgs" {
        for (TestExample.paths) |p| {
            log.debug("file: {s}", .{p});
            var orig_mem_data: []u8 = undefined;
            defer t_alloc.free(orig_mem_data);
            {
                const f = try std.fs.cwd().openFile(p, .{});
                defer f.close();
                orig_mem_data = try f.readToEndAlloc(t_alloc, 20e6);
                log.debug("orig_mem_data_len: {d}", .{orig_mem_data.len});
            }
            {
                const f = try std.fs.cwd().openFile(p, .{});
                defer f.close();
                var reader = Reader.init(&f);
                var jpg_r = JPGRecoverer.init(t_alloc, &reader);
                var jpg = (try jpg_r.find_next()).?;
                log.debug("recovered_data_len: {d}", .{jpg.data.len});
                defer jpg.deinit();

                try expect(dbg_eql(orig_mem_data, jpg.data));
            }
        }
    }

    test "recovered jpgs have correct start and end bytes" {
        var fs_handler = try testing_fs_handler();
        defer fs_handler.deinit();
        const reader = try fs_handler.create_new_reader();
        var jpg_r = JPGRecoverer.init(t_alloc, reader);
        const jpg = (try jpg_r.find_next()).?;
        defer jpg.deinit();
        try expect(std.mem.eql(u8, jpg.data[0..3], &[3]u8{ 0xff, 0xd8, 0xff }));
        try expect(std.mem.eql(u8, jpg.data[jpg.data.len-2..], &[2]u8{ 0xff, 0xd9 }));
    }

    test "recover jpg from fat32, verify using sha1" {
        var hashes = try TestExample.hashes();
        defer TestExample.cleanup_hashes(&hashes);
        var fs_handler = try testing_fs_handler();
        defer fs_handler.deinit();

        const reader = try fs_handler.create_new_reader();
        var jpg_r = JPGRecoverer.init(t_alloc, reader);

        var output_paths: [TestExample.paths.len][]const u8 = undefined;
        if (testing.log_level == .debug) {
            inline for (TestExample.paths, 0..) |p, idx| {
                comptime var path_part: []const u8 = undefined;
                comptime {
                    var path_iter = std.mem.splitSequence(u8, p, "/");
                    assert(path_iter.next() != null);
                    path_part = path_iter.next().?;
                }
                const path = "output/" ++ path_part;
                output_paths[idx] = path;
            }
        }

        for (output_paths) |op| {
            const jpg = (try jpg_r.find_next()).?;
            defer jpg.deinit();
            if (testing.log_level == .debug) try jpg.write_to_file(op);
            const h = try hash(jpg.data);
            defer t_alloc.free(h);

            try expect(hashes.contains(h));
        }
    }
};
