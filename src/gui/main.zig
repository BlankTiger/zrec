const std = @import("std");
const config = @import("config");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.gui_main);
const e = @import("elements.zig");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

var FPS: u32 = config.fps;
var SHOULD_QUIT = false;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const SCREEN_TICKS_PER_FRAME = 1000.0 / @as(f64, @floatFromInt(FPS));

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        return;
    }

    const window = c.SDL_CreateWindow("zrec", 600, 400, c.SDL_WINDOW_RESIZABLE) orelse {
        log.err("something went wrong with the window init", .{});
        return;
    };
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, undefined) orelse {
        log.err("something went wrong with the renderer init", .{});
        return;
    };
    defer c.SDL_DestroyRenderer(renderer);

    if (!c.TTF_Init()) {
        log.err("something went wrong with the TTF init", .{});
        return;
    }
    defer c.TTF_Quit();

    var gui = try GUI.init(gpa, renderer);
    defer gui.deinit();

    var avg_fps: f64 = 0;

    while (!SHOULD_QUIT) {
        const start_tick = c.SDL_GetTicks();

        try update(&gui);
        try draw(renderer, window, gui);

        const end_tick = c.SDL_GetTicks();
        const delta: f64 = @floatFromInt(end_tick - start_tick);
        const den: f64 = SCREEN_TICKS_PER_FRAME - delta;
        if (den != 0) {
            avg_fps = 1000.0 / den;
            if (delta < SCREEN_TICKS_PER_FRAME) c.SDL_Delay(@intFromFloat(den));
            // log.debug("fps: {d}", .{@round(avg_fps)});
        }
    }
}

const GUI = struct {
    a: Allocator,
    r: *c.SDL_Renderer,
    font: *c.TTF_Font,
    elements: []e.Element,

    pub fn init(a: Allocator, r: *c.SDL_Renderer) !GUI {
        const f = c.TTF_OpenFont("./resources/IosevkaNerdFontMono-Regular.ttf", 36).?;
        const _elements = [_]e.Element {
            .{ .button = start_btn(r, f) },
            .{ .button = end_btn(r, f) },
        };
        const elements = try a.dupe(e.Element, &_elements);
        return .{
            .a = a,
            .r = r,
            .font = f,
            .elements = elements,
        };
    }

    pub fn deinit(self: GUI) void {
        for (self.elements) |b| b.deinit();
        c.TTF_CloseFont(self.font);
        self.a.free(self.elements);
    }

    fn start_btn(r: *c.SDL_Renderer, f: *c.TTF_Font) e.Button {
        return e.Button.init(
            r,
            f,
            .{ .x = 50, .y = 50, .w = 100, .h = 40 },
            "Start",
            .{ .r = 240, .g = 240, .b = 240, .a = 255 },
            .{ .r = 50, .g = 50, .b = 50, .a = 255 },
            .{ .r = 0, .g = 125, .b = 125, .a = 255 },
            e.Button.start_btn_action,
        );
    }

    fn end_btn(r: *c.SDL_Renderer, f: *c.TTF_Font) e.Button {
        return e.Button.init(
            r,
            f,
            .{ .x = 450, .y = 50, .w = 100, .h = 40 },
            "End",
            .{ .r = 240, .g = 240, .b = 240, .a = 255 },
            .{ .r = 50, .g = 50, .b = 50, .a = 255 },
            .{ .r = 0, .g = 125, .b = 125, .a = 255 },
            e.Button.start_btn_action,
        );
    }
};


fn update(gui: *GUI) !void {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event)) {
        switch (event.type) {
            c.SDL_EVENT_QUIT => {
                SHOULD_QUIT = true;
                return;
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                const p: c.SDL_FPoint = .{ .x = event.button.x, .y = event.button.y };
                for (gui.elements) |*el| {
                    if (el.* == .button) {
                        var b = &el.button;
                        if (c.SDL_PointInRectFloat(&p, &b.rect)) {
                            try b.click();
                        }
                    }
                }
            },
            else => {},
        }
    }
    for (gui.elements) |*el| el.update();
}

fn draw(r: *c.SDL_Renderer, w: *c.SDL_Window, gui: GUI) !void {
    _ = c.SDL_SetRenderDrawColor(r, 0, 0, 0, 255);
    _ = c.SDL_RenderClear(r);

    for (gui.elements) |*b| b.draw();

    _ = c.SDL_RenderPresent(r);
    _ = c.SDL_UpdateWindowSurface(w);
}
