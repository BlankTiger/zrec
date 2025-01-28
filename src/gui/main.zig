const std = @import("std");
const config = @import("config");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.gui_main);
const AppState = @import("state.zig").AppState;
const c = @cImport(@cInclude("SDL3/SDL.h"));
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raygui.h");
});

const font_data = @embedFile("./IosevkaNerdFontMono-Regular.ttf");
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
    path: ?[]u8 = null,
    show_msg_box: bool = false,

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
        };
    }

    pub fn deinit(self: *GUI) void {
        c.SDL_Quit();
        r.CloseWindow();
        self.state.deinit();
        self.gpa.destroy(self.state);
        self.frame_arena_state.deinit();
        self.gpa.destroy(self.frame_arena_state);
        if (self.path != null) self.gpa.free(self.path.?);
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

        if (self.path != null and !self.state.path_retrieved) self.gpa.free(self.path.?);
        if (!self.state.path_retrieved) self.path = try self.state.get_path();
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
            const txt: [:0]u8 = try self.frame_arena.allocSentinel(u8, self.path.?.len, 0);
            @memcpy(txt, self.path.?);
            const txt_size = r.MeasureTextEx(font, txt, 32, 2);
            const x = @max(0, @as(f32, @floatFromInt(@divFloor(self.state.width, @as(c_int, @intCast(2))))) - txt_size.x / 2);
            // const y = @as(f32, @floatFromInt(@divFloor(self.state.height, @as(c_int, @intCast(2))))) - txt_size.y / 2;
            r.DrawTextEx(
                font,
                txt,
                .{
                    .x = x,
                    .y = 20,
                },
                32,
                2,
                r.WHITE
            );
        }
    }
};
