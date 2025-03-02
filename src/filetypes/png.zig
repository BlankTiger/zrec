const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("../lib.zig");
const Reader = lib.Reader;
const log = std.log.scoped(.png);
const assert = std.debug.assert;

pub const PNGRecoverer = struct {
    pub const PNG = struct {
        data: []u8,
        alloc: Allocator,

        pub fn init(alloc: Allocator, data: []u8) PNG {
            return PNG {
                .data = data,
                .alloc = alloc,
            };
        }

        pub fn deinit(self: PNG) void {
            self.alloc.free(self.data);
        }

        pub fn write_to_file(self: PNG, path: []const u8) !void {
            const f = try std.fs.cwd().createFile(path, .{});
            defer f.close();
            try f.writer().writeAll(self.data);
        }
    };

    alloc: Allocator,
    reader: Reader,
    stride: usize = 512,
    max_size: usize = 20e6,
    debug: bool = false,

    const Self = @This();

    pub fn init(alloc: Allocator, reader: Reader) Self {
        return Self {
            .alloc = alloc,
            .reader = reader,
        };
    }

    pub fn deinit(self: Self) void {
        self.reader.deinit();
    }

    pub const START = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
    fn is_png_start(bytes: []const u8) bool {
        return std.mem.eql(u8, bytes, &START);
    }

    pub const END = "IEND";
    /// in reality END is 'IEND' + 4 bytes of len
    pub const END_len = END.len + 4;
    fn is_png_end(bytes: []const u8) bool {
        return std.mem.eql(u8, bytes, END);
    }

    pub fn find_next(self: *Self) !?PNG {
        const buf = try self.alloc.alloc(u8, self.stride);
        defer self.alloc.free(buf);
        var img_data = try self.alloc.alloc(u8, self.max_size);
        errdefer self.alloc.free(img_data);

        var png_mem_copied: usize = 0;
        var png_started = false;
        var idx_png_start: usize = 0;
        var idx_png_end: usize = 0;
        var embedded_png_count: usize = 0;
        var png_ends_found: usize = 0;

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
                // a png start or png end
                if (png_started and bytes_left < END_len and read_bytes < self.stride and is_png_end(buf[idx..idx + END.len])) {
                    png_ends_found += 1;
                    idx += END_len;
                    idx_png_end = idx;
                    break;
                } else if (bytes_left < START.len and read_bytes > START.len) {
                    if (self.debug) log.debug("going back by {d} bytes, next bytes should be {x}", .{bytes_left, buf[buf.len-bytes_left..]});
                    try self.reader.seek_by(-@as(i64, @intCast(bytes_left)));
                    break;
                }

                if (!png_started and is_png_start(buf[idx..idx + START.len])) {
                    idx_png_start = idx;
                    idx += START.len;
                    png_started = true;
                } else if (png_started and is_png_start(buf[idx..idx + START.len])) {
                    embedded_png_count += 1;
                    if (self.debug) log.debug("embedded_png_count: {d}", .{embedded_png_count});
                    idx += START.len;
                } else if (png_started and is_png_end(buf[idx..idx + END.len])) {
                    png_ends_found += 1;
                    if (self.debug) log.debug("embedded_png_count: {d}, ends_found: {d}", .{embedded_png_count, png_ends_found});
                    idx += END_len;
                    if (embedded_png_count < png_ends_found) {
                        idx_png_end = idx;
                        try self.reader.seek_by(-@as(i64, @intCast(read_bytes - idx_png_end)));
                        break;
                    }
                } else {
                    idx += 1;
                }
            }

            if (png_started and idx_png_end == 0) {
                const for_copy = buf[idx_png_start..buf.len - bytes_left];
                @memcpy(img_data[png_mem_copied..png_mem_copied + for_copy.len], for_copy);
                png_mem_copied += for_copy.len;
                // has to be reset for it to copy correct bytes on the next read
                idx_png_start = 0;
                if (self.debug) {
                    @memcpy(&bytes_left_buf, buf[buf.len-bytes_left..]);
                    log.debug("last copied bytes: {x}, left bytes: {x}", .{img_data[png_mem_copied-bytes_left..png_mem_copied], buf[buf.len-bytes_left..]});
                }
            } else if (png_started and idx_png_end != 0) {
                const for_copy = buf[idx_png_start..idx_png_end];
                @memcpy(img_data[png_mem_copied..png_mem_copied + for_copy.len], for_copy);
                png_mem_copied += for_copy.len;

                // free unused memory from the img_data buffer
                img_data = try self.alloc.realloc(img_data, png_mem_copied);
                return PNG.init(self.alloc, img_data);
            }
        }
        return null;
    }
};

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    const t = std.testing;
    const t_alloc = t.allocator;
    const FsHandler = lib.FilesystemHandler;
    const utils = @import("testing_utils.zig");
    const proj_t_utils = @import("../testing_utils.zig");
    const testing_fs_handler = utils.testing_fs_handler;
    const hash = utils.hash;
    const Hashes = utils.Hashes;
    const cleanup_hashes = utils.cleanup_hashes;
    const testing_original_data = utils.testing_original_data;
    const END = PNGRecoverer.END;
    const START = PNGRecoverer.START;
    const tlog = std.log.scoped(.png_tests);

    const TestExample = enum {
        @"input/pngs/example1.png",
        @"input/pngs/example2.png",
        @"input/pngs/example3.png",
        @"input/pngs/example4.png",

        const paths = p: {
            const self_type_info = @typeInfo(TestExample).@"enum";
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
                const data = try testing_original_data(p);
                defer t_alloc.free(data);
                const hash_ptr = try hash(data);
                try hs.put(hash_ptr, {});
            }
            return hs;
        }
    };

    test "pngs read straight from the disk are interpreted via reader as the same imgs" {
        try proj_t_utils.skip_slow_test();

        inline for (TestExample.paths) |p| {
            tlog.debug("file: {s}", .{p});
            var orig_mem_data: []u8 = undefined;
            defer t_alloc.free(orig_mem_data);
            {
                const f = try std.fs.cwd().openFile(p, .{});
                defer f.close();
                orig_mem_data = try f.readToEndAlloc(t_alloc, 20e6);
                tlog.debug("orig_mem_data_len: {d}", .{orig_mem_data.len});
            }
            {
                const f = try std.fs.cwd().openFile(p, .{});
                const reader = try Reader.init(&f);
                var png_r = PNGRecoverer.init(t_alloc, reader);
                defer png_r.deinit();
                var png = (try png_r.find_next()).?;
                tlog.debug("recovered_data_len: {d}", .{png.data.len});
                defer png.deinit();

                tlog.debug("a end: {s}, b end: {s}", .{orig_mem_data[orig_mem_data.len-END.len..], png.data[png.data.len-END.len..]});
                try t.expectEqualSlices(u8, orig_mem_data, png.data);
            }
        }
    }

    test "recovered pngs have correct start and end bytes" {
        try proj_t_utils.skip_slow_test();

        var fs_handler = try testing_fs_handler();
        defer fs_handler.deinit();
        const reader = try fs_handler.create_new_reader();
        var png_r = PNGRecoverer.init(t_alloc, reader);
        const png = (try png_r.find_next()).?;
        defer png.deinit();

        try t.expectEqualSlices(u8, png.data[0..START.len], &START);
        try t.expectEqualSlices(u8, png.data[png.data.len-PNGRecoverer.END_len..png.data.len-4], PNGRecoverer.END);
    }

    test "recover png from fat32, verify using sha1" {
        try proj_t_utils.skip_slow_test();

        var hashes = try TestExample.hashes();
        defer cleanup_hashes(&hashes);
        var fs_handler = try testing_fs_handler();
        defer fs_handler.deinit();

        const reader = try fs_handler.create_new_reader();
        var png_r = PNGRecoverer.init(t_alloc, reader);

        const output_paths = utils.calc_output_paths(TestExample.paths.len, TestExample.paths);

        for (output_paths) |op| {
            const png = (try png_r.find_next()).?;
            defer png.deinit();
            if (t.log_level == .debug) try png.write_to_file(op);
            const h = try hash(png.data);
            defer t_alloc.free(h);

            t.expect(hashes.contains(h)) catch |err| {
                tlog.err("file {s} has incorrect hash: {x}", .{op, h});
                return err;
            };
        }
    }
};
