const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("../lib.zig");
const Reader = lib.Reader;
const log = std.log.scoped(.ext2);
const set_fields_alignment_in_struct = lib.set_fields_alignment_in_struct;
const set_fields_alignment = lib.set_fields_alignment;

pub const EXT2 = struct {
    const SuperblockOffset = 0x400;

    /// 1024 bytes in size, in revision 0 at beginning of every block group.
    /// From revision 1 of EXT2 they can be placed sparsely every other block.
    const Superblock = extern struct {
        /// Value indicating the total number of inodes, both used and free, in the file system.
        /// This value must be lower or equal to (s_inodes_per_group * number of block groups). It
        /// must be equal to the sum of the inodes defined in each block group.
        inodes_count: u32 align(1),

        /// Value indicating the total number of blocks in the system including all used, free and
        /// reserved. This value must be lower or equal to (s_blocks_per_group * number of block
        /// groups). It can be lower than the previous calculation if the last block group has a
        /// smaller number of blocks than s_blocks_per_group du to volume size. It must be equal to
        /// the sum of the blocks defined in each block group.
        blocks_count: u32 align(1),

        /// Value indicating the total number of blocks reserved for the usage of the super user.
        /// This is most useful if for some reason a user, maliciously or not, fill the file system
        /// to capacity; the super user will have this specified amount of free blocks at his
        /// disposal so he can edit and save configuration files.
        r_blocks_count: u32 align(1),

        /// Value indicating the total number of free blocks, including the number of reserved
        /// blocks (see s_r_blocks_count). This is a sum of all free blocks of all the block groups.
        free_blocks_count: u32 align(1),

        /// Value indicating the total number of free inodes. This is a sum of all free inodes of
        /// all the block groups.
        free_inodes_count: u32 align(1),

        /// Value identifying the first data block, in other word the id of the block containing the
        /// superblock structure.
        ///
        /// Note that this value is always 0 for file systems with a block size larger than 1KB, and
        /// always 1 for file systems with a block size of 1KB. The superblock is always starting at
        /// the 1024th byte of the disk, which normally happens to be the first byte of the 3rd
        /// sector.
        first_data_block: u32 align(1),

        /// The block size is computed using this value as the number of bits to shift left the
        /// value 1024. This value may only be non-negative.
        log_block_size: u32 align(1),

        /// The fragment size is computed using this value as the number of bits to shift left
        /// the value 1024. Note that a negative value would shift the bit right rather than left.
        ///
        /// ```
        /// if( positive )
        ///   fragmnet size = 1024 << s_log_frag_size;
        /// else
        ///   framgnet size = 1024 >> -s_log_frag_size;
        /// ```
        log_frag_size: i32 align(1),

        /// Value indicating the total number of blocks per group. This value in combination with
        /// s_first_data_block can be used to determine the block groups boundaries. Due to volume
        /// size boundaries, the last block group might have a smaller number of blocks than what is
        /// specified in this field.
        blocks_per_group: u32 align(1),

        /// Value indicating the total number of fragments per group. It is also used to determine
        /// the size of the block bitmap of each block group.
        frags_per_group: u32 align(1),

        /// Value indicating the total number of inodes per group. This is also used to determine
        /// the size of the inode bitmap of each block group. Note that you cannot have more than
        /// (block size in bytes * 8) inodes per group as the inode bitmap must fit within a single
        /// block. This value must be a perfect multiple of the number of inodes that can fit in a
        /// block ((1024<<s_log_block_size)/s_inode_size).
        inodes_per_group: u32 align(1),

        /// Unix time, as defined by POSIX, of the last time the file system was mounted.
        mtime: u32 align(1),

        /// Unix time, as defined by POSIX, of the last write access to the file system.
        wtime: u32 align(1),

        /// Value indicating how many times the file system was mounted since the last time it was
        /// fully verified.
        mnt_count: u16 align(1),

        /// Value indicating the maximum number of times that the file system may be mounted before
        /// a full check is performed.
        max_mnt_count: u16 align(1),

        /// Value identifying the file system as Ext2. The value is currently fixed to
        /// EXT2_SUPER_MAGIC of value 0xEF53.
        magic: u16 align(1),

        /// Value indicating the file system state. When the file system is mounted, this state is
        /// set to EXT2_ERROR_FS. After the file system was cleanly unmounted, this value is set to
        /// EXT2_VALID_FS.
        ///
        /// When mounting the file system, if a valid of EXT2_ERROR_FS is encountered it means the
        /// file system was not cleanly unmounted and most likely contain errors that will need to
        /// be fixed. Typically under Linux this means running fsck.
        state: enum(u16) {
            EXT2_VALID_FS = 1,
            EXT2_ERROR_FS = 2,
        } align(1),

        /// Value indicating what the file system driver should do when an error is detected.
        errors: enum(u16) {
            /// Continue as if nothing happened.
            EXT2_ERRORS_CONTINUE = 1,
            /// Remount read-only
            EXT2_ERRORS_RO       = 2,
            /// Cause a kernel panic
            EXT2_ERRORS_PANIC    = 3,
        } align(1),

        /// Value identifying the minor revision level within its revision level.
        minor_rev_level: u16 align(1),

        /// Unix time, as defined by POSIX, of the last file system check.
        last_check: u32 align(1),

        /// Maximum Unix time interval, as defined by POSIX, allowed between file system checks.
        checkinterval: u32 align(1),

        /// Identifier of the os that created the file system.
        creator_os: enum(u32) {
            EXT2_OS_LINUX   = 0,
            EXT2_OS_HURD    = 1,
            EXT2_OS_MASIX   = 2,
            EXT2_OS_FREEBSD = 3,
            EXT2_OS_LITES   = 4,
        } align(1),

        /// Revision level value.
        rev_level: enum(u32) {
            /// Revision 0.
            EXT2_GOOD_OLD_REV = 0,
            /// Revision 1 with variable inode sizes, extended attributes, etc.
            EXT2_DYNAMIC_REV  = 1,
        } align(1),

        /// Value used as the default user id for reserved blocks.
        def_resuid: u16 align(1),

        /// Value used as the default group id for reserved blocks.
        def_resgid: u16 align(1),

        // EXT2_DYNAMIC_REV specific

        /// Value used as index to the first inode useable for standard files. In revision 0, the
        /// first non-reserved inode is fixed to 11 (EXT2_GOOD_OLD_FIRST_INO). In revision 1 and
        /// later this value may be set to any value.
        first_ino: u32 align(1),

        /// Value indicating the size of the inode structure. In revision 0, this value is always
        /// 128 (EXT2_GOOD_OLD_INODE_SIZE). In revision 1 and later, this value must be a perfect
        /// power of 2 and must be smaller or equal to the block size (1<<s_log_block_size).
        inode_size: u16 align(1),

        /// Value used to indicate the block group number hosting this superblock structure. This
        /// can be used to rebuild the file system from any superblock backup.
        block_group_nr: u16 align(1),

        /// Bitmask of compatible features. The file system implementation is free to support them
        /// or not without risk of damaging the meta-data.
        feature_compat: packed struct(u32) {
            /// Block pre-allocation for new directories.
            EXT2_FEATURE_COMPAT_DIR_PREALLOC:  bool,
            EXT2_FEATURE_COMPAT_IMAGIC_INODES: bool,
            /// An Ext3 journal exists.
            EXT3_FEATURE_COMPAT_HAS_JOURNAL:   bool,
            /// Extended inode attributes are present.
            EXT2_FEATURE_COMPAT_EXT_ATTR:      bool,
            /// Non-standard inode size used.
            EXT2_FEATURE_COMPAT_RESIZE_INO:    bool,
            /// Directory indexing (HTree).
            EXT2_FEATURE_COMPAT_DIR_INDEX:     bool,
            __unused:                           u26,
        } align(1),

        /// Bitmask of incompatible features. The file system implementation should refuse to mount
        /// the file system if any of the indicated feature is unsupported.
        ///
        /// An implementation not supporting these features would be unable to properly use the file
        /// system. For example, if compression is being used and an executable file would be
        /// unusable after being read from the disk if the system does not know how to uncompress
        /// it.
        feature_incompat: packed struct(u32) {
            /// Disk/File compression is used.
            EXT2_FEATURE_INCOMPAT_COMPRESSION: bool,
            EXT2_FEATURE_INCOMPAT_FILETYPE:    bool,
            EXT3_FEATURE_INCOMPAT_RECOVER:     bool,
            EXT3_FEATURE_INCOMPAT_JOURNAL_DEV: bool,
            EXT2_FEATURE_INCOMPAT_META_BG:     bool,
            __unused:                           u27,
        } align(1),

        /// Bitmask of “read-only” features. The file system implementation should mount as
        /// read-only if any of the indicated feature is unsupported.
        feature_ro_compat: packed struct(u32) {
            /// Sparse Superblock.
            EXT2_FEATURE_RO_COMPAT_SPARSE_SUPER: bool,
            /// Large file support, 64-bit file size.
            EXT2_FEATURE_RO_COMPAT_LARGE_FILE:   bool,
            /// Binary tree sorted directory files.
            EXT2_FEATURE_RO_COMPAT_BTREE_DIR:    bool,
            __unused:                             u29,
        } align(1),

        /// Value used as the volume id. This should, as much as possible, be unique for each file
        /// system formatted.
        uuid: [16]u8 align(1),

        /// Volume name, mostly unusued. A valid volume name would consist of only ISO-Latin-1
        /// characters and be 0 terminated.
        volume_name: [16]u8 align(1),

        /// Directory path where the file system was last mounted. While not normally used, it could
        /// serve for auto-finding the mountpoint when not indicated on the command line. Again the
        /// path should be zero terminated for compatibility reasons. Valid path is constructed from
        /// ISO-Latin-1 characters.
        last_mounted: [64]u8 align(1),

        /// Value used by compression algorithms to determine the compression method(s) used.
        algo_bitmap: packed struct(u32) {
            EXT2_LZV1_ALG:   bool,
            EXT2_LZRW3A_ALG: bool,
            EXT2_GZIP_ALG:   bool,
            EXT2_BZIP2_ALG:  bool,
            EXT2_LZO_ALG:    bool,
            __unused:         u27,
        } align(1),

        // Performance hints

        /// Value representing the number of blocks the implementation should attempt to
        /// pre-allocate when creating a new regular file.
        prealloc_blocks: u8 align(1),

        /// Value representing the number of blocks the implementation should attempt to
        /// pre-allocate when creating a new directory.
        prealloc_dir_blocks: u8 align(1),

        __alignment: u16 align(1),

        // Journaling support

        /// Value containing the uuid of the journal superblock.
        journal_uuid: [16]u8 align(1),

        /// Inode number of the journal file.
        journal_inum: u32 align(1),

        /// Device number of the journal file.
        journal_dev: u32 align(1),

        /// Inode number, pointing to the first inode in the list of inodes to delete.
        last_orphan: u32 align(1),

        // Directory indexing support

        /// An array of 4 32bit values containing the seeds used for the hash algorithm for
        /// directory indexing.
        hash_seed: [4]u32 align(1),

        /// Value containing the default hash version used for directory indexing.
        def_hash_version: u8 align(1),

        __padding_reserved: [3]u8 align(1),

        // Other options

        /// Value containing the default mount options for this file system.
        default_mount_options: u32 align(1),

        /// Value indicating the block group ID of the first meta block group.
        first_meta_bg: u32 align(1),

        __unused_reserved: [760]u8 align(1),

        pub fn block_size(self: Superblock) u32 {
            return std.math.shl(u32, 1024, self.log_block_size);
        }

        pub fn n_groups(self: Superblock) u32 {
            return self.inodes_count / self.inodes_per_group;
        }
    };

    /// Starts on the first block following the superblock.
    pub const BlockGroupDescriptorTable = []BlockGroupDescriptor;

    /// For each block group in the file system, such a group_desc is created. Each represent a
    /// single block group within the file system and the information within any one of them is
    /// pertinent only to the group it is describing. Every block group descriptor table contains
    /// all the information about all the block groups.
    pub const BlockGroupDescriptor = set_fields_alignment_in_struct(_BlockGroupDescriptor, 1);
    const _BlockGroupDescriptor = extern struct {
        /// Block id of the first block of the 'block bitmap' for the group represented.
        ///
        /// The actual block bitmap is located within its own allocated blocks starting at the block
        /// ID specified by this value.
        block_bitmap: u32,

        /// Block id of the first block of the 'inode bitmap' for the group represented.
        inode_bitmap: u32,

        /// Block id of the first block of the 'inode table' for the group represented.
        inode_table: u32,

        /// Value indicating the total number of free blocks for the represented group.
        free_blocks_count: u16,

        /// Value indicating the total number of free inodes for the represented group.
        free_inodes_count: u16,

        /// Value indicating the number of inodes allocated to directories for the represented
        /// group.
        used_dirs_count: u16,

        __padding: u16,
        __reserved: [12]u8,
    };

    pub const Error =
        Allocator.Error
        || std.fs.File.ReadError
        || error{
            NotEXT2,
            FileTooSmall,
            UnimplementedCurrently,
            NotEnoughReadToParseSuperblock,
            NotEnoughReadToBlockGroup
        };
    const Self = @This();

    gpa: Allocator,
    reader: *Reader,
    superblock: *Superblock,
    bg_desc_table: BlockGroupDescriptorTable,

    pub fn init(gpa: Allocator, reader: *Reader) Error!Self {
        const superblock = try parse_superblock(gpa, reader);
        if (superblock.magic != 0xef53) return error.NotEXT2;

        const bg_desc_table = try parse_bg_desc_table(gpa, reader, superblock);
        return .{
            .gpa = gpa,
            .reader = reader,
            .superblock = superblock,
            .bg_desc_table = bg_desc_table,
        };
    }

    pub fn deinit(self: Self) void {
        self.gpa.destroy(self.superblock);
        self.gpa.free(self.bg_desc_table);
    }

    pub fn calc_size(self: Self) f64 {
        _ = self;
        return 0;
    }

    fn parse_superblock(gpa: Allocator, reader: *Reader) Error!*Superblock {
        const s = try gpa.create(Superblock);
        errdefer gpa.destroy(s);

        const dest = std.mem.asBytes(s);
        try reader.seek_to(SuperblockOffset);
        const read = try reader.read(dest);
        if (read != dest.len) return error.NotEnoughReadToParseSuperblock;

        return s;
    }

    fn parse_bg_desc_table(gpa: Allocator, reader: *Reader, s: *Superblock) Error!BlockGroupDescriptorTable {
        const n_groups = s.n_groups();
        const table = try gpa.alloc(BlockGroupDescriptor, n_groups);
        errdefer gpa.free(table);

        const bs = s.block_size();
        const offset = if (bs == 1024) bs * 2 else bs;
        try reader.seek_to(offset);
        const size = n_groups * @sizeOf(BlockGroupDescriptor);
        const dest: []u8 = @as([*]u8, @ptrCast(table))[0..size];
        const read = try reader.read(dest);
        if (read != size) return error.NotEnoughReadToBlockGroup;

        return table;
    }

};

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    const FilesystemHandler = lib.FilesystemHandler;
    const EXT2_PATH = "./filesystems/ext2_filesystem.img";
    const t = std.testing;
    const t_alloc = t.allocator;
    const tlog = std.log.scoped(.ext2_tests);

    fn create_ext2_reader() !Reader {
        const f = try std.fs.cwd().openFile(EXT2_PATH, .{});
        return try Reader.init(&f);
    }

    fn parse_cstr(cstr_slice: []const u8) []const u8 {
        for (cstr_slice, 0..) |c, c_idx| {
            if (c == 0) return cstr_slice[0..c_idx];
        }
        return "";
    }

    test "has superblock at SuperblockOffset" {
        var reader = try create_ext2_reader();
        defer reader.deinit();
        const ext2 = try EXT2.init(t_alloc, &reader);
        defer ext2.deinit();

        try t.expectEqual(0xef53, ext2.superblock.magic);
        try t.expectEqual(64000, ext2.superblock.inodes_count);
        try t.expectEqual(4096, ext2.superblock.block_size());
        const expected_ending = "zrec/mnt";
        const last_mounted = parse_cstr(&ext2.superblock.last_mounted);
        try t.expectEqualSlices(u8, expected_ending, last_mounted[last_mounted.len-expected_ending.len..]);
    }

    test "has copies of the superblock" {}

    test "block descriptor group table starts at the first block after superblock" {
        var reader = try create_ext2_reader();
        defer reader.deinit();
        const ext2 = try EXT2.init(t_alloc, &reader);
        defer ext2.deinit();

        for (ext2.bg_desc_table) |bg| lib.print(bg, null);
    }

    test "copy of block group descriptor is also stored with every copy of the superblock" {}

    test "read first block descriptors" {}
};
