// pub const TextArea = @import("elements/text_area.zig");
// pub const Window = @import("elements/window.zig");
pub const Button = @import("elements/button.zig");
// pub const Picker = @import("elements/picker.zig");
// pub const Image = @import("elements/image.zig");
// pub const Text = @import("elements/text.zig");

pub const Element = union(enum) {
    button: Button,

    const Self = @This();

    pub fn deinit(self: Self) void {
        switch (self) {
            .button => |b| b.deinit(),
        }
    }

    pub fn update(self: *Self) void {
        switch (self.*) {
            .button => |*b| b.update(),
        }
    }

    pub fn draw(self: Self) void {
        switch (self) {
            .button => |b| b.draw(),
        }
    }
};
