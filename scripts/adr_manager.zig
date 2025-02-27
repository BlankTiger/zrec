const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.adr_manager);

const ADR_PATH = "./docs/adr/";
const TEMPLATE_PATH = ADR_PATH ++ "0000-template.md";

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    defer std.process.argsFree(arena, args);

    if (args.len < 2) {
        show_help();
        return error.GiveCmdArgument;
    }
    const cmd = args[1];

    for (CMDs) |c| {
        if (!std.mem.eql(u8, cmd, c.name)) continue;
        const func_args = if (args.len > 2) args[2..] else &.{};
        try c.handler(arena, func_args);
    }
}

fn show_help() void {
    std.debug.print("{s}\n", .{HELP});
}

const CMD = struct {
    name:    []const u8,
    handler: *const fn(Allocator, []const [:0]u8) anyerror!void,
};

const CMDs: []const CMD = &.{
    .{ .name = "create", .handler = &create_ADR        },
    .{ .name = "list",   .handler = &list_ADRs         },
    .{ .name = "status", .handler = &update_ADR_status },
};

const HELP = h: {
    var h: []const u8 = "adr_manager\n\nAvailable commands are: ";
    const sep = ", ";
    for (CMDs) |cmd| {
        h = h ++ cmd.name ++ sep;
    }
    h = h[0..h.len - sep.len];
    break :h h;
};

/// first arg is the title of the adr
/// from second arg you can overwrite default values for template placeholders
/// by doing placeholder_name="value"
fn create_ADR(arena: Allocator, args: []const [:0]u8) !void {
    if (args.len < 1) return error.MissingAdrTitleArgument;

    const cwd = std.fs.cwd();
    const last_idx = i: {
        var dir_iter = (try cwd.openDir(ADR_PATH, .{ .iterate = true })).iterate();
        var max_idx: usize = 0;
        while (try dir_iter.next()) |e| {
            if (std.mem.eql(u8, e.name, "README.md")) continue;
            var name_iter = std.mem.splitScalar(u8, e.name, '-');
            const idx_part = name_iter.next().?;
            const idx = try std.fmt.parseInt(usize, idx_part, 10);
            max_idx = @max(max_idx, idx);
            // should for now always be 4 char long
            assert(idx_part.len == 4);
        }
        break :i max_idx;
    };
    const idx = last_idx + 1;

    const template_file = try cwd.openFile(TEMPLATE_PATH, .{});
    defer template_file.close();

    var template_reader = template_file.reader();
    const template = try template_reader.readAllAlloc(arena, 20e3);

    const title = args[0];
    const file_title = t: {
        const t = try arena.dupe(u8, title);
        _ = std.mem.replace(u8, title, " ", "_", t);
        for (t) |*c| c.* = std.ascii.toLower(c.*);
        break :t t;
    };

    var placeholders = try parse_placeholders(arena, args);

    const idx_text  = try std.fmt.allocPrint(arena, "{d:0>4}", .{idx});
    const title_key = "title";
    const idx_key   = "idx";
    const date_key  = "date";
    if (!placeholders.contains(title_key)) try placeholders.put(title_key, title);
    if (!placeholders.contains(idx_key))   try placeholders.put(idx_key, idx_text);
    if (!placeholders.contains(date_key))   try placeholders.put(date_key, try get_todays_date(arena));

    var p_iter = placeholders.iterator();
    var text = try arena.dupe(u8, template);
    while (p_iter.next()) |p| {
        const to_replace = try std.fmt.allocPrint(arena, "<{s}>", .{p.key_ptr.*});
        log.debug("{s} -> {s}", .{to_replace, p.value_ptr.*});
        const size = std.mem.replacementSize(u8, text, to_replace, p.value_ptr.*);
        const buf = try arena.alloc(u8, size);
        _ = std.mem.replace(u8, text, to_replace, p.value_ptr.*, buf);
        text = buf;
    }

    const path = try std.fmt.allocPrint(arena, "{s}{s}-{s}.md", .{ADR_PATH, idx_text, file_title});
    log.debug("Saving to: {s}", .{path});
    const output = try cwd.createFile(path, .{});
    var writer = output.writer();
    try writer.writeAll(text);
    defer output.close();
}

pub fn get_todays_date(allocator: std.mem.Allocator) ![]u8 {
    const timestamp = std.time.timestamp();

    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const epoch_day = epoch_seconds.getEpochDay();

    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const month = month_day.month.numeric();
    const day = month_day.day_index + 1;
    const year = year_day.year;

    return std.fmt.allocPrint(allocator, "{d:0>2}-{d:0>2}-{d:0>4}", .{ day, month, year });
}

fn parse_placeholders(alloc: Allocator, args: []const [:0]u8) !std.StringHashMap([]const u8) {
    var placeholders: std.StringHashMap([]const u8) = .init(alloc);
    errdefer placeholders.deinit();

    if (args.len > 1) for (args[1..]) |arg| {
        var key_val = std.mem.splitScalar(u8, arg, '=');
        try placeholders.put(key_val.next().?, key_val.next().?);
    };

    return placeholders;
}

fn list_ADRs(arena: Allocator, args: []const [:0]u8) !void {
    _ = arena;
    _ = args;
}

fn update_ADR_status(arena: Allocator, args: []const [:0]u8) !void {
    _ = arena;
    _ = args;
}
