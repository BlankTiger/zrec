const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("lib.zig");
const Reader = lib.Reader;
const FAT32 = @import("filesystems/fat.zig").FAT32;
const NTFS = @import("filesystems/ntfs.zig").NTFS;
const EXT2 = @import("filesystems/ext2.zig").EXT2;
const log = std.log.scoped(.filesystems);

pub const FilesystemHandler = struct {
    alloc: Allocator,
    path: []const u8,
    /// can be used to lookup what errors happened during a call to `determine_filesystem`
    errors: std.ArrayList(Error),
    _files: std.ArrayList(*std.fs.File),
    _readers: std.ArrayList(*Reader),

    const Self = @This();

    const Error =
        FAT32.Error
        || EXT2.Error
        || NTFS.Error
        || Allocator.Error
        || std.fs.File.ReadError
        || std.fs.File.OpenError
        || std.posix.MMapError
        || error{ NoFilesystemMatch };

    pub fn init(alloc: Allocator, filepath: []const u8) Error!Self {
        return .{
            .alloc = alloc,
            .path = try alloc.dupe(u8, filepath),
            .errors = std.ArrayList(Error).init(alloc),
            ._files = std.ArrayList(*std.fs.File).init(alloc),
            ._readers = std.ArrayList(*Reader).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
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

    pub fn update_path(self: *Self, new_path: []const u8) Allocator.Error!void {
        self.alloc.free(self.path);
        self.path = try self.alloc.dupe(u8, new_path);
    }

    pub const Filesystem = union(enum) {
        fat32: FAT32,
        ntfs: NTFS,
        ext2: EXT2,
        // ext4: EXT4,
        // ext3: EXT3,

        pub fn deinit(self: *Filesystem) void {
            switch (self.*) {
                inline else => |*it| it.deinit(),
            }
            self.* = undefined;
        }

        pub fn name(self: Filesystem) [:0]const u8 {
            return @tagName(self);
        }

        pub fn calc_size(self: Filesystem) f64 {
            return switch (self) {
                inline else => |*it| it.calc_size(),
            };
        }

    };

    /// Caller must call deinit on the resulting Filesystem
    pub fn determine_filesystem(self: *Self) Error!Filesystem {
        inline for (std.meta.fields(Filesystem)) |field| {
            if (field.type.init(self.alloc, try self.create_new_reader())) |fs| {
                return @unionInit(Filesystem, field.name, fs);
            } else |err| {
                log.warn("couldnt init {any}, err: {any}", .{field.type, err});
                try self.errors.append(err);
            }
        }

        return Error.NoFilesystemMatch;
    }

    /// *Reader is kept internally in an ArrayList.
    /// Calling deinit on FilesystemHandler also deinits *Reader.
    pub fn create_new_reader(self: *Self) Error!*Reader {
        const f = try self.alloc.create(std.fs.File);
        errdefer self.alloc.destroy(f);
        f.* = try std.fs.cwd().openFile(self.path, .{});
        try self._files.append(f);

        const custom_reader = try self.alloc.create(Reader);
        errdefer self.alloc.destroy(custom_reader);
        custom_reader.* = try Reader.init(f);
        try self._readers.append(custom_reader);
        return custom_reader;
    }
};

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
        var fs_handler = try FilesystemHandler.init(t_alloc, "this path doesnt exist");
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

        var fs_handler = try FilesystemHandler.init(t_alloc, path);
        defer fs_handler.deinit();
        try t.expectError(error.NoFilesystemMatch, fs_handler.determine_filesystem());
        try t.expectEqual(3, fs_handler.errors.items.len);
        try t.expectEqualSlices(
            FilesystemHandler.Error,
            fs_handler.errors.items,
            &[_]FilesystemHandler.Error{
                error.FileTooSmall,
                error.UnimplementedCurrently,
                error.NotEnoughReadToParseSuperblock,
            }
        );
    }
};
