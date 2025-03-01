const FAT32 = @import("filesystems/FAT.zig");
const NTFS  = @import("filesystems/NTFS.zig");
const EXT2  = @import("filesystems/EXT2.zig");

pub const Filesystem = union(enum) {
    fat32: FAT32,
    ntfs:  NTFS,
    ext2:  EXT2,
    // ext3: EXT3,
    // ext4: EXT4,

    pub const Error = FAT32.Error || EXT2.Error || NTFS.Error;

    pub fn deinit(self: *Filesystem) void {
        switch (self.*) { inline else => |*it| it.deinit() }
        self.* = undefined;
    }

    pub fn name(self: Filesystem) [:0]const u8 {
        return @tagName(self);
    }

    /// Returns size of the filesystem in bytes.
    pub fn get_size(self: Filesystem) f64 {
        return switch (self) { inline else => |*it| it.get_size() };
    }

    /// Returns free size of the filesystem in bytes.
    pub fn get_free_size(self: Filesystem) f64 {
        return switch (self) { inline else => |*it| it.get_free_size() };
    }
};
