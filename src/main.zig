const std = @import("std");
const fat = @import("fat.zig");
const FAT32 = fat.FAT32;
const Allocator = std.mem.Allocator;
const log = std.log;
const assert = std.debug.assert;

fn is_jpeg(bytes: [3]u8) bool {
    return std.mem.eql(u8, bytes, &[3]u8{ 0xff, 0xd8, 0xff });
}

const Filesystem = union(enum) {
    fat32: FAT32,
    // ntfs: NTFS,
    // ext4: EXT4,
    // ext3: EXT3,
    // ext2: EXT2,
};

const FilesystemHandler = struct {
    alloc: Allocator,
    file: std.fs.File,
    reader: std.io.BufferedReader(4096, std.fs.File.Reader),
    buf: []u8,

    const Self = @This();

    const Error =
        FAT32.Error
        || Allocator.Error
        || std.fs.File.ReadError
        || std.fs.File.OpenError
        || error{ NoFilesystemMatch };

    pub fn init(alloc: Allocator, filepath: []u8) Error!Self {
        const f = try std.fs.cwd().openFile(filepath, .{});
        const f_reader = f.reader();
        const b_reader = std.io.bufferedReader(f_reader);
        return Self {
            .alloc = alloc,
            .file = f,
            .reader = b_reader,
            .buf = try alloc.alloc(u8, 10_000),
        };
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
        self.alloc.free(self.buf);
        self.* = undefined;
    }

    pub fn determine_filesystem(self: *Self) Error!Filesystem {
        const read = try self.reader.read(self.buf);
        if (FAT32.init(self.buf[0..read])) |fat32| return .{ .fat32 = fat32 } else |_| {}
        return Error.NoFilesystemMatch;
    }
};

pub fn main() !void {
    // var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa_state.deinit();
    // const gpa = gpa_state.allocator();

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    assert(args.len > 1);
    const path = args[1];

    var mem_handler = try FilesystemHandler.init(arena, path);
    defer mem_handler.deinit();

    const fs = mem_handler.determine_filesystem() catch |err| {
        switch (err) {
            error.NoFilesystemMatch =>
                log.err("No filesystem matches image that was passed into the program\n", .{}),
            else => log.err("Unexpected err: {any}\n", .{err}),
        }
        return err;
    };
    switch (fs) {
        .fat32 => |fat32| {
            log.debug("jmp_boot: {X}\n", .{fat32.boot_sector.jmp_boot});
            log.debug("bytes_per_sector: {d}\n", .{fat32.bios_parameter_block.bytes_per_sector});
            log.debug("sectors_per_cluster: {d}\n", .{fat32.bios_parameter_block.sectors_per_cluster});
        }
    }
}
