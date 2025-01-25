const std = @import("std");
const log = std.log.scoped(.button);
const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});
const AppState = @import("../state.zig").AppState;

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
text_rect: c.SDL_FRect = undefined,
bg_color: c.SDL_Color,
clicked_bg_color: c.SDL_Color,
state: enum { down, up } = .up,
action: ActionT,

text_surface: *c.SDL_Surface,
text_texture: *c.SDL_Texture,

const ActionT = *const fn(*Button, *AppState) anyerror!void;
const Button = @This();

pub fn init(
    renderer: *c.SDL_Renderer,
    font: *c.TTF_Font,
    rect: c.SDL_FRect,
    text: []const u8,
    text_color: c.SDL_Color,
    bg_color: c.SDL_Color,
    clicked_bg_color: c.SDL_Color,
    action: ActionT,
) Button {
    const txt_surface = c.TTF_RenderText_Shaded(font, @as([*c]const u8, @ptrCast(text)), text.len, text_color, bg_color);
    const txt_texture = c.SDL_CreateTextureFromSurface(renderer, txt_surface);

    const pad_x = 0.15;
    const pad_y = 0.10;

    var btn: Button = .{
        .r = renderer,
        .f = font,
        .rect = undefined,
        .text = text,
        .pad_x = pad_x,
        .pad_y = pad_y,
        .text_color = text_color,
        .text_rect = undefined,
        .bg_color = bg_color,
        .clicked_bg_color = clicked_bg_color,
        .action = action,

        .text_surface = txt_surface,
        .text_texture = txt_texture,
    };

    var r = rect;
    const _pad_x = pad_x * r.w;
    const _pad_y = pad_y * r.h;
    var bounding_rect: c.SDL_FRect = .{ .x = r.x + _pad_x, .y = r.y + _pad_y, .w = @floatFromInt(btn.text_surface.w), .h = @floatFromInt(btn.text_surface.h) };
    r.w = @max(r.w, (1 + pad_x) * bounding_rect.w);
    r.h = @max(r.h, (1 + pad_y) * bounding_rect.h);
    bounding_rect.x = r.x + (r.w - bounding_rect.w) / 2;
    bounding_rect.y = r.y + (r.h - bounding_rect.h) / 2;
    btn.text_rect = bounding_rect;
    btn.rect = r;

    return btn;
}

pub fn deinit(self: Button) void {
    self.destroy_text();
}

fn destroy_text(self: Button) void {
    _ = c.SDL_DestroySurface(self.text_surface);
    _ = c.SDL_DestroyTexture(self.text_texture);
}

pub fn click(self: *Button, state: *AppState) !void {
    self.state = .down;
    try self.action(self, state);
}

const CLICKED_TIME = 90;
var clicked_time: u64 = 0;

pub fn update(self: *Button) void {
    if (self.state == .down and clicked_time == 0) {
        clicked_time = c.SDL_GetTicks();
        self.update_text_bg();
    }

    if (self.state == .down and c.SDL_GetTicks() - clicked_time > CLICKED_TIME) {
        self.state = .up;
        self.update_text_bg();
        clicked_time = 0;
    }
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
    const bg = &switch (self.state) {
        .up => self.bg_color,
        .down => self.clicked_bg_color,
    };
    const r = &self.rect;

    if (self.radius > 0) {
        // TODO: make rounded buttons
    } else {
        _ = c.SDL_SetRenderDrawColor(self.r, bg.r, bg.g, bg.b, bg.a);
        _ = c.SDL_RenderFillRect(self.r, r);
    }
    _ = c.SDL_RenderTexture(self.r, self.text_texture, null, &self.text_rect);
}
