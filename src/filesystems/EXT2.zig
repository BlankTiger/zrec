const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("../lib.zig");
const Reader = lib.Reader;
const assert = std.debug.assert;
const log = std.log.scoped(.ext2);
const set_fields_alignment_in_struct = lib.set_fields_alignment_in_struct;
const set_fields_alignment = lib.set_fields_alignment;

const Self = @This();

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

    fn block_size(self: Superblock) u32 {
        return std.math.shl(u32, 1024, self.log_block_size);
    }

    fn n_groups(self: Superblock) u32 {
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

pub const InodeTables = struct {
    tables: []InodeTable,
    filled: std.ArrayList(usize),
    gpa: Allocator,
    group_count: u32,
    inodes_per_group: u32,

    pub fn init(gpa: Allocator, group_count: u32, inodes_per_group: u32) !InodeTables {
        const tables = try gpa.alloc(InodeTable, group_count);
        errdefer gpa.free(tables);

        const filled = try std.ArrayList(usize).initCapacity(gpa, group_count);
        errdefer filled.deinit();

        return .{
            .tables = tables,
            .filled = filled,
            .gpa = gpa,
            .group_count = group_count,
            .inodes_per_group = inodes_per_group,
        };
    }

    pub fn deinit(self: InodeTables) void {
        for (self.filled.items) |filled_group_id| {
            self.gpa.free(self.tables[filled_group_id]);
        }
        self.gpa.free(self.tables);
        self.filled.deinit();
    }

    /// Passed in `table` must be owned.
    pub fn fill_for_group(self: *InodeTables, group_id: usize, table: InodeTable) !void {
        assert(group_id < self.tables.len);
        // NOTE: we may want to update some table (UNLIKELY), if we do, then we must
        // first remove the duplicate group_id from the list, or not insert a duplicate
        // or use a HashSet instead of ArrayList
        assert(!self.has_group_filled(group_id));

        self.tables[group_id] = table;
        try self.filled.append(group_id);
    }

    pub fn has_group_filled(self: InodeTables, group_id: usize) bool {
        return std.mem.indexOfScalar(usize, self.filled.items, group_id) != null;
    }

    pub fn get_group_id_containing_inode_id(self: InodeTables, inode_id: u32) u32 {
        const group_id = (inode_id - 1) / self.inodes_per_group;
        assert(group_id < self.group_count);
        return group_id;
    }

    pub fn get_inode(self: InodeTables, inode_id: u32) Inode {
        const group_id = self.get_group_id_containing_inode_id(inode_id);
        // TODO: verify if -1 is correct. I think it is, because inode ids start from 1.
        const inode_id_in_group = (inode_id - 1) % self.inodes_per_group;
        return self.tables[group_id][inode_id_in_group];
    }
};

pub const InodeTable = []Inode;

/// Inode contains the information about a single physical file on the system. A file can be a
/// directory, a socket, a buffer, character or block device, symbolic link or a regular file.
/// So an inode can be seen as a block of information related to an entity, describing its
/// location on disk, its size and its owner.
pub const Inode = extern struct {
    const Mode = packed struct(u16) {
        const AccessRights = packed struct {
            /// Others execute.
            EXT2_S_IXOTH: u1 = 0,
            /// Others write
            EXT2_S_IWOTH: u1 = 0,
            /// Others read.
            EXT2_S_IROTH: u1 = 0,

            /// Group execute.
            EXT2_S_IXGRP: u1 = 0,
            /// Group write.
            EXT2_S_IWGRP: u1 = 0,
            /// Group read.
            EXT2_S_IRGRP: u1 = 0,

            /// User execute.
            EXT2_S_IXUSR: u1 = 0,
            /// User write.
            EXT2_S_IWUSR: u1 = 0,
            /// User read.
            EXT2_S_IRUSR: u1 = 0,
        };

        const ProcessExecution = packed struct {
            /// Sticky bit.
            EXT2_S_ISVTX: u1 = 0,
            /// Set process Group ID.
            EXT2_S_ISGID: u1 = 0,
            /// Set process User ID.
            EXT2_S_ISUID: u1 = 0,
        };

        const FileFormat = packed struct {
            /// FIFO.
            EXT2_S_IFIFO: u1 = 0,
            /// Character device.
            EXT2_S_IFCHR: u1 = 0,
            /// Directory.
            EXT2_S_IFDIR: u1 = 0,
            /// Regular file.
            EXT2_S_IFREG: u1 = 0,
        };

        /// Block device.
        pub const EXT2_S_IFBLK: FileFormat = .{ .EXT2_S_IFCHR = 1, .EXT2_S_IFDIR = 1 };

        /// Symbolic link.
        pub const EXT2_S_IFLNK: FileFormat = .{ .EXT2_S_IFREG = 1, .EXT2_S_IFCHR = 1 };

        /// Socket.
        pub const EXT2_S_IFSOCK: FileFormat = .{ .EXT2_S_IFREG = 1, .EXT2_S_IFDIR = 1 };

        access_rights: AccessRights,
        process_execution: ProcessExecution,
        file_format: FileFormat,

        pub fn backing_integer(self: Mode) @typeInfo(Mode).@"struct".backing_integer.? {
            return @bitCast(self);
        }

    };

    const Flags = packed struct(u32) {
        const Compression = packed struct {
            /// Dirty (modified).
            EXT2_DIRTY_FL: u1,
            /// Compressed blocks.
            EXT2_COMPRBLK_FL: u1,
            /// Access raw compressed data.
            EXT2_NOCOMPR_FL: u1,
            /// Compression error.
            EXT2_ECOMPR_FL: u1,
        };

        /// Secure deletion.
        EXT2_SECRM_FL: u1,
        /// Record for undelete.
        EXT2_UNRM_FL: u1,
        /// Compressed file.
        EXT2_COMPR_FL: u1,
        /// Synchronous updates.
        EXT2_SYNC_FL: u1,
        /// Immutable file.
        EXT2_IMMUTABLE_FL: u1,
        /// Append only.
        EXT2_APPEND_FL: u1,
        /// do not dump/Delete file.
        EXT2_NODUMP_FL: u1,
        /// Do not update .i_atime.
        EXT2_NOATIME_FL: u1,

        /// Reserved for compression usage.
        compression: Compression,

        /// B-tree format directory.
        EXT2_BTREE_FL: u1,
        /// Hash indexed directory.
        EXT2_INDEX_FL: u1,
        /// AFS directory.
        EXT2_IMAGIC_FL: u1,
        /// Journal file data.
        EXT3_JOURNAL_DATA_FL: u1,

        __unused: u15,

        /// Reserved for ext2 library.
        EXT2_RESERVED_FL: u1,

        pub fn backing_integer(self: Flags) @typeInfo(Flags).@"struct".backing_integer.? {
            return @bitCast(self);
        }
    };

    const OSD2 = extern union {
        hurd: extern struct {
            /// Fragment number. Always 0 GNU HURD since fragments are not supported. Obsolete
            /// with Ext4.
            frag: u8,
            /// Fragment size. Always 0 in GNU HURD since fragments are not supported. Obsolete
            /// with Ext4.
            fsize: u8,
            /// High 16bit of the 32bit mode.
            mode_high: u16,
            /// High 16bit of user id.
            uid_high: u16,
            /// High 16bit of group id.
            gid_high: u16,
            /// User id of the assigned file author. If this value is set to -1, the POSIX user
            /// id will be used.
            author: i32,
        },

        linux: extern struct {
            /// Fragment number.
            ///
            /// Always 0 in Linux since fragments are not supported.
            ///
            /// Important:
            /// A new implementation of Ext2 should completely disregard this field if the
            /// i_faddr value is 0; in Ext4 this field is combined with l_i_fsize to become the
            /// high 16bit of the 48bit blocks count for the inode data.
            frag: u8,
            /// Fragment size.
            ///
            /// Always 0 in Linux since fragments are not supported. Important
            ///
            /// A new implementation of Ext2 should completely disregard this field if the
            /// i_faddr value is 0; in Ext4 this field is combined with l_i_frag to become the
            /// high 16bit of the 48bit blocks count for the inode data.
            fsize: u8,
            __reserved: u16,
            /// High 16bit of user id.
            uid_high: u16,
            /// High 16bit of group id.
            gid_high: u16,
            __reserved2: u32,
        },

        masix: extern struct {
            /// Fragment number. Always 0 in Masix as framgents are not supported. Obsolete with
            /// Ext4.
            frag: u8,
            /// Fragment size. Always 0 in Masix as fragments are not supported. Obsolete with
            /// Ext4.
            fsize: u8,
            __reserved: [10]u8,
        },

        pub fn backing_integer(self: OSD2) @Type(.{
            .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(OSD2) }
        }) {
            return @bitCast(self);
        }
    };

    /// Value used to indicate the format of the described file and the access rights.
    mode: Mode,

    /// User id associated with the file.
    uid: u16,

    /// In revision 0, (signed) 32bit value indicating the size of the file in bytes. In
    /// revision 1 and later revisions, and only for regular files, this represents the lower
    /// 32-bit of the file size; the upper 32-bit is located in the i_dir_acl.
    size: u32,

    /// Value representing the number of seconds since january 1st 1970 of the last time this
    /// inode was accessed.
    atime: u32,

    /// Value representing the number of seconds since january 1st 1970, of when the inode was
    /// created.
    ctime: u32,

    /// Value representing the number of seconds since january 1st 1970, of the last time this
    /// inode was modified.
    mtime: u32,

    /// Value representing the number of seconds since january 1st 1970, of when the inode was
    /// deleted.
    dtime: u32,

    /// Value of the POSIX group having access to this file.
    gid: u16,

    /// Value indicating how many times this particular inode is linked (referred to). Most
    /// files will have a link count of 1. Files with hard links pointing to them will have an
    /// additional count for each hard link.
    ///
    /// Symbolic links do not affect the link count of an inode. When the link count reaches 0
    /// the inode and all its associated blocks are freed.
    links_count: u16,

    /// Value representing the total number of 512-bytes blocks reserved to contain the data of
    /// this inode, regardless if these blocks are used or not. The block numbers of these
    /// reserved blocks are contained in the i_block array.
    ///
    /// Since this value represents 512-byte blocks and not file system blocks, this value
    /// should not be directly used as an index to the i_block array. Rather, the maximum index
    /// of the i_block array should be computed from i_blocks / ((1024<<s_log_block_size)/512),
    /// or once simplified, i_blocks/(2<<s_log_block_size).
    blocks: u32,

    /// Value indicating how the ext2 implementation should behave when accessing the data for
    /// this inode.
    flags: Flags,

    /// OS dependent value.
    ///
    /// Hurd: 32bit value labeled as 'translator'.
    /// Linux: 32bit value currently reserved.
    /// Masix: 32bit value currently reserved.
    osd1: u32,

    ///  15 x 32bit block numbers pointing to the blocks containing the data for this inode. The
    ///  first 12 blocks are direct blocks. The 13th entry in this array is the block number of
    ///  the first indirect block; which is a block containing an array of block ID containing
    ///  the data. Therefore, the 13th block of the file will be the first block ID contained in
    ///  the indirect block. With a 1KiB block size, blocks 13 to 268 of the file data are
    ///  contained in this indirect block.
    ///
    /// The 14th entry in this array is the block number of the first doubly-indirect block;
    /// which is a block containing an array of indirect block IDs, with each of those indirect
    /// blocks containing an array of blocks containing the data. In a 1KiB block size, there
    /// would be 256 indirect blocks per doubly-indirect block, with 256 direct blocks per
    /// indirect block for a total of 65536 blocks per doubly-indirect block.
    ///
    /// The 15th entry in this array is the block number of the triply-indirect block; which is
    /// a block containing an array of doubly-indrect block IDs, with each of those
    /// doubly-indrect block containing an array of indrect block, and each of those indirect
    /// block containing an array of direct block. In a 1KiB file system, this would be a total
    /// of 16777216 blocks per triply-indirect block.
    ///
    /// In the original implementation of Ext2, a value of 0 in this array effectively
    /// terminated it with no further block defined. In sparse files, it is possible to have
    /// some blocks allocated and some others not yet allocated with the value 0 being used to
    /// indicate which blocks are not yet allocated for this file.
    block: [15]u32,

    /// Value used to indicate the file version (used by NFS).
    generation: u32,

    /// Value indicating the block number containing the extended attributes. In revision 0 this
    /// value is always 0.
    file_acl: u32,

    /// In revision 0 this 32bit value is always 0. In revision 1, for regular files this 32bit
    /// value contains the high 32 bits of the 64bit file size.
    ///
    /// Linux sets this value to 0 if the file is not a regular file (i.e. block devices,
    /// directories, etc). In theory, this value could be set to point to a block containing
    /// extended attributes of the directory or special file.
    dir_acl: u32,

    /// Value indicating the location of the file fragment.
    ///
    /// In Linux and GNU HURD, since fragments are unsupported this value is always 0. In Ext4
    /// this value is now marked as obsolete.
    faddr: u32,

    /// 96bit OS dependant structure.
    osd2: OSD2,

    pub fn is_dir(self: Inode) bool {
        return self.mode.file_format == Mode.FileFormat{ .EXT2_S_IFDIR = 1 };
    }
};

