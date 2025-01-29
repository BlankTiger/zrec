const std = @import("std");
const config = @import("config");
const lib = @import("zrec");
const FilesystemHandler = lib.FilesystemHandler;
const Filesystem = lib.FilesystemHandler.Filesystem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.gui_main);
const AppState = @import("state.zig").AppState;
const c = @cImport(@cInclude("SDL3/SDL.h"));
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raygui.h");
});

const font_data = @embedFile("./resources/IosevkaNerdFontMono-Regular.ttf");
var font: r.Font = undefined;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var gui = try GUI.init(gpa);
    defer gui.deinit();
    try gui.run();
}


const GUI = struct {
    gpa: Allocator,
    frame_arena: Allocator,
    frame_arena_state: *std.heap.ArenaAllocator,
    state: *AppState,

    fs_state: FsState,
    path: ?[]u8 = null,
    filename: ?[:0]u8 = null,

    show_msg_box: bool = false,

    const FsState = struct {
        gpa: Allocator,
        fs_handler: FilesystemHandler,
        fs: ?Filesystem = null,

        fn init(gpa: Allocator) !FsState {
            return .{
                .gpa = gpa,
                .fs_handler = try FilesystemHandler.init(gpa, "invalid path currently"),
            };
        }

        fn deinit(self: *FsState) void {
            self.fs_handler.deinit();
            if (self.fs) |*fs| fs.deinit();
        }
    };

    pub fn init(gpa: Allocator) !GUI {
        const frame_arena_state = try gpa.create(std.heap.ArenaAllocator);
        frame_arena_state.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const frame_arena = frame_arena_state.allocator();
        const state = try gpa.create(AppState);
        state.* = try AppState.init(.{ .gpa = gpa });

        r.SetConfigFlags(r.FLAG_WINDOW_RESIZABLE);
        r.InitWindow(state.width, state.height, "zrec");
        // NOTE: font HAS TO BE loaded after InitWindow (wasted hours counter: 3)
        font = r.LoadFontFromMemory(".ttf", @ptrCast(font_data), font_data.len, 32, 0, 1000);
        r.SetTargetFPS(config.fps);
        r.GuiSetStyle(r.DEFAULT, r.TEXT_SIZE, 32);
        r.GuiSetFont(font);

        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
            log.err("couldnt init SDL", .{});
            return error.CouldntInitSDL;
        }

        return .{
            .gpa = gpa,
            .frame_arena = frame_arena,
            .frame_arena_state = frame_arena_state,
            .state = state,
            .fs_state = try FsState.init(gpa),
        };
    }

    pub fn deinit(self: *GUI) void {
        c.SDL_Quit();
        r.UnloadFont(font);
        r.CloseWindow();
        self.state.deinit();
        self.fs_state.deinit();
        self.gpa.destroy(self.state);
        self.frame_arena_state.deinit();
        self.gpa.destroy(self.frame_arena_state);
        if (self.path != null) self.gpa.free(self.path.?);
        if (self.filename != null) self.gpa.free(self.filename.?);
        self.* = undefined;
    }

    pub fn run(self: *GUI) !void {
        while (!r.WindowShouldClose()) {
            defer assert(self.frame_arena_state.reset(.free_all));

            try self.update();
            try self.draw();
        }
    }

    fn update(self: *GUI) !void {
        if (r.IsWindowResized()) {
            self.state.width = r.GetScreenWidth();
            self.state.height = r.GetScreenHeight();
        }

        if (r.IsFileDropped()) {
            const dropped_files = r.LoadDroppedFiles();
            defer r.UnloadDroppedFiles(dropped_files);
            log.debug("{any}", .{dropped_files});
            if (dropped_files.count != 1) return error.IncorrectNumberOfFilesDropped;
            const file = dropped_files.paths[0];
            if (file == null) return;
            const path = file[0..std.mem.len(file)];
            try self.state.save_path(path);
        }

        if (!self.state.was_pick_file_clicked and self.state.pick_file_clicked == 1) {
            self.state.set_clicked();
            c.SDL_ShowOpenFileDialog(
                &_file_dialog_callback,
                @as(*anyopaque, @ptrCast(self.state)),
                null,
                null,
                0,
                null,
                false
            );
        }

        if (!self.state.path_retrieved) try self.handle_file_chosen();
        // necessary to push the event loop forward because main loop doesn't
        // run all the prerequisites of SDL3 and we wouldn't receive the callback
        // to the file picker without this
        c.SDL_PumpEvents();
    }

    fn _file_dialog_callback(app_state: ?*anyopaque, filelist: [*c]const [*c]const u8, filter: c_int) callconv(.C) void {
        _ = filter;
        const s = @as(*AppState, @alignCast(@ptrCast(app_state)));
        s.set_unclicked();
        const file = filelist[0];
        if (file == null) return;
        const path = file[0..std.mem.len(file)];
        log.debug("saved path", .{});
        s.save_path(path) catch @panic("huhh");
        log.debug("saved path", .{});
    }

    fn draw(self: *GUI) !void {
        r.BeginDrawing();
        defer r.EndDrawing();
        defer r.ClearBackground(r.BLACK);

        if (self.path == null) {
            const msg = "Drop a disk image file";
            r.GuiSetFont(font);
            r.GuiSetStyle(r.BUTTON, r.TEXT_ALIGNMENT, r.TEXT_ALIGN_MIDDLE);
            r.GuiSetStyle(r.BUTTON, r.BORDER_WIDTH, 10);
            r.GuiSetStyle(r.BUTTON, r.BORDER_COLOR_PRESSED, r.ColorToInt(r.BLUE));
            r.GuiSetStyle(r.BUTTON, r.BASE_COLOR_NORMAL, r.ColorToInt(r.BLACK));
            r.GuiSetStyle(r.BUTTON, r.BASE_COLOR_FOCUSED, r.ColorToInt(r.BLACK));
            r.GuiSetStyle(r.BUTTON, r.BASE_COLOR_PRESSED, r.ColorToInt(r.BLACK));
            self.state.pick_file_clicked = r.GuiButton(
                .{ .x = 10, .y = 10, .width = @floatFromInt(self.state.width - 20), .height = @floatFromInt(self.state.height - 20) },
                @ptrCast(msg[0..]),
            );
        } else {
            self.draw_filename();
            try self.draw_fs_info();
        }
    }

    const filename_y = 20;
    var text_line_h: f32 = 0;

    fn draw_filename(self: GUI) void {
        const txt_size = r.MeasureTextEx(font, self.filename.?, 32, 2);
        text_line_h = txt_size.y;
        const x = @max(0, @as(f32, @floatFromInt(@divFloor(self.state.width, @as(c_int, @intCast(2))))) - txt_size.x / 2);
        r.DrawTextEx(font, self.filename.?, .{ .x = x, .y = 20, }, 32, 2, r.SKYBLUE);
    }

    fn draw_fs_info(self: GUI) !void {
        if (self.fs_state.fs) |fs| {
            const fs_type = try std.fmt.allocPrintZ(self.frame_arena, "filesystem: {s}", .{fs.name()});
            r.DrawTextEx(font, fs_type, .{ .x = 10, .y = filename_y + 2 * text_line_h, }, 32, 2, r.WHITE);
            const fs_size = try std.fmt.allocPrintZ(self.frame_arena, "size: {d} bytes", .{fs.calc_size()});
            r.DrawTextEx(font, fs_size, .{ .x = 10, .y = filename_y + 3 * text_line_h, }, 32, 2, r.WHITE);
        } else {
            r.DrawTextEx(font, "This file doesn't match any implemented filesystem", .{ .x = 10, .y = filename_y + 2 * text_line_h, }, 32, 2, r.WHITE);
        }
    }

    fn draw_filetype_recovery_list(self: GUI) void {
        if (!self.fs_state.fs) return;
        // TODO: start here, build the list of choices with toggles
        // const txt_size = r.MeasureTextEx(font, self.filename.?, 32, 2);
        // const fs_type = try std.fmt.allocPrintZ(self.frame_arena, "filesystem: {s}", .{fs.name()});
        // r.DrawTextEx(font, fs_type, .{ .x = 10, .y = filename_y + 2 * text_line_h, }, 32, 2, r.WHITE);
    }

    fn handle_file_chosen(self: *GUI) !void {
        if (self.path != null) self.gpa.free(self.path.?);
        if (self.filename != null) self.gpa.free(self.filename.?);
        if (self.fs_state.fs) |*fs| {
            fs.deinit();
            self.fs_state.fs = null;
        }

        self.path = try self.state.get_path();
        const p = self.path.?;

        var filename_len: usize = 0;
        var idx_filename_start: usize = 0;
        const idx_of_slash = std.mem.lastIndexOf(u8, p, "/");
        if (idx_of_slash == null) {
            filename_len = p.len;
            idx_filename_start = 0;
        } else {
            filename_len = p.len - idx_of_slash.? - 1;
            idx_filename_start = idx_of_slash.? + 1;
        }
        self.filename = try self.gpa.allocSentinel(u8, filename_len, 0);
        @memcpy(self.filename.?, p[idx_filename_start..]);

        try self.fs_state.fs_handler.update_path(p);
        log.debug("updated fs_handler file path to: {s}", .{p});
        const fs = self.fs_state.fs_handler.determine_filesystem() catch |err| {
            log.err("{any}", .{err});
            return;
        };
        self.fs_state.fs = fs;
    }
};
