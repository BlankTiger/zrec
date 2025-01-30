const jpg = @import("filetypes/jpg.zig");
const png = @import("filetypes/png.zig");

pub const JPGRecoverer = jpg.JPGRecoverer;
pub const PNGRecoverer = png.PNGRecoverer;
pub const Filetypes = enum {
    jpg,
    png,

    const _fields = @typeInfo(@This()).Enum.fields;
    const _len = _fields.len;
    /// Array of available filetypes for convenience
    pub const types: [_len][:0]const u8 = blk: {
        var res: [_len][:0]const u8 = undefined;
        for (_fields, 0..) |f, idx| {
            res[idx] = f.name;
        }
        break :blk res;
    };
};
