const std = @import("std");
const lib = @import("../lib.zig");
const Reader = lib.Reader;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.fat);
const set_fields_alignment = lib.set_fields_alignment;

fn join(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    var res: [a.len + b.len]std.meta.Child(@TypeOf(a)) = undefined;
    @memcpy(res[0..a.len], a);
    @memcpy(res[a.len..], b);
    return &res;
}

fn BootSectorImpl() type {
    const fields = std.meta.fields;
    var fs = join(fields(BS_Part1), fields(BIOSParameterBlock));
    fs = join(fs, fields(BS_Part2));
    // set all fields alignment to 1 (get rid of padding like #pragma pack)
    fs = set_fields_alignment(fs, 1);

    const declarations = std.meta.declarations;
    var decls = join(declarations(BS_Part1), declarations(BIOSParameterBlock));
    decls = join(decls, declarations(BS_Part2));

    return @Type(.{
        .@"struct" = .{
            .layout = .@"extern",
            .backing_integer = null,
            .fields = fs,
            .decls = decls,
            .is_tuple = false,
        }
    });
}

const BS_Part1 = extern struct {
    /// Starts at offset: 0
    ///
    /// What this forms is a three-byte Intel x86
    /// unconditional branch (jump) instruction that jumps
    /// to the start of the operating system bootstrap code.
    /// This code typically occupies the rest of sector 0 of
    /// the volume following the BPB and possibly other
    /// sectors.
    ///
    /// Two valid options for this field are:
    ///
    /// jmp_boot[0] = 0xEB, jmp_boot[1] = 0x??,
    /// jmp_boot[2] = 0x90
    /// and
    /// jmp_boot[0] = 0xE9, jmp_boot[1] = 0x??,
    /// jmp_boot[2] = 0x??
    jmp_boot: [3]u8,
    oem_name: [8]u8,
};

/// Fields start from byte offset 11
const BIOSParameterBlock = extern struct {
    /// Count of bytes per sector. This value may take on
    /// only the following values: 512, 1024, 2048 or 4096
    bytes_per_sector: u16,

    /// Number of sectors per allocation unit. This value
    /// must be a power of 2 that is greater than 0. The
    /// legal values are 1, 2, 4, 8, 16, 32, 64, and 128.
    sectors_per_cluster: u8,

    /// Number of reserved sectors in the reserved region
    /// of the volume starting at the first sector of the
    /// volume. This field is used to align the start of the
    /// data area to integral multiples of the cluster size
    /// with respect to the start of the partition/media.
    ///
    /// This field must not be 0 and can be any non-zero
    /// value.
    ///
    /// This field should typically be used to align the start
    /// of the data area (cluster #2) to the desired
    /// alignment unit, typically cluster size.
    reserved_sector_count: u16,

    /// The count of file allocation tables (FATs) on the
    /// volume. A value of 2 is recommended although a
    /// value of 1 is acceptable.
    num_of_fats: u8,

    /// For FAT12 and FAT16 volumes, this field contains
    /// the count of 32-byte directory entries in the root
    /// directory. For FAT32 volumes, this field must be set
    /// to 0. For FAT12 and FAT16 volumes, this value
    /// should always specify a count that when multiplied
    /// by 32 results in an even multiple of bytes_per_sector.
    root_entries_count: u16,

    /// This field is the old 16-bit total count of sectors on
    /// the volume. This count includes the count of all
    /// sectors in all four regions of the volume.
    /// This field can be 0; if it is 0, then BPB_TotSec32
    /// must be non-zero. For FAT32 volumes, this field
    /// must be 0.
    /// For FAT12 and FAT16 volumes, this field contains
    /// the sector count, and BPB_TotSec32 is 0 if the
    /// total sector count “fits” (is less than 0x10000)
    total_sectors_16: u16,

    /// The legal values for this field are 0xF0, 0xF8, 0xF9,
    /// 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, and 0xFF.
    /// 0xF8 is the standard value for “fixed” (non-removable)
    /// media. For removable media, 0xF0 is
    /// frequently used.
    media: u8,

    fat_size_16: u16,

    sectors_per_track: u16,

    num_of_heads: u16,

    hidden_sectors: u32,

    total_sectors_32: u32,

    fat_size_32: u32,

    extra_flags: u16,

    /// Must be 0, but high byte is major revision number.
    /// Low byte is minor revision number.
    filesystem_version: u16,

    root_cluster: u32,

    fsinfo_sector_number: u16,

    backup_boot_sector_number: u16,

    reserved: [12]u8,
};

