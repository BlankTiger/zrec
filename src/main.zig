const std = @import("std");
const config = @import("config");
const gui = @import("gui/main.zig");
const tui = @import("tui/main.zig");

pub const std_options: std.Options = .{
    .log_level = switch (config.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    }
};

pub fn main() !void {
    switch (config.build_gui) {
        true => try gui.main(),
        false => try tui.main(),
    }
}
