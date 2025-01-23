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
            const avg = average(u64, &time);
            const stddev = std_dev(u64, &time);
            return .{
                .avg = avg,
                .std_dev = stddev,
                .time = time,
                .results = results,
            };
        }
    };
}

pub fn p_value_independent_t_test(T: type, values_a: []const T, values_b: []const T, two_tailed: bool) f64 {
    const t = independent_t_test(T, values_a, values_b);
    const df: f64 = @floatFromInt(values_a.len + values_b.len - 2);
    const cdf = t_cdf(@abs(t), df);
    return if (two_tailed) 2 * (1 - cdf) else 1 - cdf;
}

pub fn t_cdf(t: f64, df: f64) f64 {
    const x = df / (df + std.math.pow(f64, t, 2));
    const a = df / 2;
    const b = 0.5;
    return 1 - 0.5 * incomplete_beta(x, a, b);
}

pub fn incomplete_beta(x: f64, a: f64, b: f64) f64 {
    var sum: f64 = 1;
    var term: f64 = 1;
    for (1..100) |_k| {
        const k: f64 = @floatFromInt(_k);
        term *= x * (a + k - 1) / (k * (a + b + k - 1));
        sum += term;
        if (term < 1e-10) break;
    }
    return sum * std.math.pow(f64, x, a) * std.math.pow(f64, 1 - x, b) / (a * std.math.gamma(f64, a + b) / (std.math.gamma(f64, a) * std.math.gamma(f64, b)));
}

/// https://www.datanovia.com/en/lessons/t-test-formula/independent-t-test-formula/
pub fn independent_t_test(T: type, values_a: []const T, values_b: []const T) f64 {
    const avg_a = average(T, values_a);
    const avg_b = average(T, values_b);
    const s_squared = calc_s_squared(T, values_a, avg_a, values_b, avg_b);
    const len_a: f64 = @floatFromInt(values_a.len);
    const len_b: f64 = @floatFromInt(values_b.len);
    return (avg_a - avg_b) / @sqrt(s_squared / len_a + s_squared / len_b);
}

fn calc_s_squared(T: type, values_a: []const T, avg_a: f64, values_b: []const T, avg_b: f64) f64 {
    var sum_a: f64 = 0;
    var sum_b: f64 = 0;
    switch (@typeInfo(T)) {
        .Int => {
            for (values_a) |a| {
                const _a: f64 = @floatFromInt(a);
                sum_a += std.math.pow(f64, _a - avg_a, 2);
            }
            for (values_b) |b| {
                const _b: f64 = @floatFromInt(b);
                sum_b += std.math.pow(f64, _b - avg_b, 2);
            }
        },
        .Float => {
            for (values_a) |a| sum_a += std.math.pow(f64, a - avg_a, 2);
            for (values_b) |b| sum_b += std.math.pow(f64, b - avg_b, 2);
        },
        else => unreachable,
    }
    const len_a: f64 = @floatFromInt(values_a.len);
    const len_b: f64 = @floatFromInt(values_b.len);
    return (sum_a + sum_b) / (len_a + len_b - 2);
}

pub fn average(T: type, values: []const T) f64 {
    assert(values.len > 0);
    var sum: T = 0;
    for (values) |v| sum += v;
    const nom: f64 = switch (@typeInfo(T)) {
        .Int => @floatFromInt(sum),
        .Float => sum,
        else => unreachable,
    };
    const den: f64 = @floatFromInt(values.len);
    return nom / den;
}

pub fn std_dev(T: type, values: []const T) f64 {
    const avg = average(T, values);
    var sum: f64 = 0;
    switch (@typeInfo(T)) {
        .Int => { for (values) |v| sum += std.math.pow(f64, @as(f64, @floatFromInt(v)) - avg, 2); },
        .Float => { for (values) |v| sum += std.math.pow(f64, v - avg, 2); },
        else => unreachable,
    }
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
