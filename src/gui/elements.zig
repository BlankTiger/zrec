// pub const TextArea = @import("elements/text_area.zig");
// pub const Window = @import("elements/window.zig");
pub const Button = @import("elements/button.zig");
// pub const Picker = @import("elements/picker.zig");
// pub const Image = @import("elements/image.zig");
pub const Text = @import("elements/text.zig");

pub const Element = union(enum) {
    button: Button,
    text: Text,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .button => |*b| b.deinit(),
            .text => |*t| t.deinit(),
        }
        self.* = undefined;
    }

    pub fn update(self: *Self) void {
        switch (self.*) {
            .button => |*b| b.update(),
            .text => |*t| t.update(),
        }
    }

    pub fn draw(self: *const Self) void {
        switch (self.*) {
            .button => |b| b.draw(),
            .text => |t| t.draw(),
        }
    }
};
