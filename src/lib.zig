const std = @import("std");
const filesystems = @import("filesystems.zig");
const filetypes = @import("filetypes.zig");
const reader = @import("reader.zig");
const printer = @import("printer.zig");
const utils = @import("utils.zig");

pub const ReadReader = reader.ReadReader;
pub const MmapReader = reader.MmapReader;
/// Choice of Reader over the application and tests is made here
/// changing the line below should change implementation in all
/// necessary places.
pub const Reader = MmapReader;
pub const JPGRecoverer = filetypes.JPGRecoverer;
pub const PNGRecoverer = filetypes.PNGRecoverer;
pub const Filetypes = filetypes.Filetypes;
pub const print = printer.print;
pub const PrintOpts = printer.Opts;
pub const set_fields_alignment = utils.set_fields_alignment;
pub const set_fields_alignment_in_struct = utils.set_fields_alignment_in_struct;

pub const FilesystemHandler = filesystems.FilesystemHandler;

test {
    std.testing.refAllDecls(@This());
}
