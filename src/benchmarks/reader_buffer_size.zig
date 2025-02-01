const std = @import("std");
const testing = std.testing;
const log = std.log.scoped(.reader_buffer_size);
const utils = @import("utils.zig");

const optimization_mode = @import("builtin").mode;

test "512 bytes vs 1 kB vs 4 kB vs 512 kB vs 1024 kB" {
    const prev_log_level = testing.log_level;
    testing.log_level = .info;
    defer testing.log_level = prev_log_level;
    const count = 10;
    const core_count = 1;
    const orig_buf_size = utils.buf_size;
    defer utils.buf_size = orig_buf_size;

    log.info("optimization mode: {any}", .{optimization_mode});

    {
        utils.buf_size = 512;
        const time_res_read512 = try utils.measure_time_and_mem(utils.run_read_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_read512 = utils.mem_measurements;

        utils.buf_size = 1024;
        const time_res_read1kB = try utils.measure_time_and_mem(utils.run_read_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_read1kB = utils.mem_measurements;

        utils.buf_size = 4096;
        const time_res_read4kB = try utils.measure_time_and_mem(utils.run_read_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_read4kB = utils.mem_measurements;

        utils.buf_size = 8192;
        const time_res_read8kB = try utils.measure_time_and_mem(utils.run_read_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_read8kB = utils.mem_measurements;

        utils.buf_size = 512e3;
        const time_res_read512kB = try utils.measure_time_and_mem(utils.run_read_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_read512kB = utils.mem_measurements;

        utils.buf_size = 1024e3;
        const time_res_read1024kB = try utils.measure_time_and_mem(utils.run_read_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_read1024kB = utils.mem_measurements;

        utils.buf_size = 4096e3;
        const time_res_read4096kB = try utils.measure_time_and_mem(utils.run_read_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_read4096kB = utils.mem_measurements;

        log.info("read (single core, 512B): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_read512.avg / std.time.ns_per_s, time_res_read512.std_dev / std.time.ns_per_s, mem_res_read512.max, mem_res_read512.avg});
        log.info("read (single core, 1kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_read1kB.avg / std.time.ns_per_s, time_res_read1kB.std_dev / std.time.ns_per_s, mem_res_read1kB.max, mem_res_read1kB.avg});
        log.info("read (single core, 4kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_read4kB.avg / std.time.ns_per_s, time_res_read4kB.std_dev / std.time.ns_per_s, mem_res_read4kB.max, mem_res_read4kB.avg});
        log.info("read (single core, 8kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_read8kB.avg / std.time.ns_per_s, time_res_read8kB.std_dev / std.time.ns_per_s, mem_res_read8kB.max, mem_res_read8kB.avg});
        log.info("read (single core, 512kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_read512kB.avg / std.time.ns_per_s, time_res_read512kB.std_dev / std.time.ns_per_s, mem_res_read512kB.max, mem_res_read512kB.avg});
        log.info("read (single core, 1024kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_read1024kB.avg / std.time.ns_per_s, time_res_read1024kB.std_dev / std.time.ns_per_s, mem_res_read1024kB.max, mem_res_read1024kB.avg});
        log.info("read (single core, 4096kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_read4096kB.avg / std.time.ns_per_s, time_res_read4096kB.std_dev / std.time.ns_per_s, mem_res_read4096kB.max, mem_res_read4096kB.avg});
    }

    {
        utils.buf_size = 512;
        const time_res_mmap512 = try utils.measure_time_and_mem(utils.run_mmap_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_mmap512 = utils.mem_measurements;

        utils.buf_size = 1024;
        const time_res_mmap1kB = try utils.measure_time_and_mem(utils.run_mmap_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_mmap1kB = utils.mem_measurements;

        utils.buf_size = 4096;
        const time_res_mmap4kB = try utils.measure_time_and_mem(utils.run_mmap_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_mmap4kB = utils.mem_measurements;

        utils.buf_size = 8192;
        const time_res_mmap8kB = try utils.measure_time_and_mem(utils.run_mmap_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_mmap8kB = utils.mem_measurements;

        utils.buf_size = 512e3;
        const time_res_mmap512kB = try utils.measure_time_and_mem(utils.run_mmap_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_mmap512kB = utils.mem_measurements;

        utils.buf_size = 1024e3;
        const time_res_mmap1024kB = try utils.measure_time_and_mem(utils.run_mmap_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_mmap1024kB = utils.mem_measurements;

        utils.buf_size = 4096e3;
        const time_res_mmap4096kB = try utils.measure_time_and_mem(utils.run_mmap_reader, .{core_count}, count, true);
        while (!utils.results_saved.load(.monotonic)) {}
        const mem_res_mmap4096kB = utils.mem_measurements;

        log.info("mmap (single core, 512B): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_mmap512.avg / std.time.ns_per_s, time_res_mmap512.std_dev / std.time.ns_per_s, mem_res_mmap512.max, mem_res_mmap512.avg});
        log.info("mmap (single core, 1kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_mmap1kB.avg / std.time.ns_per_s, time_res_mmap1kB.std_dev / std.time.ns_per_s, mem_res_mmap1kB.max, mem_res_mmap1kB.avg});
        log.info("mmap (single core, 4kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_mmap4kB.avg / std.time.ns_per_s, time_res_mmap4kB.std_dev / std.time.ns_per_s, mem_res_mmap4kB.max, mem_res_mmap4kB.avg});
        log.info("mmap (single core, 8kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_mmap8kB.avg / std.time.ns_per_s, time_res_mmap8kB.std_dev / std.time.ns_per_s, mem_res_mmap8kB.max, mem_res_mmap8kB.avg});
        log.info("mmap (single core, 512kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_mmap512kB.avg / std.time.ns_per_s, time_res_mmap512kB.std_dev / std.time.ns_per_s, mem_res_mmap512kB.max, mem_res_mmap512kB.avg});
        log.info("mmap (single core, 1024kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_mmap1024kB.avg / std.time.ns_per_s, time_res_mmap1024kB.std_dev / std.time.ns_per_s, mem_res_mmap1024kB.max, mem_res_mmap1024kB.avg});
        log.info("mmap (single core, 4096kB): avg={d}s, std_dev={d}s, max mem used={d} pages, avg mem used={d} pages", .{time_res_mmap4096kB.avg / std.time.ns_per_s, time_res_mmap4096kB.std_dev / std.time.ns_per_s, mem_res_mmap4096kB.max, mem_res_mmap4096kB.avg});
    }
}
