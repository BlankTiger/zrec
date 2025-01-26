const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.app_state);

pub const AppState = struct {
    gpa: Allocator,
    should_quit: bool = false,
    disk_image_path: ?[]u8 = null,
    path_retrieved: bool = true,
    fps_buf: []u8,
    fps: []u8,
    fps_len: *usize,
    mutex: std.Thread.Mutex = .{},

    pub fn init(gpa: Allocator) !AppState {
        const fps_buf = try gpa.alloc(u8, 3);
        const res: AppState = .{ .gpa = gpa, .fps_buf = fps_buf, .fps = fps_buf, .fps_len = try gpa.create(usize) };
        res.fps_len.* = 3;
        return res;
    }

    pub fn deinit(self: *AppState) void {
        if (self.disk_image_path) |ptr| {
            self.gpa.free(ptr);
        }
        self.gpa.free(self.fps_buf);
        self.gpa.destroy(self.fps_len);
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

    pub fn update_fps(self: *AppState, fps: f64) !void {
        self.fps = try std.fmt.bufPrint(self.fps_buf, "{d}", .{@min(999, @round(fps))});
        self.fps_len.* = self.fps.len;
    }
};
