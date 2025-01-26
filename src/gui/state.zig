const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.app_state);

pub const AppState = struct {
    gpa: Allocator,
    should_quit: bool = false,
    disk_image_path: ?[]u8 = null,

    pub fn deinit(self: *AppState) void {
        if (self.disk_image_path) |ptr| {
            self.gpa.free(ptr);
        }
        self.* = undefined;
    }

    pub fn save_path(self: *AppState, p: []const u8) !void {
        if (self.disk_image_path) |ptr| {
            log.debug("freeing previous path: {s}", .{ptr});
            self.gpa.free(ptr);
        }
        self.disk_image_path = try self.gpa.dupe(u8, p);
        log.debug("saved new path: {s}", .{p});
    }
};
