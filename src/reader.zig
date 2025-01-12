const std = @import("std");

pub const Reader = std.io.BufferedReader(4096, std.fs.File.Reader);
