const std = @import("std");

pub const Opts = struct {
    leading_newline: bool = false,
    arr_of_u8_as_str: bool = true,
    newline_after_fields: bool = true,
    nesting: usize = 0,
    first: bool = true,
    tabs: []const u8 = "\t",
};

const buf_size = 3000;

pub fn print(x: anytype) void {
    print_with_opts(x, null);
}

pub fn print_with_opts(x: anytype, options: ?*Opts) void {
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    print_with_writer(std.io.getStdErr().writer(), x, options);
}

fn print_with_writer(writer: anytype, x: anytype, options: ?*Opts) void {
    const opts = if (options) |o| o else o: { var _o: Opts = .{}; break :o &_o; };
    var buf: [buf_size]u8 = undefined;
    const nesting_depth = opts.nesting;
    const nesting_width = opts.tabs.len;
    if (opts.leading_newline) writer.print("\n", .{}) catch return;
    var last_nesting_idx: usize = 0;
    for (0..nesting_depth + 2) |nesting_depth_idx| {
        _ = std.fmt.bufPrint(buf[last_nesting_idx..], "{s}", .{opts.tabs}) catch return;
        last_nesting_idx = nesting_width * nesting_depth_idx;
    }
    const tabs = buf[0..last_nesting_idx - nesting_width];
    const tabs_next = buf[0..last_nesting_idx];
    const first = opts.first;
    if (first) opts.first = false;

    const T = @TypeOf(x);
    const t_info = @typeInfo(T);
    switch (t_info) {
        .@"struct" => |info| {
            const fs = info.fields;
            writer.print("{any}{{\n", .{T}) catch return;
            opts.nesting += 1;
            inline for (fs) |f| {
                writer.print("{s}.{s} = ", .{tabs_next, f.name}) catch return;
                print_with_writer(writer, @field(x, f.name), opts);
                writer.print(",", .{}) catch return;
                if (opts.newline_after_fields) writer.print("\n", .{}) catch return;
            }
            opts.nesting -= 1;
            writer.print("{s}}}", .{tabs}) catch return;
        },
        .type, .bool, .enum_literal, .@"opaque", .@"frame", .@"anyframe" => writer.print("{any}", .{x}) catch return,
        .void, .noreturn, .undefined, .null, .@"fn" => writer.print("{any}", .{x}) catch return,
        .int, .float, .comptime_float, .comptime_int => writer.print("{d}", .{x}) catch return,
        .pointer => |info| {
            switch (info.size) {
                .one => print_with_writer(writer, x.*, opts),
                .many, .c => writer.print("{any}", .{x}) catch return,
                .slice => {
                    if (info.child == u8 and opts.arr_of_u8_as_str) {
                        writer.print("\"{s}\"", .{x}) catch return;
                    } else {
                        writer.print("&[{d}]{any}{any}", .{x.len, info.child, x}) catch return;
                    }
                }
            }
        },
        .array => |info| {
            if (info.child == u8 and opts.arr_of_u8_as_str) {
                writer.print("\"{s}\"", .{x}) catch return;
            } else {
                writer.print("&[{d}]{any}{any}", .{x.len, info.child, x}) catch return;
            }
        },
        .optional => if (x == null) writer.print("{any}", .{x}) catch return else print_with_writer(writer, x.?, opts),
        .error_union => if (x) |not_err| print_with_writer(writer, not_err, opts) else |err| writer.print("{any}", .{err}) catch return,
        .error_set => writer.print("{any}", .{x}) catch return,
        .@"enum" => writer.print("{any}", .{x}) catch return,
        .@"union" => |info| {
            if (info.tag_type) |TagType| {
                const tag: TagType = x;
                inline for (info.fields) |f| {
                    const field_tag = @field(TagType, f.name);
                    if (field_tag == tag) {
                        writer.print("{any}{{\n{s}.{s} = ", .{T, tabs_next, f.name}) catch return;
                        opts.nesting += 1;
                        print_with_writer(writer, @field(x, f.name), opts);
                        if (opts.newline_after_fields) writer.print("\n", .{}) catch return;
                        writer.print("{s}}}", .{tabs}) catch return;
                        opts.nesting += 1;
                        break;
                    }
                }
            }
        },
        .vector => {},
    }
    if (first) {
        writer.print("\n", .{}) catch return;
    }
}

const t_utils = @import("testing_utils.zig");

test print {
    try t_utils.skip_slow_test();

    const E = enum { a, b, c, d };

    const C = struct {
        a3: usize,
        b3: []const u8,
    };

    const U = union(enum) {
        a3: f64,
        b3: []const u8,
    };

    const B = struct {
        a2: C,
        b2: U,
    };

    const A = struct {
        a: usize,
        b: E,
        c: []const u8,
        d: []const u16,
        e: f32,
        f: B,
    };

    const a: A = .{
        .a = 15,
        .b = .d,
        .c = "hello, world!",
        .d = &[_]u16 { 5, 6, 7, 8, 9 },
        .e = 0.5,
        .f = .{
            .a2 = .{
                .a3 = 0,
                .b3 = "elo",
            },
            .b2 = .{ .b3 = "simea" },
        }
    };
    const expected =
        \\printer.decltest.print.A{
        \\  .a = 15,
        \\  .b = printer.decltest.print.E.d,
        \\  .c = "hello, world!",
        \\  .d = &[5]u16{ 5, 6, 7, 8, 9 },
        \\  .e = 0.5,
        \\  .f = printer.decltest.print.B{
        \\    .a2 = printer.decltest.print.C{
        \\      .a3 = 0,
        \\      .b3 = "elo",
        \\    },
        \\    .b2 = printer.decltest.print.U{
        \\      .b3 = "simea"
        \\    },
        \\  },
        \\}
        \\
    ;

    const t = std.testing;
    var buf = std.ArrayList(u8).init(t.allocator);
    defer buf.deinit();
    const writer = buf.writer();
    var opts: Opts = .{
        .tabs = "  ",
    };
    print_with_writer(writer, a, &opts);
    try t.expectEqualStrings(expected, buf.items);
}
