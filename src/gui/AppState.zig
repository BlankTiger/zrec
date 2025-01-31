const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.app_state);
pub const ABool = std.atomic.Value(bool);

pub const Settings = struct {
    gpa: Allocator,
    width: f32 = 1200,
    height: f32 = 700,
    should_quit: bool = false,
    disk_image_path: ?[]u8 = null,
    path_retrieved: bool = true,
    pick_file_clicked: ABool = ABool.init(false),
    recover_clicked: ABool = ABool.init(false),
    mutex: std.Thread.Mutex = .{},
};

gpa: Allocator,
width: f32,
height: f32,
should_quit: bool,
disk_image_path: ?[]u8,
path_retrieved: bool,
pick_file_clicked: ABool,
recover_clicked: ABool,
mutex: std.Thread.Mutex,

const AppState = @This();

pub fn init(opts: Settings) !AppState {
    var state: AppState = undefined;

    inline for (@typeInfo(AppState).Struct.fields) |f| {
        const f_name = f.name;
        const hidden = comptime std.mem.startsWith(u8, f_name, "_");
        if (hidden) continue;
        @field(state, f_name) = @field(opts, f_name);
    }

    return state;
}

pub fn deinit(self: *AppState) void {
    if (self.disk_image_path) |ptr| self.gpa.free(ptr);
    self.* = undefined;
}

/// caller should free the memory
pub fn get_path(self: *AppState) !?[]u8 {
    if (self.path_retrieved) return null;

    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.disk_image_path) |p| {
        self.path_retrieved = true;
        return try self.gpa.dupe(u8, p);
    }
    return null;
}

pub fn save_path(self: *AppState, p: []const u8) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.disk_image_path) |ptr| {
        log.debug("freeing previous path: {s}", .{ptr});
        self.gpa.free(ptr);
    }

    self.disk_image_path = try self.gpa.dupe(u8, p);
    self.path_retrieved = false;
    log.debug("saved new path: {s}", .{self.disk_image_path.?});
}
