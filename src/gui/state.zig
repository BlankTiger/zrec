const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.app_state);

pub const AppState = struct {
    pub const Settings = struct {
        gpa: Allocator,
        width: c_int = 1200,
        height: c_int = 700,
        should_quit: bool = false,
        disk_image_path: ?[]u8 = null,
        path_retrieved: bool = true,
        pick_file_clicked: c_int = 0,
        was_pick_file_clicked: bool = false,
        mutex: std.Thread.Mutex = .{},
    };

    gpa: Allocator,
    width: c_int,
    height: c_int,
    should_quit: bool,
    disk_image_path: ?[]u8,
    path_retrieved: bool,
    pick_file_clicked: c_int,
    was_pick_file_clicked: bool,
    mutex: std.Thread.Mutex,

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
        if (self.disk_image_path) |ptr| {
            self.gpa.free(ptr);
        }
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
        log.debug("saved new path: {s}", .{p});
    }

    pub fn set_clicked(self: *AppState) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.was_pick_file_clicked = true;
    }

    pub fn set_unclicked(self: *AppState) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.was_pick_file_clicked = false;
    }
};
