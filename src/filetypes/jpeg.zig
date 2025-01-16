const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const Reader = @import("../lib.zig").Reader;

pub const JPEG = struct {
    _data: []u8,
    alloc: Allocator,
    end: usize,

    const Self = @This();

    pub fn init(alloc: Allocator, data: []u8, end: usize) Self {
        return Self{
            .alloc = alloc, ._data = data, .end = end,
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self._data);
        self.* = undefined;
    }

    pub fn get_data(self: Self) []u8 {
        return self._data[0..self.end];
    }

    fn is_jpeg(bytes: []const u8) bool {
        return std.mem.eql(u8, bytes, &[3]u8{ 0xff, 0xd8, 0xff });
    }

    fn ends_jpeg(bytes: []const u8) bool {
        return std.mem.eql(u8, bytes, &[2]u8{ 0xff, 0xd9 });
    }

    pub fn find_with_reader(alloc: Allocator, r: *Reader) !?Self {
        const buf = try alloc.alloc(u8, 512);
        defer alloc.free(buf);
        var jpg_found = false;
        var end_found = false;
        var sec_num: u32 = 0;
        var jpg_start_idx: usize = 0;
        var jpg_end_idx: usize = 0;
        var img_data = try alloc.alloc(u8, 20e6); // 10 MB max
        errdefer alloc.free(img_data);
        var img_data_offset: usize = 0;
        var img_data_end: usize = 0;
        while (try r.read(buf) == 512) : (sec_num += 1) {
            var w_iter = std.mem.window(u8, buf, 3, 1);
            var b_offset: u32 = 0;
            if (!jpg_found) {
                while (w_iter.next()) |w| : (b_offset += 1) {
                    if (is_jpeg(w)) {
                        log.info("JPGJPGJPGJPGJPG, sec_num: {d}, byte_offset: {d}", .{sec_num, b_offset});
                        jpg_found = true;
                        jpg_start_idx = 512*sec_num + b_offset;
                        @memcpy(img_data[0..512], buf);
                        img_data_offset = 1;
                        break;
                    }
                }
                continue;
            }

            w_iter = std.mem.window(u8, buf, 2, 1);
            if (!end_found) {
                while (w_iter.next()) |w| : (b_offset += 1) {
                    if (ends_jpeg(w)) {
                        log.info("ENDJPG, sec_num: {d}, byte_offset: {d}", .{sec_num, b_offset});
                        end_found = true;
                        jpg_end_idx = 512*sec_num + b_offset;
                        img_data_end = 512*img_data_offset + b_offset + 1;
                        break;
                    }
                }
                @memcpy(img_data[512*img_data_offset..512*(img_data_offset+1)], buf);
                img_data_offset += 1;
                continue;
            }
            break;
        }

        if (!jpg_found or !end_found) {
            alloc.free(img_data);
            return null;
        }

        return Self {
            ._data = img_data,
            .alloc = alloc,
            .end = img_data_end + 1,
        };
    }

    pub fn save_to_disk(self: Self, path: []const u8) !void {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll(self._data[0..self.end]);
    }

    pub fn find_n_with_reader(alloc: Allocator, r: *Reader, n: usize) !?[]Self {
        const jpgs = try alloc.alloc(Self, n);
        errdefer alloc.free(jpgs);
        var curr_jpg: usize = 0;

        const buf = try alloc.alloc(u8, 512);
        defer alloc.free(buf);
        var jpg_found = false;
        var end_found = false;
        var sec_num: u32 = 0;
        var jpg_start_idx: usize = 0;
        var jpg_end_idx: usize = 0;
        var img_data = try alloc.alloc(u8, 20e6); // 10 MB max
        errdefer alloc.free(img_data);
        var img_data_offset: usize = 0;
        var img_data_end: usize = 0;
        while (try r.read(buf) == 512) : (sec_num += 1) {
            var w_iter = std.mem.window(u8, buf, 3, 1);
            var b_offset: u32 = 0;
            if (!jpg_found) {
                while (w_iter.next()) |w| : (b_offset += 1) {
                    if (is_jpeg(w)) {
                        log.info("JPGJPGJPGJPGJPG, sec_num: {d}, byte_offset: {d}", .{sec_num, b_offset});
                        jpg_found = true;
                        jpg_start_idx = 512*sec_num + b_offset;
                        @memcpy(img_data[0..512], buf);
                        img_data_offset = 1;
                        break;
                    }
                }
                continue;
            }

            w_iter = std.mem.window(u8, buf, 2, 1);
            if (!end_found) {
                while (w_iter.next()) |w| : (b_offset += 1) {
                    if (ends_jpeg(w)) {
                        log.info("ENDJPG, sec_num: {d}, byte_offset: {d}", .{sec_num, b_offset});
                        end_found = true;
                        jpg_end_idx = 512*sec_num + b_offset;
                        img_data_end = 512*img_data_offset + b_offset + 1;
                        break;
                    }
                }
                @memcpy(img_data[512*img_data_offset..512*(img_data_offset+1)], buf);
                img_data_offset += 1;
                continue;
            } else {
                jpgs[curr_jpg] = Self {
                    ._data = img_data,
                    .alloc = alloc,
                    .end = img_data_end + 1,
                };
                curr_jpg += 1;
            }
            if (curr_jpg == n) break;
        }

        return jpgs;
    }
};

const assert = std.debug.assert;
const testing = std.testing;
const t_alloc = testing.allocator;
const FsHandler = @import("../filesystems.zig").FilesystemHandler;

fn testing_fs_handler() !FsHandler {
    const FAT32_PATH = "./filesystems/fat32_filesystem.img";
    return try FsHandler.init(t_alloc, FAT32_PATH);
}

fn testing_original_jpg_data() ![]u8 {
    const original_jpg = try std.fs.cwd().openFile("./input/example.jpg", .{});
    defer original_jpg.close();
    const original_data = try original_jpg.readToEndAlloc(t_alloc, 10e6);
    return original_data;
}

test "recover jpeg from fat32" {
    var fs_handler = try testing_fs_handler();
    defer fs_handler.deinit();
    const original_data = try testing_original_jpg_data();
    defer t_alloc.free(original_data);

    const reader = try fs_handler.create_new_reader();
    var jpg = (try JPEG.find_with_reader(t_alloc, reader)).?;
    defer jpg.deinit();
    const jpg_data = jpg.get_data();

    assert(std.mem.eql(u8, jpg_data, original_data));
}

test "recover n jpegs from fat32" {
    // try jpg.save_to_disk("recovered_from_ext4.jpg");
    // const jpgs = try JPEG.find_n_with_reader(t_alloc, reader, 200);
    // for (jpgs, 0..) |jpg, idx| try jpg.save_to_disk(try std.fmt.allocPrint(arena, "mnt/recovered_{d}.jpg", .{idx}));
}