const BS_Part2 = extern struct {
    /// IMPORTANT: FIELDS CONTINUE AT BYTE OFFSET 64 FOR FAT32
    drive_number: u8,
    reserved_1: u8,
    boot_signature: u8,
    volume_serial_number: u32,
    volume_label: [11]u8,
    file_system_type: [8]u8,
    reserved_2: [420]u8,
    signature_word: [2]u8,
    // all remaining bytes in the sector from byte offset 512 should be 0x00
    // if bytes_per_sector > 512
};

pub const FAT32Dir = extern struct {
    /// 'Short' file name limited to 11 character
    name: [11]u8,

    /// The upper two bits of the attribute byte are reserved
    /// and must always be set to 0 when a file is created.
    /// These bits are not interpreted.
    attr: Attributes,

    /// Reserved. Must be set to 0.
    ntres: u8,

    /// Component of the file creation time. Count of
    /// tenths of a second. Valid range is:
    /// 0 <= crt_time_tenth <= 199
    crt_time_tenth: u8,

    /// Creation time. Granularity is 2 seconds.
    crt_time: u16,

    /// Creation date.
    crt_date: u16,

    /// Last access date. Last access is defined as a
    /// read or write operation performed on the
    /// file/directory described by this entry.
    lst_acc_date: u16,

    /// High word of first data cluster number for
    /// file/directory described by this entry.
    fst_clus_hi: u16,

    /// Last modification (write) time.
    wrt_time: u16,

    /// Last modification (write) date.
    wrt_date: u16,

    /// Low word of first data cluster number for
    /// file/directory described by this entry.
    fst_clus_lo: u16,

    /// 32-bit quantity containing size in bytes of
    /// file/directory described by this entry.
    file_size: u32,

    pub const Attributes = enum(u8) {
        READ_ONLY = 0x01,
        HIDDEN    = 0x02,
        SYSTEM    = 0x04,
        VOLUME_ID = 0x08,
        DIRECTORY = 0x10,
        ARCHIVE   = 0x20,
        LONG_NAME = 0x01 | 0x02 | 0x04 | 0x08,
    };
};

pub const FAT32State = union(enum) {
    /// 0x0000000
    free,

    /// holds cluster number of the next used cluster
    /// for allocated file TODO: verify if true
    ///
    /// 0x0000002 to MAX, MAX = Maximum Valid Cluster Number
    allocated: usize,

    /// (MAX + 1) to 0xFFFFFF6
    reserved,

    /// 0xFFFFFF7
    bad,

    /// could be interpreted as EOF
    ///
    /// 0xFFFFFF8 to 0xFFFFFFE
    reserved_dont_use,

    /// 0xFFFFFFFF
    eof,
};

pub const FileAllocationTable = struct {
    state: FAT32State,
};

/// All fields are sequential on disk from byte offset 0
pub const BootSector = BootSectorImpl();

gpa: Allocator,
reader: *Reader,
buf: []u8,
filesystem: []u8,
boot_sector: *BootSector,
count_of_clusters: usize,
fat: []FileAllocationTable,

const Self = @This();
const SECTOR_SIZE = 512;
const BPB_START_OFFSET = 11;
const BPB_END_OFFSET = 64;
const SIZE_OF_BPB = BPB_END_OFFSET - BPB_START_OFFSET;
const FIRST_PART_SIZE = 3 + 8;
const SECOND_PART_OFFSET = 64;
const SECOND_PART_SIZE = 448;
const INPUT_MEM_SIZE = SECOND_PART_OFFSET + SECOND_PART_SIZE;

