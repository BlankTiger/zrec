const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("lib.zig");
const Reader = lib.Reader;
const log = std.log.scoped(.filesystems);
const FAT32 = @import("filesystems/FAT.zig");
const NTFS = @import("filesystems/NTFS.zig");
const EXT2 = @import("filesystems/EXT2.zig");
const Filesystem = @import("filesystem.zig").Filesystem;

const Error =
    Filesystem.Error
    || Allocator.Error
    || std.fs.File.ReadError
    || std.fs.File.OpenError
    || std.posix.MMapError
    || error{ NoFilesystemMatch };

alloc: Allocator,
path: []const u8,
/// can be used to lookup what errors happened during a call to `determine_filesystem`
errors: std.ArrayList(Error),
_files: std.ArrayList(*std.fs.File),
_readers: std.ArrayList(*Reader),

const FsHandler = @This();

pub fn init(alloc: Allocator, filepath: []const u8) Error!FsHandler {
    return .{
        .alloc = alloc,
        .path = try alloc.dupe(u8, filepath),
        .errors = std.ArrayList(Error).init(alloc),
        ._files = std.ArrayList(*std.fs.File).init(alloc),
        ._readers = std.ArrayList(*Reader).init(alloc),
    };
}

pub fn deinit(self: *FsHandler) void {
    self.alloc.free(self.path);
    self.errors.deinit();
    for (self._readers.items) |r| {
        r.deinit();
        self.alloc.destroy(r);
    }
    self._readers.deinit();
    for (self._files.items) |f| {
        self.alloc.destroy(f);
    }
    self._files.deinit();
    self.* = undefined;
}

pub fn update_path(self: *FsHandler, new_path: []const u8) Allocator.Error!void {
    self.alloc.free(self.path);
    self.path = try self.alloc.dupe(u8, new_path);
}

/// Caller must call deinit on the resulting Filesystem
pub fn determine_filesystem(self: *FsHandler) Error!Filesystem {
    inline for (std.meta.fields(Filesystem)) |field| {
        var reader = try self.create_new_reader();
        errdefer reader.deinit();
        if (field.type.init(self.alloc, &reader)) |fs| {
            return @unionInit(Filesystem, field.name, fs);
        } else |err| {
            log.info("couldnt init {any}, err: {any}", .{field.type, err});
            try self.errors.append(err);
        }
    }

    return Error.NoFilesystemMatch;
}

/// Caller must call `deinit` on the resulting Reader.
pub fn create_new_reader(self: *FsHandler) Error!Reader {
    const f = try self.alloc.create(std.fs.File);
    errdefer self.alloc.destroy(f);
    f.* = try std.fs.cwd().openFile(self.path, .{});
    try self._files.append(f);

    return try Reader.init(f);
}

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    const t = std.testing;
    const t_alloc = t.allocator;
    const assert = std.debug.assert;
    const FAT32_PATH = "./filesystems/fat32_filesystem.img";
    const tlog = std.log.scoped(.filesystems_tests);

    test "create new reader cleans up everything when somethings goes wrong (file access err)" {
        var fs_handler = try FsHandler.init(t_alloc, "this path doesnt exist");
        defer fs_handler.deinit();
        try t.expectError(error.FileNotFound, fs_handler.create_new_reader());
        try fs_handler.update_path(FAT32_PATH);
    }

    test "hold all errors found during determine_filesystem" {
        var _dir = t.tmpDir(.{});
        defer _dir.cleanup();
        const dir = _dir.dir;
        const filename = "tmp_not_filesystem";
        {
            const tmp_file = try dir.createFile(filename, .{});
            defer tmp_file.close();
            _ = try tmp_file.write("siema elo tmp file");
        }
        const path = try dir.realpathAlloc(t_alloc, filename);
        defer t_alloc.free(path);
        tlog.debug("{s}", .{path});

        var fs_handler = try FsHandler.init(t_alloc, path);
        defer fs_handler.deinit();
        try t.expectError(error.NoFilesystemMatch, fs_handler.determine_filesystem());
        try t.expectEqual(3, fs_handler.errors.items.len);
        try t.expectEqualSlices(
            FsHandler.Error,
            fs_handler.errors.items,
            &[_]FsHandler.Error{
                error.FileTooSmall,
                error.UnimplementedCurrently,
                error.NotEnoughReadToParseSuperblock,
            }
        );
    }
};
