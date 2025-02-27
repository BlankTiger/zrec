const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.adr_manager);

const TEMPLATE = @embedFile("../docs/adr/0000-template.md");

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
    assert(args.len > 1);
    const cmd = args[1];

    for (CMDs) |c| {
        if (!std.mem.eql(u8, cmd, c.name)) continue;
        try c.handler(arena);
    }
}

fn show_help() void {
    std.debug.print("{s}\n", .{HELP});
}

const CMD = struct {
    name:    []const u8,
    handler: *const fn(Allocator) anyerror!void,
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

// TODO: create those handlers
fn create_ADR(arena: Allocator) !void {
    _ = arena;
}

fn list_ADRs(arena: Allocator) !void {
    _ = arena;
}

fn update_ADR_status(arena: Allocator) !void {
    _ = arena;
}