pub const Error =
    Allocator.Error
    || std.fs.File.ReadError
    || error{
        NotFAT32,
        InvalidJmpBoot,
        FileTooSmall,
        TooLittleMemoryPassedForBootSecParsing,
        TooLittleMemoryPassedForBIOSParamBlockParsing,
    };

pub fn init(gpa: Allocator, reader: *Reader) Error!Self {
    const buf = try gpa.alloc(u8, 10000);
    errdefer gpa.free(buf);
    const read = try reader.read(buf);
    // should at least have 9 sectors of 512 bytes each
    if (read <= 9*SECTOR_SIZE) return error.FileTooSmall;
    const mem = buf[0..read];

    const bs = try parse_boot_sector(gpa, mem[0..@sizeOf(BootSector)]);
    errdefer gpa.destroy(bs);

    const root_dir_sectors = ((bs.root_entries_count * 32) + (bs.bytes_per_sector - 1)) / bs.bytes_per_sector;
    const fat_size = bs.fat_size_32;
    const total_sectors = bs.total_sectors_32;
    const data_sectors = total_sectors - (bs.reserved_sector_count + (bs.num_of_fats * fat_size) + root_dir_sectors);
    const count_of_clusters = data_sectors / bs.sectors_per_cluster;
    if (root_dir_sectors != 0 or count_of_clusters < 65526) return error.NotFAT32;

    var self: Self = .{
        .gpa = gpa,
        .reader = reader,
        .buf = buf[0..],
        .filesystem = mem,
        .boot_sector = bs,
        .count_of_clusters = count_of_clusters,
        .fat = undefined,
    };
    self.fat = try self.parse_fat();
    return self;
}

pub fn deinit(self: *Self) void {
    self.gpa.free(self.buf);
    self.gpa.destroy(self.boot_sector);
    self.* = undefined;
}

fn parse_boot_sector(gpa: Allocator, mem: []u8) !*BootSector {
    if (mem.len < SECOND_PART_OFFSET + SECOND_PART_SIZE)
        return error.TooLittleMemoryPassedForBootSecParsing;
    const bs = try gpa.create(BootSector);
    errdefer gpa.destroy(bs);
    const dst = std.mem.asBytes(bs);
    @memcpy(dst,  mem[0..dst.len]);
    const jmp_boot = bs.jmp_boot;
    if ((jmp_boot[0] != 0xEB or jmp_boot[2] != 0x90) and jmp_boot[0] != 0xE9) return error.InvalidJmpBoot;

    // TODO: add all validation
    return bs;
}

fn parse_fat(self: Self) ![]FileAllocationTable {
    var fat = std.ArrayList(FileAllocationTable).init(self.gpa);
    const bs = self.boot_sector;
    const s = self.find_first_sector_of_cluster(bs.root_cluster);
    _ = s;
    // log.debug("first sector of root cluster: {d}", .{s});
    return try fat.toOwnedSlice();
}

fn find_first_sector_of_cluster(self: Self, cluster_num: usize) usize {
    const bs = self.boot_sector;
    const root_dir_sectors = ((bs.root_entries_count * 32) + (bs.bytes_per_sector - 1)) / bs.bytes_per_sector;
    const first_data_sector = bs.reserved_sector_count + (bs.num_of_fats * bs.fat_size_32) + root_dir_sectors;
    const first_sector_of_cluster = ((cluster_num - 2) * bs.sectors_per_cluster) + first_data_sector;
    return first_sector_of_cluster * bs.bytes_per_sector;

}

pub fn get_backup_boot_sector(self: Self) !*BootSector {
    const mem = self.buf[6*SECTOR_SIZE..6*SECTOR_SIZE + INPUT_MEM_SIZE];
    return try parse_boot_sector(self.gpa, mem);
}

