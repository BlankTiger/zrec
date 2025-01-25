const std = @import("std");
const log = std.log.scoped(.button);
const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

r: *c.SDL_Renderer,
f: *c.TTF_Font,
rect: c.SDL_FRect,
text: []const u8,
/// percent
pad_x: f32,
/// percent
pad_y: f32,
/// radius of the corners
radius: f32 = 0,
text_color: c.SDL_Color,
bg_color: c.SDL_Color,
clicked_bg_color: c.SDL_Color,
state: enum { down, up } = .up,
action: *const fn() anyerror!void,

text_surface: *c.SDL_Surface,
text_texture: *c.SDL_Texture,

const Button = @This();

pub fn init(
    renderer: *c.SDL_Renderer,
    font: *c.TTF_Font,
    rect: c.SDL_FRect,
    text: []const u8,
    text_color: c.SDL_Color,
    bg_color: c.SDL_Color,
    clicked_bg_color: c.SDL_Color,
    action: *const fn() anyerror!void,
) Button {
    const txt_surface = c.TTF_RenderText_Shaded(font, @as([*c]const u8, @ptrCast(text)), text.len, text_color, bg_color);
    const txt_texture = c.SDL_CreateTextureFromSurface(renderer, txt_surface);

    return .{
        .r = renderer,
        .f = font,
        .rect = rect,
        .text = text,
        .pad_x = 0.15,
        .pad_y = 0.10,
        .text_color = text_color,
        .bg_color = bg_color,
        .clicked_bg_color = clicked_bg_color,
        .action = action,

        .text_surface = txt_surface,
        .text_texture = txt_texture,
    };
}

pub fn deinit(self: Button) void {
    self.destroy_text();
}

fn destroy_text(self: Button) void {
    _ = c.SDL_DestroySurface(self.text_surface);
    _ = c.SDL_DestroyTexture(self.text_texture);
}

pub fn click(self: *Button) !void {
    self.state = .down;
    try self.action();
}

const CLICKED_TIME = 90;
var clicked_time: u64 = 0;

pub fn update(self: *Button, ev: ?c.SDL_Event) void {
    if (self.state == .down and clicked_time == 0) {
        clicked_time = c.SDL_GetTicks();
        self.update_text_bg();
    }

    if (self.state == .down and c.SDL_GetTicks() - clicked_time > CLICKED_TIME) {
        self.state = .up;
        self.update_text_bg();
        clicked_time = 0;
    }

    if (ev) |e| switch (e.type) {
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            log.debug("{any}", .{e.button});
        },
        else => unreachable,
    };
}

fn update_text_bg(self: *Button) void {
    const bg = switch (self.state) {
        .up => self.bg_color,
        .down => self.clicked_bg_color,
    };
    self.destroy_text();
    self.text_surface = c.TTF_RenderText_Shaded(self.f, @as([*c]const u8, @ptrCast(self.text)), self.text.len, self.text_color, bg);
    self.text_texture = c.SDL_CreateTextureFromSurface(self.r, self.text_surface);
}

pub fn draw(self: Button) void {
    const bg = switch (self.state) {
        .up => &self.bg_color,
        .down => &self.clicked_bg_color,
    };
    const r = &self.rect;
    if (self.radius > 0) {
    } else {
        _ = c.SDL_SetRenderDrawColor(self.r, bg.r, bg.g, bg.b, bg.a);
        _ = c.SDL_RenderFillRect(self.r, r);
    }
    const _pad_x = self.pad_x * r.w;
    const _pad_y = self.pad_y * r.h;
    const bounding_rect: c.SDL_FRect = .{ .x = r.x + _pad_x, .y = r.y + _pad_y, .w = r.w - _pad_x*2, .h = r.h - _pad_y*2 };
    _ = c.SDL_RenderTexture(self.r, self.text_texture, null, &bounding_rect);
}

