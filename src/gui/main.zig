const std = @import("std");
const config = @import("config");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.gui_main);
const e = @import("elements.zig");
const AppState = @import("state.zig").AppState;
const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

var FPS: u32 = config.fps;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        log.err("couldnt init SDL", .{});
        return;
    }
    defer c.SDL_Quit();

    if (!c.TTF_Init()) {
        log.err("something went wrong with the TTF init", .{});
        return;
    }
    defer c.TTF_Quit();

    const SCREEN_TICKS_PER_FRAME = 1000.0 / @as(f64, @floatFromInt(FPS));

    var gui = try GUI.init(gpa);
    defer gui.deinit();

    var avg_fps: f64 = 0;

    while (!gui.state.should_quit) {
        const start_tick = c.SDL_GetTicks();

        try gui.update();
        try gui.draw();

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
    w: *c.SDL_Window,
    state: AppState,
    font: *c.TTF_Font,
    elements: []e.Element,

    pub fn init(a: Allocator) !GUI {
        const w = c.SDL_CreateWindow("zrec", 1200, 800, c.SDL_WINDOW_RESIZABLE) orelse {
            log.err("something went wrong with the window init", .{});
            return error.CouldntCreateWindow;
        };
        const r = c.SDL_CreateRenderer(w, undefined) orelse {
            log.err("something went wrong with the renderer init", .{});
            return error.CouldntCreateRenderer;
        };

        const f = c.TTF_OpenFont("./resources/IosevkaNerdFontMono-Regular.ttf", 36).?;
        const _elements = [_]e.Element {
            .{ .button = GUIElements.start_btn(r, f) },
            .{ .button = GUIElements.end_btn(r, f) },
        };
        const elements = try a.dupe(e.Element, &_elements);
        return .{
            .a = a,
            .r = r,
            .w = w,
            .state = .{},
            .font = f,
            .elements = elements,
        };
    }

    pub fn deinit(self: *GUI) void {
        for (self.elements) |b| b.deinit();
        self.a.free(self.elements);
        c.TTF_CloseFont(self.font);
        c.SDL_DestroyWindow(self.w);
        c.SDL_DestroyRenderer(self.r);
        self.* = undefined;
    }

    fn update(self: *GUI) !void {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    self.state.should_quit = true;
                    return;
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    const p: c.SDL_FPoint = .{ .x = event.button.x, .y = event.button.y };
                    for (self.elements) |*el| {
                        if (el.* == .button) {
                            var b = &el.button;
                            if (c.SDL_PointInRectFloat(&p, &b.rect)) {
                                try b.click(&self.state);
                            }
                        }
                    }
                },
                else => {},
            }
        }
        for (self.elements) |*el| el.update();
    }

    fn draw(self: *const GUI) !void {
        _ = c.SDL_SetRenderDrawColor(self.r, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(self.r);

        for (self.elements) |*b| b.draw();

        _ = c.SDL_RenderPresent(self.r);
        _ = c.SDL_UpdateWindowSurface(self.w);
    }
};

const GUIElements = struct {
    const act_log = std.log.scoped(.action);

    fn start_btn(r: *c.SDL_Renderer, f: *c.TTF_Font) e.Button {
        return e.Button.init(
            r,
            f,
            .{ .x = 50, .y = 50, .w = 100, .h = 40 },
            "Start",
            .{ .r = 240, .g = 240, .b = 240, .a = 255 },
            .{ .r = 50, .g = 50, .b = 50, .a = 255 },
            .{ .r = 0, .g = 125, .b = 125, .a = 255 },
            struct {
                fn a(self: *e.Button, _: *AppState) !void {
                    act_log.debug("clicked button with text: {s}", .{self.text});
                }
            }.a,
        );
    }

    fn end_btn(r: *c.SDL_Renderer, f: *c.TTF_Font) e.Button {
        return e.Button.init(
            r,
            f,
            .{ .x = 450, .y = 50, .w = 100, .h = 40 },
            "Finish",
            .{ .r = 240, .g = 240, .b = 240, .a = 255 },
            .{ .r = 50, .g = 50, .b = 50, .a = 255 },
            .{ .r = 0, .g = 125, .b = 125, .a = 255 },
            struct {
                fn a(_: *e.Button, app_state: *AppState) !void {
                    log.debug("byeeeeeee", .{});
                    app_state.should_quit = true;
                }
            }.a,
        );
    }
};
