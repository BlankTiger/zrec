const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("../lib.zig");
const Reader = lib.Reader;
const log = std.log.scoped(.ext2);
const set_fields_alignment_in_struct = lib.set_fields_alignment_in_struct;

pub const EXT2 = struct {
    /// 1024 bytes in size, in revision 0 at beginning of every block group.
    /// From revision 1 of EXT2 they can be placed sparsely every other block.
    pub const Superblock = set_fields_alignment_in_struct(_Superblock, 1);
    const _Superblock = extern struct {
        /// Value indicating the total number of inodes, both used and free, in the file system.
        /// This value must be lower or equal to (s_inodes_per_group * number of block groups). It
        /// must be equal to the sum of the inodes defined in each block group.
        inodes_count: u32,

        /// Value indicating the total number of blocks in the system including all used, free and
        /// reserved. This value must be lower or equal to (s_blocks_per_group * number of block
        /// groups). It can be lower than the previous calculation if the last block group has a
        /// smaller number of blocks than s_blocks_per_group du to volume size. It must be equal to
        /// the sum of the blocks defined in each block group.
        blocks_count: u32,

        /// Value indicating the total number of blocks reserved for the usage of the super user.
        /// This is most useful if for some reason a user, maliciously or not, fill the file system
        /// to capacity; the super user will have this specified amount of free blocks at his
        /// disposal so he can edit and save configuration files.
        r_blocks_count: u32,

        /// Value indicating the total number of free blocks, including the number of reserved
        /// blocks (see s_r_blocks_count). This is a sum of all free blocks of all the block groups.
        free_blocks_count: u32,

        /// Value indicating the total number of free inodes. This is a sum of all free inodes of
        /// all the block groups.
        free_inodes_count: u32,

        /// Value identifying the first data block, in other word the id of the block containing the
        /// superblock structure.
        ///
        /// Note that this value is always 0 for file systems with a block size larger than 1KB, and
        /// always 1 for file systems with a block size of 1KB. The superblock is always starting at
        /// the 1024th byte of the disk, which normally happens to be the first byte of the 3rd
        /// sector.
        first_data_block: u32,

        /// The block size is computed using this value as the number of bits to shift left the
        /// value 1024. This value may only be non-negative.
        log_block_size: u32,

        /// The fragment size is computed using this value as the number of bits to shift left
        /// the value 1024. Note that a negative value would shift the bit right rather than left.
        ///
        /// ```
        /// if( positive )
        ///   fragmnet size = 1024 << s_log_frag_size;
        /// else
        ///   framgnet size = 1024 >> -s_log_frag_size;
        /// ```
        log_frag_size: i32,

        /// Value indicating the total number of blocks per group. This value in combination with
        /// s_first_data_block can be used to determine the block groups boundaries. Due to volume
        /// size boundaries, the last block group might have a smaller number of blocks than what is
        /// specified in this field.
        blocks_per_group: u32,

        /// Value indicating the total number of fragments per group. It is also used to determine
        /// the size of the block bitmap of each block group.
        frags_per_group: u32,

        /// Value indicating the total number of inodes per group. This is also used to determine
        /// the size of the inode bitmap of each block group. Note that you cannot have more than
        /// (block size in bytes * 8) inodes per group as the inode bitmap must fit within a single
        /// block. This value must be a perfect multiple of the number of inodes that can fit in a
        /// block ((1024<<s_log_block_size)/s_inode_size).
        inodes_per_group: u32,

        /// Unix time, as defined by POSIX, of the last time the file system was mounted.
        mtime: u32,

        /// Unix time, as defined by POSIX, of the last write access to the file system.
        wtime: u32,

        /// Value indicating how many times the file system was mounted since the last time it was
        /// fully verified.
        mnt_count: u16,

        /// Value indicating the maximum number of times that the file system may be mounted before
        /// a full check is performed.
        max_mnt_count: u16,

        /// Value identifying the file system as Ext2. The value is currently fixed to
        /// EXT2_SUPER_MAGIC of value 0xEF53.
        magic: u16,

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
        },

        /// Value indicating what the file system driver should do when an error is detected.
        errors: enum(u16) {
            /// Continue as if nothing happened.
            EXT2_ERRORS_CONTINUE = 1,
            /// Remount read-only
            EXT2_ERRORS_RO       = 2,
            /// Cause a kernel panic
            EXT2_ERRORS_PANIC    = 3,
        },

        /// Value identifying the minor revision level within its revision level.
        minor_rev_level: u16,

        /// Unix time, as defined by POSIX, of the last file system check.
        last_check: u32,

        /// Maximum Unix time interval, as defined by POSIX, allowed between file system checks.
        checkinterval: u32,

        /// Identifier of the os that created the file system.
        creator_os: enum(u32) {
            EXT2_OS_LINUX   = 0,
            EXT2_OS_HURD    = 1,
            EXT2_OS_MASIX   = 2,
            EXT2_OS_FREEBSD = 3,
            EXT2_OS_LITES   = 4,
        },

        /// Revision level value.
        rev_level: enum(u32) {
            /// Revision 0.
            EXT2_GOOD_OLD_REV = 0,
            /// Revision 1 with variable inode sizes, extended attributes, etc.
            EXT2_DYNAMIC_REV  = 1,
        },

        /// Value used as the default user id for reserved blocks.
        def_resuid: u16,

        /// Value used as the default group id for reserved blocks.
        def_resgid: u16,

        // EXT2_DYNAMIC_REV specific

        /// Value used as index to the first inode useable for standard files. In revision 0, the
        /// first non-reserved inode is fixed to 11 (EXT2_GOOD_OLD_FIRST_INO). In revision 1 and
        /// later this value may be set to any value.
        first_ino: u32,

        /// Value indicating the size of the inode structure. In revision 0, this value is always
        /// 128 (EXT2_GOOD_OLD_INODE_SIZE). In revision 1 and later, this value must be a perfect
        /// power of 2 and must be smaller or equal to the block size (1<<s_log_block_size).
        inode_size: u16,

        /// Value used to indicate the block group number hosting this superblock structure. This
        /// can be used to rebuild the file system from any superblock backup.
        block_group_nr: u16,

        /// Bitmask of compatible features. The file system implementation is
        /// free to support them or not without risk of damaging the meta-data.
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
        },

        /// Bitmask of incompatible features. The file system implementation
        /// should refuse to mount the file system if any of the indicated
        /// feature is unsupported.
        ///
        /// An implementation not supporting these features would be unable to
        /// properly use the file system. For example, if compression is being
        /// used and an executable file would be unusable after being read from
        /// the disk if the system does not know how to uncompress it.
        feature_incompat: packed struct(u32) {
            /// Disk/File compression is used.
            EXT2_FEATURE_INCOMPAT_COMPRESSION: bool,
            EXT2_FEATURE_INCOMPAT_FILETYPE:    bool,
            EXT3_FEATURE_INCOMPAT_RECOVER:     bool,
            EXT3_FEATURE_INCOMPAT_JOURNAL_DEV: bool,
            EXT2_FEATURE_INCOMPAT_META_BG:     bool,
            __unused:                           u27,
        },
        feature_ro_compat: u32,
        uuid: [16]u8,
        volume_name: [16]u8,
        last_mounted: [64]u8,
        algo_bitmap: u32,

        // Performance hints
        prealloc_blocks: u8,
        prealloc_dir_blocks: u8,
        __alignment: u16,

        // Journaling support
        journal_uuid: [16]u8,
        journal_inum: u32,
        journal_dev: u32,
        last_orphan: u32,

        // Directory indexing support
        hash_seed: [4*4]u8,
        def_hash_version: u8,
        __padding_reserved: [3]u8,

        // Other options
        default_mount_options: u32,
        first_meta_bg: u32,
        __unused_reserved: [760]u8,
    };

    pub const Error =
        Allocator.Error
        || std.fs.File.ReadError
        || error{
            NotEXT2,
            FileTooSmall,
            UnimplementedCurrently,
        };
    const Self = @This();

    gpa: Allocator,
    reader: *Reader,

    pub fn init(gpa: Allocator, reader: *Reader) Error!Self {
        if (true) return error.UnimplementedCurrently;
        return .{
            .gpa = gpa,
            .reader = reader,
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }

    pub fn calc_size(self: Self) f64 {
        _ = self;
        return 0;
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

    test "has superblock at offset 1K" {
    }
};
