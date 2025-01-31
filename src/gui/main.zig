const std = @import("std");
const GUI = @import("GUI.zig");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var gui = try GUI.init(gpa);
    defer gui.deinit();
    try gui.run();
}