const DirEntry = struct {
    const FileType = enum(u8) {
        /// Unknown file type.
        EXT2_FT_UNKNOWN  = 0,
        /// Regular file.
        EXT2_FT_REG_FILE = 1,
        /// Directory file.
        EXT2_FT_DIR      = 2,
        /// Character device.
        EXT2_FT_CHRDEV   = 3,
        /// Block device.
        EXT2_FT_BLKDEV   = 4,
        /// Buffer file.
        EXT2_FT_FIFO     = 5,
        /// Socket file.
        EXT2_FT_SOCK     = 6,
        /// Symbolic link.
        EXT2_FT_SYMLINK  = 7,
    };

    /// Inode number of the file entry. A value of 0 indicate that the entry is not used.
    inode_id: u32,

    /// Displacement to the next directory entry from the start of the current directory entry.
    /// This field must have a value at least equal to the length of the current record.
    ///
    /// The directory entries must be aligned on 4 bytes boundaries and there cannot be any
    /// directory entry spanning multiple data blocks. If an entry cannot completely fit in one
    /// block, it must be pushed to the next data block and the rec_len of the previous entry
    /// properly adjusted.
    ///
    /// Since this value cannot be negative, when a file is removed the previous record within
    /// the block has to be modified to point to the next valid record within the block or to
    /// the end of the block when no other directory entry is present.
    ///
    /// If the first entry within the block is removed, a blank record will be created and point
    /// to the next directory entry or to the end of the block.
    rec_len: u16,

    /// Value indicating how many bytes of character data are contained in the name.
    ///
    /// This value must never be larger than rec_len - 8. If the directory entry name is updated
    /// and cannot fit in the existing directory entry, the entry may have to be relocated in a
    /// new directory entry of sufficient size and possibly stored in a new data block.
    name_len: u8,

    /// In revision 0, this field was the upper 8-bit of the then 16-bit name_len. Since all
    /// implementations still limited the file names to 255 characters this 8-bit value was
    /// always 0.
    ///
    /// This value must match the inode type defined in the related inode entry.
    file_type: FileType,

    name: []u8,

    pub fn init(gpa: Allocator, reader: *Reader) !DirEntry {
        // NOTE: ASSUMES THIS IS NOT REV 0!
        const inode_id = reader.read_u32();
        const rec_len = reader.read_u16();
        const name_len = reader.read_u8();
        const file_type: FileType = @enumFromInt(reader.read_u8());
        const name = try gpa.alloc(u8, name_len);
        const read = try reader.read(name);
        assert(read == name.len);

        const aligned = std.mem.alignForward(usize, reader.idx, 4) - reader.idx;
        try reader.seek_by(@intCast(aligned));

        return .{
            .inode_id = inode_id,
            .rec_len = rec_len,
            .name_len = name_len,
            .file_type = file_type,
            .name = name,
        };
    }

    pub fn deinit(self: DirEntry, gpa: Allocator) void {
        gpa.free(self.name);
    }

    pub fn free_entries(gpa: Allocator, entries: []DirEntry) void {
        if (entries.len > 0) {
            for (entries) |e| e.deinit(gpa);
        }
        gpa.free(entries);
    }
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

gpa: Allocator,
reader: Reader,
superblock: *Superblock,
bg_desc_table: BlockGroupDescriptorTable,
/// Should always be equal in len to bg_desc_table (one inode_table per group).
inode_tables: InodeTables,
n_groups: u32,
block_size: u32,
is_sparse: bool,

pub fn init(gpa: Allocator, reader: *Reader) Error!Self {
    const superblock = try parse_superblock(gpa, reader);
    errdefer gpa.destroy(superblock);

    if (superblock.magic != 0xef53) return error.NotEXT2;

    var self: Self = .{
        .gpa = gpa,
        .reader = reader.*,
        .superblock = superblock,
        .bg_desc_table = &.{},
        .inode_tables = undefined,
        .n_groups = superblock.n_groups(),
        .block_size = superblock.block_size(),
        .is_sparse = superblock.feature_ro_compat.EXT2_FEATURE_RO_COMPAT_SPARSE_SUPER,
    };

    self.bg_desc_table = try parse_bg_desc_table(&self);
    errdefer gpa.free(self.bg_desc_table);

    self.inode_tables = try InodeTables.init(gpa, @intCast(self.bg_desc_table.len), self.superblock.inodes_per_group);
    errdefer self.inode_tables.deinit();

    return self;
}

pub fn deinit(self: Self) void {
    self.gpa.destroy(self.superblock);
    self.gpa.free(self.bg_desc_table);
    self.inode_tables.deinit();
    self.reader.deinit();
}

pub fn get_size(self: Self) f64 {
    return @floatFromInt(self.superblock.blocks_count * self.block_size);
}

pub fn get_free_size(self: Self) f64 {
    return @floatFromInt(self.superblock.free_blocks_count * self.block_size);
}

fn parse_superblock(gpa: Allocator, reader: *Reader) Error!*Superblock {
    return try parse_superblock_at_offset(gpa, reader, SuperblockOffset);
}

fn parse_superblock_at_offset(gpa: Allocator, reader: *Reader, offset: usize) Error!*Superblock {
    const s = try gpa.create(Superblock);
    errdefer gpa.destroy(s);

    const dest = std.mem.asBytes(s);
    try reader.seek_to(offset);
    const read = try reader.read(dest);
    if (read != dest.len) return error.NotEnoughReadToParseSuperblock;

    return s;
}

fn parse_bg_desc_table(self: *Self) Error!BlockGroupDescriptorTable {
    const offset = self.block_group_desc_table_offset(0);
    return try self.parse_bg_desc_table_at_offset(offset);
}

fn parse_bg_desc_table_at_offset(self: *Self, offset: usize) Error!BlockGroupDescriptorTable {
    const table = try self.gpa.alloc(BlockGroupDescriptor, self.n_groups);
    errdefer self.gpa.free(table);

    try self.reader.seek_to(offset);
    const size = self.n_groups * @sizeOf(BlockGroupDescriptor);
    const dest: []u8 = @as([*]u8, @ptrCast(table))[0..size];
    const read = try self.reader.read(dest);
    if (read != size) return error.NotEnoughReadToBlockGroup;

    return table;
}

/// Should always be the next block over from superblock (check if filesystem has sparse copies).
fn block_group_desc_table_offset(self: Self, group_idx: usize) usize {
    if (group_idx == 0) return if (self.block_size == @sizeOf(Superblock)) self.block_size * 2 else self.block_size;
    const bg_offset = self.block_group_offset(group_idx);
    return bg_offset + self.block_size;
}

fn block_group_offset(self: Self, group_idx: usize) usize {
    if (group_idx == 0) return SuperblockOffset;
    return self.block_size * group_idx * self.superblock.blocks_per_group;
}

fn block_offset(self: Self, block_id: u32) usize {
    return self.block_size * block_id;
}

fn is_backup_block_group(self: Self, block_group_idx: usize) bool {
    if (!self.is_sparse) return true;
    if (block_group_idx == 1) return true;

    // power of 3, 5, 7
    if (is_power_of_base(block_group_idx, 3) or is_power_of_base(block_group_idx, 5) or is_power_of_base(block_group_idx, 7))
        return true;

    return false;
}

fn is_power_of_base(num: usize, base: usize) bool {
    var n = num;
    if (n == 0) return false;

    while (n % base == 0) {
        n /= base;
    }

    return n == 1;
}

const ROOT_INODE = 2;

fn list_files(self: Self, inode_id: u32) !void {
    _ = self;
    _ = inode_id;
}

fn get_used_blocks_in_group(self: Self, group_id: u32) u32 {
    assert(group_id < self.bg_desc_table.len);
    return self.superblock.blocks_per_group - self.bg_desc_table[group_id].free_blocks_count;
}

/// Caller owns the returned InodeTable and must free it.
fn get_inode_table(self: *Self, group_id: u32) !InodeTable {
    assert(group_id < self.bg_desc_table.len);
    const i_table = try self.gpa.alloc(Inode, self.superblock.inodes_per_group);
    errdefer self.gpa.free(i_table);

    const offset = (self.bg_desc_table[group_id].inode_table % self.superblock.blocks_per_group) * self.block_size;
    try self.reader.seek_to(offset);

    // TODO: maybe this can be somehow optimized, or maybe we shouldn't do this at all and
    // instead parse each Inode on demand.
    for (0..self.superblock.inodes_per_group) |inode_id| {
        const dest = std.mem.asBytes(&i_table[inode_id]);
        const read = try self.reader.read(dest);
        assert(read == dest.len);
        try self.reader.seek_by(self.superblock.inode_size - @as(u16, @intCast(read)));
    }

    return i_table;
}

fn get_inode(self: *Self, inode_id: u32) !Inode {
    const group_id = self.inode_tables.get_group_id_containing_inode_id(inode_id);
    if (!self.inode_tables.has_group_filled(group_id)) {
        const inode_table = try self.get_inode_table(group_id);
        errdefer self.gpa.free(inode_table);

        try self.inode_tables.fill_for_group(group_id, inode_table);
    }

    return self.inode_tables.get_inode(inode_id);
}

/// Caller owns and must free the returned memory. Asserts that passed inode is a dir.
fn read_dir_entries_with_inode_id(self: *Self, dir_inode_id: u32) ![]DirEntry {
    const inode = try self.get_inode(dir_inode_id);
    assert(inode.is_dir());

    const entries = try self.read_dir_entries_with_inode(inode);
    errdefer DirEntry.free_entries(self.gpa, entries);
    return entries;
}

/// Caller owns and must free the returned memory. Asserts that passed inode is a dir.
fn read_dir_entries_with_inode(self: *Self, dir_inode: Inode) ![]DirEntry {
    assert(dir_inode.is_dir());
    var entries = std.ArrayList(DirEntry).init(self.gpa);
    errdefer entries.deinit();

    for (dir_inode.block) |blk| {
        if (blk == 0) continue;
        var offset = self.block_offset(blk);
        const block_end_offset = offset + self.block_size;
        while (offset < block_end_offset) {
            try self.reader.seek_to(offset);
            const entry = try DirEntry.init(self.gpa, &self.reader);
            errdefer entry.deinit(self.gpa);
            try entries.append(entry);
            offset += entry.rec_len;
        }
    }

    return entries.toOwnedSlice();
}

fn count_bits_on(bytes: []u8) u32 {
    var count: u32 = 0;
    for (bytes) |b| count += @popCount(b);
    return count;
}


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
        const ext2 = try init(t_alloc, &reader);
        defer ext2.deinit();

        try t.expectEqual(0xef53, ext2.superblock.magic);
        try t.expectEqual(64000, ext2.superblock.inodes_count);
        try t.expectEqual(4096, ext2.superblock.block_size());
        const expected_ending = "zrec/mnt";
        const last_mounted = parse_cstr(&ext2.superblock.last_mounted);
        try t.expectEqualSlices(u8, expected_ending, last_mounted[last_mounted.len-expected_ending.len..]);
    }

    fn expectEqualSuperblock(expected: *Superblock, actual: *Superblock) error{TestExpectedEqual}!void {
        inline for(std.meta.fields(@TypeOf(expected.*))) |f| {
            comptime if (std.mem.eql(u8, f.name, "block_group_nr")) continue;
            try t.expectEqualDeep(@field(expected, f.name), @field(actual, f.name));
        }
    }

    test "has copies of the superblock and block group descriptor table" {
        var reader = try create_ext2_reader();
        defer reader.deinit();
        var ext2 = try init(t_alloc, &reader);
        defer ext2.deinit();

        const superblock = try parse_superblock_at_offset(ext2.gpa, &ext2.reader, ext2.block_group_offset(1));
        defer ext2.gpa.destroy(superblock);

        const bg_desc_table = try parse_bg_desc_table_at_offset(&ext2, ext2.block_group_desc_table_offset(1));
        defer ext2.gpa.free(bg_desc_table);

        for (2..ext2.n_groups + 1) |idx| {
            if (!ext2.is_backup_block_group(idx)) continue;

            const superblock_offset = ext2.block_group_offset(idx);
            const copy_superblock = try parse_superblock_at_offset(ext2.gpa, &ext2.reader, superblock_offset);
            defer ext2.gpa.destroy(copy_superblock);

            const bg_desc_table_offset = ext2.block_group_desc_table_offset(idx);
            const copy_bg_desc_table = try parse_bg_desc_table_at_offset(&ext2, bg_desc_table_offset);
            defer ext2.gpa.free(copy_bg_desc_table);

            try expectEqualSuperblock(superblock, copy_superblock);
            try t.expectEqualSlices(BlockGroupDescriptor, bg_desc_table, copy_bg_desc_table);
        }
    }

    test "block descriptor group table starts at the first block after superblock" {
        var reader = try create_ext2_reader();
        defer reader.deinit();
        const ext2 = try init(t_alloc, &reader);
        defer ext2.deinit();

        try t.expectEqual(8, ext2.bg_desc_table.len);
        try t.expectEqualDeep(
            BlockGroupDescriptor {
                .block_bitmap = 64,
                .inode_bitmap = 65,
                .inode_table = 66,
                .free_blocks_count = 30823,
                .free_inodes_count = 7989,
                .used_dirs_count = 2,
                .__padding = 4,
                .__reserved = [_]u8{ 0 } ** 12,
            },
            ext2.bg_desc_table[0],
        );
    }

    fn get_used_blocks_in_group_dumb(self: *Self, group_id: u32) !u32 {
        assert(group_id < self.bg_desc_table.len);
        const block_bitmap_off = self.bg_desc_table[group_id].block_bitmap * self.block_size;
        try self.reader.seek_to(block_bitmap_off);
        const mem = try self.gpa.alloc(u8, self.superblock.blocks_per_group / 8);
        defer self.gpa.free(mem);
        _ = try self.reader.read(mem);
        const used_blocks = count_bits_on(mem);
        return used_blocks;
    }

    test "used blocks in group match" {
        var reader = try create_ext2_reader();
        defer reader.deinit();
        var ext2: Self = try .init(t_alloc, &reader);
        defer ext2.deinit();

        try t.expectEqual(ext2.get_used_blocks_in_group(0), try get_used_blocks_in_group_dumb(&ext2, 0));
    }

    test "get ROOT_INODE" {
        var reader = try create_ext2_reader();
        defer reader.deinit();
        var ext2 = try init(t_alloc, &reader);
        defer ext2.deinit();

        const inode = try ext2.get_inode(ROOT_INODE);
        try t.expectEqual(0o40755, inode.mode.backing_integer());
        try t.expectEqual(4096, inode.size);
        try t.expectEqual(5, inode.links_count);
        try t.expectEqual(8, inode.blocks);
        try t.expectEqual(0, inode.flags.backing_integer());
        try t.expectEqual(2, inode.osd1);
        try t.expectEqualSlices(u32, &[_]u32{ 566 } ++ &[_]u32{ 0 } ** 14, &inode.block);
        try t.expectEqual(0, inode.generation);
        try t.expectEqual(0, inode.file_acl);
        try t.expectEqual(0, inode.dir_acl);
        try t.expectEqual(0, inode.faddr);
        try t.expectEqual(0, inode.osd2.backing_integer());
    }

    test "get inode_table" {
        var reader = try create_ext2_reader();
        defer reader.deinit();
        var ext2 = try init(t_alloc, &reader);
        defer ext2.deinit();

        const inode_table = try ext2.get_inode_table(0);
        defer ext2.gpa.free(inode_table);

        try t.expectEqual(ext2.superblock.inodes_per_group, inode_table.len);
    }

    test "read root dir" {
        var reader = try create_ext2_reader();
        defer reader.deinit();
        var ext2 = try init(t_alloc, &reader);
        defer ext2.deinit();

        const entries = try ext2.read_dir_entries_with_inode_id(ROOT_INODE);
        defer DirEntry.free_entries(ext2.gpa, entries);
        try t.expectEqual(5, entries.len);
        const expected_names: []const []const u8 = &.{ ".", "..", "lost+found", "jpgs", "pngs" };
        for (expected_names, entries) |expected_name, entry| {
            try t.expectEqualSlices(u8, expected_name, entry.name);
        }
    }

    test "tree" {

    }
};
