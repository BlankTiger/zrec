const std = @import("std");
const assert = std.debug.assert;
const Timer = std.time.Timer;

pub fn TimeResult(count: usize, RetType: ?type) type {
    const incl_ret_type = RetType != null;

    return struct {
        /// in nanoseconds
        avg: f64,
        /// in nanoseconds
        std_dev: f64,
        /// in nanoseconds
        time: [count]u64,
        results: if (incl_ret_type) [count]RetType.? else void,

        const Self = @This();

        pub fn init(time: [count]u64, results: if (incl_ret_type) [count]RetType.? else void) Self {
            const avg = average(&time);
            const stddev = std_dev(&time);
            return .{
                .avg = avg,
                .std_dev = stddev,
                .time = time,
                .results = results,
            };
        }
    };
}

pub fn average(values: []const u64) f64 {
    assert(values.len > 0);
    var sum: u64 = 0;
    for (values) |v| sum += v;
    const nom: f64 = @floatFromInt(sum);
    const den: f64 = @floatFromInt(values.len);
    return nom / den;
}

pub fn std_dev(values: []const u64) f64 {
    const avg = average(values);
    var sum: f64 = 0;
    for (values) |v| sum += std.math.pow(f64, @as(f64, @floatFromInt(v)) - avg, 2);
    const n: f64 = @floatFromInt(values.len);
    return @sqrt(sum / n);
}

pub fn measure_avg_time(comptime f: anytype, args: anytype, comptime count: usize, comptime with_res: bool) anyerror!TR: {
    const RetType = if (with_res) @typeInfo(@TypeOf(f)).Fn.return_type.? else null;
    break :TR TimeResult(count, RetType);
} {
    const RetType: ?type = if (with_res) @typeInfo(@TypeOf(f)).Fn.return_type.? else null;
    const TimeResultType = TimeResult(count, RetType);

    const ret_t_null = RetType == null;
    var arr_time: [count]u64 = undefined;
    var arr_res: if (!ret_t_null) [count]RetType.? else void = undefined;
    var timer = try Timer.start();
    for (0..count) |idx| {
        const res = @call(.auto, f, args);
        const t = timer.lap();
        if (!ret_t_null) arr_res[idx] = res;
        arr_time[idx] = t;
    }

    return TimeResultType.init(arr_time, arr_res);
}
