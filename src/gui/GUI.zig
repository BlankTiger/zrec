const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.gui);

const config = @import("config");
const lib = @import("zrec");
const FilesystemHandler = lib.FilesystemHandler;
const Filesystem = lib.FilesystemHandler.Filesystem;
const Filetypes = lib.Filetypes;
const AppState = @import("AppState.zig");

const c = @cImport(@cInclude("SDL3/SDL.h"));
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raygui.h");
});

const GUI = @This();

gpa: Allocator,
frame_arena: Allocator,
frame_arena_state: *std.heap.ArenaAllocator,
state: *AppState,

fs_state: FsState,
path: ?[]u8 = null,
filename: ?[:0]u8 = null,

show_msg_box: bool = false,

scroll_index: c_int = 0,
active: bool = false,


const font_data = @embedFile("./resources/IosevkaNerdFontMono-Regular.ttf");
var font: r.Font = undefined;

const FsState = struct {
    gpa: Allocator,
    fs_handler: FilesystemHandler,
    fs: ?Filesystem = null,
    chosen_filetypes: CFTypeHashMap,

    const CFTypeHashMap = std.HashMap([:0]const u8, bool, CStringContext, std.hash_map.default_max_load_percentage);
    const CStringContext = struct {
        pub fn hash(self: @This(), s: [:0]const u8) u64 {
            _ = self;
            return std.hash_map.hashString(s);
        }

        pub fn eql(self: @This(), a: [:0]const u8, b: [:0]const u8) bool {
            _ = self;
            return std.hash_map.eqlString(a, b);
        }
    };

    const DType = [Filetypes.types.len]struct{[:0]const u8, bool};
    const data: DType = blk: {
        var d: DType = undefined;
        for (Filetypes.types, 0..) |t, idx| {
            d[idx] = .{ t, false };
        }
        break :blk d;
    };


    fn init(gpa: Allocator) !FsState {
        var ftypes = CFTypeHashMap.init(gpa);
        for (data) |kv| {
            try ftypes.put(kv[0], kv[1]);
        }
        return .{
            .gpa = gpa,
            .fs_handler = try FilesystemHandler.init(gpa, "invalid path currently"),
            .chosen_filetypes = ftypes,
        };
    }

    fn deinit(self: *FsState) void {
        self.fs_handler.deinit();
        self.chosen_filetypes.deinit();
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
    r.InitWindow(@intFromFloat(state.width), @intFromFloat(state.height), "zrec");
    r.SetTargetFPS(config.fps);
    // NOTE: font HAS TO BE loaded after InitWindow (wasted hours counter: 3)
    font = r.LoadFontFromMemory(".ttf", @ptrCast(font_data), font_data.len, 32, 0, 1000);
    ScreenStyles.set_style_initial_screen();

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
        self.state.width = @floatFromInt(r.GetScreenWidth());
        self.state.height = @floatFromInt(r.GetScreenHeight());
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

    if (self.state.pick_file_clicked.load(.monotonic)) {
        self.state.pick_file_clicked.store(false, .monotonic);
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

    if (self.state.recover_clicked.load(.monotonic)) {
        log.debug("huhhhh", .{});
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
    s.pick_file_clicked.store(false, .monotonic);
    const file = filelist[0];
    if (file == null) return;
    const path = file[0..std.mem.len(file)];
    log.debug("saved path", .{});
    s.save_path(path) catch @panic("huhh");
    log.debug("saved path", .{});
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

    ScreenStyles.set_style_for_image_analysed_screen();
}

fn draw(self: *GUI) !void {
    r.BeginDrawing();
    defer r.EndDrawing();
    defer r.ClearBackground(r.BLACK);

    if (self.path == null) {
        const msg = "Drop a disk image file";
        const pick_file_clicked = r.GuiButton(
            .{ .x = 10, .y = 10, .width = self.state.width - 20, .height = self.state.height - 20 },
            @ptrCast(msg[0..]),
        );
        if (pick_file_clicked == 1) self.state.pick_file_clicked.store(true, .monotonic);
    } else {
        self.draw_filename();
        try self.draw_fs_info();
        if (self.fs_state.fs) |_| {
            self.draw_filetype_recovery_list();
            self.draw_make_it_happen_btn();
        }
    }
}

const filename_y = 20;
var text_line_h: f32 = 0;

fn draw_filename(self: *const GUI) void {
    const txt_size = r.MeasureTextEx(font, self.filename.?, 32, 2);
    text_line_h = txt_size.y;
    const x = @max(0, self.state.width / 2 - txt_size.x / 2);
    r.DrawTextEx(font, self.filename.?, .{ .x = x, .y = 20, }, 32, 2, r.SKYBLUE);
}

fn draw_fs_info(self: *const GUI) !void {
    if (self.fs_state.fs) |fs| {
        const fs_type = try std.fmt.allocPrintZ(self.frame_arena, "filesystem: {s}", .{fs.name()});
        r.DrawTextEx(font, fs_type, .{ .x = 10, .y = filename_y + 2 * text_line_h, }, 32, 2, r.WHITE);
        const fs_size = try std.fmt.allocPrintZ(self.frame_arena, "size: {d} MB", .{fs.calc_size() / 1e6});
        r.DrawTextEx(font, fs_size, .{ .x = 10, .y = filename_y + 3 * text_line_h, }, 32, 2, r.WHITE);
    } else {
        const txt = "This file doesn't match any implemented filesystem";
        const txt_size = r.MeasureTextEx(font, txt, 32, 2);
        const x = self.state.width / 2 - txt_size.x / 2;
        r.DrawTextEx(font, txt, .{ .x = x, .y = filename_y + 2 * text_line_h, }, 32, 2, r.WHITE);
    }
}

var box_x: f32 = 0;
const box_x_offset: f32 = 450;
const box_width: f32 = box_x_offset - 50;
var box_y: f32 = 0;
const box_y_offset = 200;

fn draw_filetype_recovery_list(self: *GUI) void {
    if (self.fs_state.fs == null) return;

    // TODO: calculate the height based on the amount of choices, optionally turn this into a listview
    box_x = self.state.width - box_x_offset;
    box_y = text_line_h * 3;
    _ = r.GuiGroupBox(
        .{
            .x = box_x,
            .y = box_y,
            .width = box_width,
            .height = self.state.height - box_y_offset
        },
        "Choose filetypes to recover"
    );

    var k_iter = self.fs_state.chosen_filetypes.keyIterator();
    var idx: usize = 0;
    while (k_iter.next()) |k| : (idx += 1) {
        const value_ptr = self.fs_state.chosen_filetypes.getPtr(k.*).?;
        _ = r.GuiCheckBox(
            .{
                .x = box_x + 20,
                .y = box_y + text_line_h + @as(f32, @floatFromInt(idx)) * (1.2 * text_line_h),
                .width = text_line_h,
                .height = text_line_h
            },
            k.*, value_ptr
        );
    }
}

fn draw_make_it_happen_btn(self: *GUI) void {
    const width = 300;
    const y = box_y + self.state.height - box_y_offset + 25;
    const recover_clicked = r.GuiButton(
        .{ .x = box_x + box_width / 2 - width / 2, .y = y, .width = width, .height = 50 },
        "Make it happen",
    );
    if (recover_clicked == 1) self.state.recover_clicked.store(true, .monotonic);
}

const ScreenStyles = struct {
    fn set_style_initial_screen() void {
        r.GuiSetStyle(r.DEFAULT, r.TEXT_SIZE, 32);
        r.GuiSetFont(font);
        r.GuiSetFont(font);
        r.GuiSetStyle(r.BUTTON, r.TEXT_ALIGNMENT, r.TEXT_ALIGN_MIDDLE);
        r.GuiSetStyle(r.BUTTON, r.BORDER_WIDTH, 10);
        r.GuiSetStyle(r.BUTTON, r.BORDER_COLOR_PRESSED, r.ColorToInt(r.BLUE));
        r.GuiSetStyle(r.BUTTON, r.BASE_COLOR_NORMAL, r.ColorToInt(r.BLACK));
        r.GuiSetStyle(r.BUTTON, r.BASE_COLOR_FOCUSED, r.ColorToInt(r.BLACK));
        r.GuiSetStyle(r.BUTTON, r.BASE_COLOR_PRESSED, r.ColorToInt(r.BLACK));
    }

    fn set_style_for_image_analysed_screen() void {
        r.GuiSetStyle(r.BUTTON, r.BORDER_WIDTH, 2);
    }
};

