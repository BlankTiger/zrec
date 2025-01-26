const std = @import("std");
const log = std.log.scoped(.text);
const AppState = @import("../state.zig").AppState;
const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

r: *c.SDL_Renderer,
f: *c.TTF_Font,
rect: c.SDL_FRect,
text: []u8,
text_len: ?*usize = null,
dynamic: bool,
text_color: c.SDL_Color,
bg_color: c.SDL_Color,

text_surface: *c.SDL_Surface,
text_texture: *c.SDL_Texture,

const Text = @This();

pub fn init(
    renderer: *c.SDL_Renderer,
    font: *c.TTF_Font,
    rect: c.SDL_FRect,
    text: []u8,
    text_len: ?*usize,
    dynamic: bool,
    text_color: c.SDL_Color,
    bg_color: c.SDL_Color,
) Text {
    const txt_surface = c.TTF_RenderText_Shaded(font, @as([*c]const u8, @ptrCast(text)), text.len, text_color, bg_color);
    const txt_texture = c.SDL_CreateTextureFromSurface(renderer, txt_surface);

    return .{
        .r = renderer,
        .f = font,
        .rect = rect,
        .text = text,
        .text_len = text_len,
        .dynamic = dynamic,
        .text_color = text_color,
        .bg_color = bg_color,

        .text_surface = txt_surface,
        .text_texture = txt_texture,
    };
}

pub fn deinit(self: *Text) void {
    self.destroy_text();
    self.* = undefined;
}

fn destroy_text(self: *const Text) void {
    _ = c.SDL_DestroySurface(self.text_surface);
    _ = c.SDL_DestroyTexture(self.text_texture);
}

pub fn update(self: *Text) void {
    if (self.dynamic) {
        const len = self.text_len.?.*;
        self.destroy_text();
        self.text_surface = c.TTF_RenderText_Shaded(self.f, @as([*c]const u8, @ptrCast(self.text)), len, self.text_color, self.bg_color);
        self.text_texture = c.SDL_CreateTextureFromSurface(self.r, self.text_surface);
    }
}

pub fn draw(self: *const Text) void {
    const r: c.SDL_FRect = .{ .x = self.rect.x, .y = self.rect.y, .w = @floatFromInt(self.text_surface.w), .h = @floatFromInt(self.text_surface.h) };
    _ = c.SDL_RenderTexture(self.r, self.text_texture, null, &r);
}
