const std = @import("std");
const testing = std.testing;
const lib = @import("zrec");
const reader = lib.reader;
const log = std.log.scoped(.read_vs_mmap);
const utils = @import("utils.zig");

const path = "filesystems/fat32_filesystem.img";

fn run_read_reader(core_count: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const threads = try alloc.alloc(std.Thread, core_count);
    for (0..core_count) |idx| {
        threads[idx] = try std.Thread.spawn(.{}, inner_read_reader, .{});
    }
    for (threads) |t| t.join();
}

fn inner_read_reader() !void {
    var read_call_buf: [512]u8 = undefined;
    const f_read = try std.fs.cwd().openFile(path, .{});
    var reader_read = reader.Reader.init(&f_read);
    defer reader_read.deinit();
    var bytes_read_read = try reader_read.read(&read_call_buf);
    while (bytes_read_read > 0) {
        bytes_read_read = try reader_read.read(&read_call_buf);
    }
}

fn run_mmap_reader(core_count: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const threads = try alloc.alloc(std.Thread, core_count);
    for (0..core_count) |idx| {
        threads[idx] = try std.Thread.spawn(.{}, inner_mmap_reader, .{});
    }
    for (threads) |t| t.join();
}

fn inner_mmap_reader() !void {
    var mmap_cal_buf: [512]u8 = undefined;
    const f_mmap = try std.fs.cwd().openFile(path, .{});
    var reader_mmap = try reader.MmapReader.init(&f_mmap);
    defer reader_mmap.deinit();
    var bytes_read_mmap = try reader_mmap.read(&mmap_cal_buf);
    while (bytes_read_mmap > 0) {
        bytes_read_mmap = try reader_mmap.read(&mmap_cal_buf);
    }
}

fn run_mmap_reader_shared(core_count: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const f_mmap = try std.fs.cwd().openFile(path, .{});
    var reader_mmap = try reader.MmapReader.init(&f_mmap);
    defer reader_mmap.deinit();

    const threads = try alloc.alloc(std.Thread, core_count);
    for (0..core_count) |idx| {
        threads[idx] = try std.Thread.spawn(.{}, inner_mmap_reader_shared, .{reader_mmap.mem});
    }
    for (threads) |t| t.join();
}

fn inner_mmap_reader_shared(mem: []u8) !void {
    var mmap_cal_buf: [512]u8 = undefined;
    var reader_mmap = reader.MmapReader.init_with_mem(mem);
    var bytes_read_mmap = try reader_mmap.read(&mmap_cal_buf);
    while (bytes_read_mmap > 0) {
        bytes_read_mmap = try reader_mmap.read(&mmap_cal_buf);
    }
}

// TODO: make sure read values are correct, to make sure that benchmarks return
// values that mean anything
//
// TODO: add more statistics, check if difference in speed is statistically significant

const optimization_mode = @import("builtin").mode;

test "single core" {
    const prev_log_level = testing.log_level;
    testing.log_level = .info;
    defer testing.log_level = prev_log_level;
    const count = 50;
    const core_count = 1;
    const time_res_read = try utils.measure_avg_time(run_read_reader, .{core_count}, count, true);
    const time_res_mmap = try utils.measure_avg_time(run_mmap_reader, .{core_count}, count, true);
    log.info("optimization mode: {any}", .{optimization_mode});
    log.info("read (single core): avg={d} s, std_dev={d} s", .{time_res_read.avg / std.time.ns_per_s, time_res_read.std_dev / std.time.ns_per_s});
    log.info("mmap (single core): avg={d} s, std_dev={d} s", .{time_res_mmap.avg / std.time.ns_per_s, time_res_mmap.std_dev / std.time.ns_per_s});
}

test "multi core" {
    const prev_log_level = testing.log_level;
    testing.log_level = .info;
    defer testing.log_level = prev_log_level;
    const count = 10;
    const core_count = try std.Thread.getCpuCount();
    const time_res_read = try utils.measure_avg_time(run_read_reader, .{core_count}, count, true);
    const time_res_mmap = try utils.measure_avg_time(run_mmap_reader, .{core_count}, count, true);
    const time_res_mmap_shared = try utils.measure_avg_time(run_mmap_reader_shared, .{core_count}, count, true);
    log.info("optimization mode: {any}", .{optimization_mode});
    log.info("read (multi core, {d} threads): avg={d} s, std_dev={d} s", .{core_count, time_res_read.avg / std.time.ns_per_s, time_res_read.std_dev / std.time.ns_per_s});
    log.info("mmap (multi core, {d} threads): avg={d} s, std_dev={d} s", .{core_count, time_res_mmap.avg / std.time.ns_per_s, time_res_mmap.std_dev / std.time.ns_per_s});
    log.info("mmap (multi core, {d} threads, mmap is shared): avg={d} s, std_dev={d} s", .{core_count, time_res_mmap_shared.avg / std.time.ns_per_s, time_res_mmap_shared.std_dev / std.time.ns_per_s});
}
