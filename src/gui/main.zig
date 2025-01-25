const std = @import("std");
const config = @import("config");
const log = std.log.scoped(.gui_main);
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

var FPS: u32 = config.fps;

pub fn main() !void {
    const SCREEN_TICKS_PER_FRAME = 1000.0 / @as(f64, @floatFromInt(FPS));

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        return;
    }

    const window = c.SDL_CreateWindow("zrec", 600, 400, c.SDL_WINDOW_RESIZABLE) orelse {
        log.err("something went wrong with the window init", .{});
        return;
    };
    const renderer = c.SDL_CreateRenderer(window, undefined) orelse {
        log.err("something went wrong with the renderer init", .{});
        return;
    };

    var avg_fps: f64 = 0;

    while (true) {
        // const start_time = c.SDL_GetTicks();
        // const start: f64 = @floatFromInt(c.SDL_GetPerformanceCounter());

        const start_tick = c.SDL_GetTicks();

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    return;
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                },
                else => {},
            }
        }

        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderPresent(renderer);
        _ = c.SDL_UpdateWindowSurface(window);

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