pub fn get_size(self: Self) f64 {
    const bs = self.boot_sector;
    const root_dir_sectors = ((bs.root_entries_count * 32) + (bs.bytes_per_sector - 1)) / bs.bytes_per_sector;
    const fat_size = bs.fat_size_32;
    const total_sectors = bs.total_sectors_32;
    const data_sectors = total_sectors - (bs.reserved_sector_count + (bs.num_of_fats * fat_size) + root_dir_sectors);
    const count_of_clusters = data_sectors / bs.sectors_per_cluster;
    const s = bs.sectors_per_cluster * count_of_clusters * bs.bytes_per_sector;
    return @floatFromInt(s);
}

pub fn get_free_size(self: Self) f64 {
    _ = self;
    unreachable;
}

/// caller has to call destroy on the resulting pointer
pub fn get_root_dir(self: Self) !*FAT32Dir {
    return try self.get_dir(self.boot_sector.root_cluster);
}

pub fn get_dir(self: Self, cluster_number: usize) !*FAT32Dir {
    assert(cluster_number >= self.boot_sector.root_cluster);
    try self.reader.seek_to(cluster_number);
    const dir = try self.gpa.create(FAT32Dir);
    errdefer self.gpa.destroy(dir);
    const size = @sizeOf(FAT32Dir);
    const buf: []u8 = @as([*]u8, @ptrCast(dir))[0..size];
    const read = try self.reader.read(buf);
    if (read != size) return error.DidntReadEnoughBytesForRootDir;
    return dir;
}

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    const FilesystemHandler = lib.FilesystemHandler;
    const t = std.testing;
    const t_alloc = t.allocator;
    const FAT32_PATH = "./filesystems/fat32_filesystem.img";
    const tlog = std.log.scoped(.fat_tests);

    test "fresh fat32 is read as expected with all backup info in sector 6" {
        var fs_handler: FilesystemHandler = try .init(t_alloc, FAT32_PATH);
        var fs = try fs_handler.determine_filesystem();
        defer fs_handler.deinit();
        defer fs.deinit();

        const fat32 = &fs.fat32;
        const bkp_bs = try fat32.get_backup_boot_sector();
        defer t_alloc.destroy(bkp_bs);
        const bs1_mem: []u8 = @as([*]u8, @ptrCast(fat32.boot_sector))[0..@sizeOf(BootSector)];
        const bs2_mem: []u8 = @as([*]u8, @ptrCast(bkp_bs))[0..@sizeOf(BootSector)];
        try t.expectEqualSlices(u8, bs1_mem, bs2_mem);
        try t.expectEqualDeep(fat32.boot_sector.*, bkp_bs.*);
    }

    test "read root cluster" {
        var fs_handler: FilesystemHandler = try .init(t_alloc, FAT32_PATH);
        defer fs_handler.deinit();
        var fs = try fs_handler.determine_filesystem();
        defer fs.deinit();

        const fat = fs.fat32;
        const root_dir = try fat.get_root_dir();
        defer fs_handler.alloc.destroy(root_dir);

        try t.expect(std.mem.containsAtLeast(u8, &root_dir.name, 1, "mkfs.fat"));
        // NOTE: documentation says this should always be 0, for some reason its 32
        try t.expectEqual(32, root_dir.ntres);
        try t.expectEqual(1069875200, root_dir.file_size);
        try t.expectEqual(0, root_dir.fst_clus_hi);
        try t.expectEqual(0, root_dir.fst_clus_hi);
        try t.expectEqual(0, root_dir.fst_clus_lo);
        try t.expectEqual(.VOLUME_ID, root_dir.attr);

        // TODO: to continue fat32 start here: figure out how to read other cluster information (had no idea on how to navigate
        // to next cluster because in read dir we seek_to(2) essentially which I don't understand at all)
        // for (fat.boot_sector.root_cluster+1..fat.count_of_clusters, 0..) |clus_idx, counter| {
        //     if (counter > 5) break;
        //     const dir = try fat.get_dir(clus_idx);
        //     lib.print(dir, null);
        // }
    }
};
