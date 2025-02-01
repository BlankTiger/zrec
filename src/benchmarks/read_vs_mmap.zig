const std = @import("std");
const testing = std.testing;
const log = std.log.scoped(.read_vs_mmap);
const utils = @import("utils.zig");

const optimization_mode = @import("builtin").mode;

test "single core" {
    const prev_log_level = testing.log_level;
    testing.log_level = .info;
    defer testing.log_level = prev_log_level;
    const count = 10;
    const core_count = 1;

    const time_res_read = try utils.measure_time_and_mem(utils.run_read_reader, .{core_count}, count, true);
    while (!utils.results_saved.load(.monotonic)) {}
    const mem_res_read = utils.mem_measurements;

    const time_res_mmap = try utils.measure_time_and_mem(utils.run_mmap_reader, .{core_count}, count, true);
    while (!utils.results_saved.load(.monotonic)) {}
    const mem_res_mmap = utils.mem_measurements;

    log.info("optimization mode: {any}", .{optimization_mode});
    log.info("read (single core): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_read.avg / std.time.ns_per_s, time_res_read.std_dev / std.time.ns_per_s, mem_res_read.max, mem_res_read.avg});
    log.info("mmap (single core): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_mmap.avg / std.time.ns_per_s, time_res_mmap.std_dev / std.time.ns_per_s, mem_res_mmap.max, mem_res_mmap.avg});

    const values_a = try testing.allocator.alloc(f64, time_res_read.time.len);
    const values_b = try testing.allocator.alloc(f64, time_res_mmap.time.len);
    defer testing.allocator.free(values_a);
    defer testing.allocator.free(values_b);

    for (time_res_read.time, 0..) |_a, idx| {
        const a: f64 = @floatFromInt(_a);
        values_a[idx] = a / std.time.ns_per_s;
    }
    for (time_res_mmap.time, 0..) |_b, idx| {
        const b: f64 = @floatFromInt(_b);
        values_b[idx] = b / std.time.ns_per_s;
    }

    const t = utils.independent_t_test(f64, values_a, values_b);
    const p_value = utils.p_value_independent_t_test(f64, values_a, values_b, true);
    log.info("independent t-test t = {d}, p_value = {d}", .{t, p_value});
}

test "multi core" {
    const prev_log_level = testing.log_level;
    testing.log_level = .info;
    defer testing.log_level = prev_log_level;
    const count = 10;
    const core_count = try std.Thread.getCpuCount();

    const time_res_read = try utils.measure_time_and_mem(utils.run_read_reader, .{core_count}, count, true);
    while (!utils.results_saved.load(.monotonic)) {}
    const mem_res_read = utils.mem_measurements;

    const time_res_mmap = try utils.measure_time_and_mem(utils.run_mmap_reader, .{core_count}, count, true);
    while (!utils.results_saved.load(.monotonic)) {}
    const mem_res_mmap = utils.mem_measurements;

    const time_res_mmap_shared = try utils.measure_time_and_mem(utils.run_mmap_reader_shared, .{core_count}, count, true);
    while (!utils.results_saved.load(.monotonic)) {}
    const mem_res_mmap_shared = utils.mem_measurements;

    log.info("optimization mode: {any}", .{optimization_mode});
    log.info("read (multi core, {d} threads): avg={d}s, std_dev={d}s, max used mem={d} pages, avg used mem={d} pages", .{core_count, time_res_read.avg / std.time.ns_per_s, time_res_read.std_dev / std.time.ns_per_s, mem_res_read.max, mem_res_read.avg});
    log.info("mmap (multi core, {d} threads): avg={d}s, std_dev={d}s, max used mem={d} pages, avg used mem={d} pages", .{core_count, time_res_mmap.avg / std.time.ns_per_s, time_res_mmap.std_dev / std.time.ns_per_s, mem_res_mmap.max, mem_res_mmap.avg});
    log.info("mmap (multi core, {d} threads, mmap is shared): avg={d}s, std_dev={d}s, max used mem={d} pages, avg used mem={d} pages", .{core_count, time_res_mmap_shared.avg / std.time.ns_per_s, time_res_mmap_shared.std_dev / std.time.ns_per_s, mem_res_mmap_shared.max, mem_res_mmap_shared.avg});

    const values_a = try testing.allocator.alloc(f64, time_res_read.time.len);
    const values_b = try testing.allocator.alloc(f64, time_res_mmap.time.len);
    const values_c = try testing.allocator.alloc(f64, time_res_mmap_shared.time.len);
    defer testing.allocator.free(values_a);
    defer testing.allocator.free(values_b);
    defer testing.allocator.free(values_c);

    for (time_res_read.time, 0..) |_a, idx| {
        const a: f64 = @floatFromInt(_a);
        values_a[idx] = a / std.time.ns_per_s;
    }
    for (time_res_mmap.time, 0..) |_b, idx| {
        const b: f64 = @floatFromInt(_b);
        values_b[idx] = b / std.time.ns_per_s;
    }
    for (time_res_mmap_shared.time, 0..) |_c, idx| {
        const c: f64 = @floatFromInt(_c);
        values_c[idx] = c / std.time.ns_per_s;
    }

    const t_a_b = utils.independent_t_test(f64, values_a, values_b);
    const p_value_a_b = utils.p_value_independent_t_test(f64, values_a, values_b, true);
    const t_b_c = utils.independent_t_test(f64, values_b, values_c);
    const p_value_b_c = utils.p_value_independent_t_test(f64, values_b, values_c, true);
    log.info("independent t-test between read and mmap: t = {d}, p_value = {d}", .{t_a_b, p_value_a_b});
    log.info("independent t-test between mmap and mmap shared: t = {d}, p_value = {d}", .{t_b_c, p_value_b_c});
}
