const std = @import("std");
const lib = @import("../lib.zig");
const Reader = lib.Reader;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.fat);

pub const FAT32 = struct {
    alloc: Allocator,
    reader: *Reader,
    buf: []u8,
    filesystem: []u8,
    boot_sector: BootSector,
    bios_parameter_block: BIOSParameterBlock,
    fat: []FileAllocationTable,

    const Self = @This();
    const SECTOR_SIZE = 512;
    const BPB_START_OFFSET = 11;
    const BPB_END_OFFSET = 64;
    const SIZE_OF_BPB = BPB_END_OFFSET - BPB_START_OFFSET;

    pub const Error =
        Allocator.Error
        || std.fs.File.ReadError
        || error{ NotFAT32, InvalidJmpBoot, FileTooSmall };

    pub fn init(alloc: Allocator, buf: []u8, reader: *Reader) Error!Self {
        const read = try reader.read(buf);
        // should at least have 9 sectors of 512 bytes each
        if (read <= 9*SECTOR_SIZE) return error.FileTooSmall;
        const mem = buf[0..read];

        const bs = try parse_boot_sector(mem[0..BPB_START_OFFSET], mem[BPB_END_OFFSET..]);
        const bpb = parse_bios_parameter_block(mem[BPB_START_OFFSET..64]);
        const root_dir_sectors = ((bpb.root_entries_count * 32) + (bpb.bytes_per_sector - 1)) / bpb.bytes_per_sector;
        const fat_size = bpb.fat_size_32;
        const total_sectors = bpb.total_sectors_32;
        const data_sectors = total_sectors - (bpb.reserved_sector_count + (bpb.num_of_fats * fat_size) + root_dir_sectors);
        const count_of_clusters = data_sectors / bpb.sectors_per_cluster;
        if (root_dir_sectors != 0 or count_of_clusters < 65526) return error.NotFAT32;

        var self: Self = .{
            .alloc = alloc,
            .reader = reader,
            .buf = buf[0..],
            .filesystem = mem,
            .boot_sector = bs,
            .bios_parameter_block = bpb,
            .fat = undefined,
        };
        self.fat = try self.parse_fat();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.buf);
        self.* = undefined;
    }

    pub fn calc_size(self: Self) f64 {
        const bpb = &self.bios_parameter_block;
        const root_dir_sectors = ((bpb.root_entries_count * 32) + (bpb.bytes_per_sector - 1)) / bpb.bytes_per_sector;
        const fat_size = bpb.fat_size_32;
        const total_sectors = bpb.total_sectors_32;
        const data_sectors = total_sectors - (bpb.reserved_sector_count + (bpb.num_of_fats * fat_size) + root_dir_sectors);
        const count_of_clusters = data_sectors / bpb.sectors_per_cluster;
        const size = bpb.sectors_per_cluster * count_of_clusters * bpb.bytes_per_sector;
        return @floatFromInt(size);
    }

    fn parse_fat(self: Self) ![]FileAllocationTable {
        var fat = std.ArrayList(FileAllocationTable).init(self.alloc);
        const bpb = &self.bios_parameter_block;
        const s = self.find_first_sector_of_cluster(bpb.root_cluster);
        log.debug("first sector of root cluster: {d}", .{s});
        return try fat.toOwnedSlice();
    }

    fn find_first_sector_of_cluster(self: Self, cluster_num: usize) usize {
        const bpb = &self.bios_parameter_block;
        const root_dir_sectors = ((bpb.root_entries_count * 32) + (bpb.bytes_per_sector - 1)) / bpb.bytes_per_sector;
        const first_data_sector = bpb.reserved_sector_count + (bpb.num_of_fats * bpb.fat_size_32) + root_dir_sectors;
        const first_sector_of_cluster = ((cluster_num - 2) * bpb.sectors_per_cluster) + first_data_sector;
        return first_sector_of_cluster * bpb.bytes_per_sector;

    }

    fn parse_boot_sector(first_part: *[11]u8, second_part: []u8) !BootSector {
        const jmp_boot = first_part[0..3];
        if ((jmp_boot[0] != 0xEB or jmp_boot[2] != 0x90) and jmp_boot[0] != 0xE9) return error.InvalidJmpBoot;

        // TODO: add all validation
        return BootSector {
            .jmp_boot = jmp_boot,
            .oem_name = first_part[3..],
            .drive_number = second_part[0..1],
            .reserved_1 = second_part[1..2],
            .boot_signature = second_part[2..3],
            .volume_serial_number = second_part[3..7],
            .volume_label = second_part[7..18],
            .file_system_type = second_part[18..26],
            .reserved_2 = second_part[26..446],
            .signature_word = second_part[446..448],
        };
    }

    fn parse_bios_parameter_block(mem: *[SIZE_OF_BPB]u8) BIOSParameterBlock {
        return BIOSParameterBlock {
            .bytes_per_sector = read_u16(mem[0..2]),
            .sectors_per_cluster = mem[2],
            .reserved_sector_count = read_u16(mem[3..5]),
            .num_of_fats = mem[5],
            .root_entries_count = read_u16(mem[6..8]),
            .total_sectors_16 = read_u16(mem[8..10]),
            .media = mem[10],
            .fat_size_16 = read_u16(mem[11..13]),
            .sectors_per_track = read_u16(mem[13..15]),
            .num_of_heads = read_u16(mem[15..17]),
            .hidden_sectors = read_u32(mem[17..21]),
            .total_sectors_32 = read_u32(mem[21..25]),
            .fat_size_32 = read_u32(mem[25..29]),
            .extra_flags = mem[29..31],
            .filesystem_version = mem[31..33],
            .root_cluster = read_u32(mem[33..37]),
            .fsinfo_sector_number = read_u16(mem[37..39]),
            .backup_boot_sector_number = read_u16(mem[39..41]),
            .reserved = mem[41..41+12],
        };
    }

    fn read_u16(mem: *[2]u8) u16 {
        return std.mem.readInt(u16, mem, .little);
    }

    fn read_u32(mem: *[4]u8) u32 {
        return std.mem.readInt(u32, mem, .little);
    }

    pub fn get_backup_boot_sector(self: Self) !BootSector {
        const mem_part1 = self.buf[6*SECTOR_SIZE..6*SECTOR_SIZE + BPB_START_OFFSET];
        const mem_part2 = self.buf[6*SECTOR_SIZE + BPB_END_OFFSET..];
        return try parse_boot_sector(mem_part1, mem_part2);
    }

    pub fn get_backup_bios_parameter_block(self: Self) BIOSParameterBlock {
        const mem = self.buf[6*SECTOR_SIZE + BPB_START_OFFSET..6*SECTOR_SIZE + BPB_START_OFFSET + SIZE_OF_BPB];
        return parse_bios_parameter_block(mem);
    }

    /// All fields are sequential on disk from byte offset 0
    pub const BootSector = struct {
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
        jmp_boot: *[3]u8,
        oem_name: *[8]u8,

        /// IMPORTANT: FIELDS CONTINUE AT BYTE OFFSET 64 FOR FAT32
        drive_number: *[1]u8,
        reserved_1: *[1]u8,
        boot_signature: *[1]u8,
        volume_serial_number: *[4]u8,
        volume_label: *[11]u8,
        file_system_type: *[8]u8,
        reserved_2: *[420]u8,
        signature_word: *[2]u8,
        // all remaining bytes in the sector from byte offset 512 should be 0x00
        // if bytes_per_sector > 512
    };

    /// Fields start from byte offset 11
    pub const BIOSParameterBlock = struct {
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

        extra_flags: *[2]u8,

        /// Must be 0, but high byte is major revision number.
        /// Low byte is minor revision number.
        filesystem_version: *[2]u8,

        root_cluster: u32,

        fsinfo_sector_number: u16,

        backup_boot_sector_number: u16,

        reserved: *[12]u8,
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
};

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    const FilesystemHandler = lib.FilesystemHandler;
    const testing = std.testing;
    const t_alloc = testing.allocator;
    const FAT32_PATH = "./filesystems/fat32_filesystem.img";
    const expect = testing.expect;
    const tlog = std.log.scoped(.fat_tests);

    fn custom_slice_and_int_eql(a: anytype, b: @TypeOf(a)) bool {
        const T = @TypeOf(a);

        inline for (@typeInfo(T).@"struct".fields) |field_info| {
            const f_name = field_info.name;
            const f_a = @field(a, f_name);
            const f_b = @field(b, f_name);
            const f_info = @typeInfo(@TypeOf(f_a));
            // std.debug.print("type tag: {s}\n", .{@tagName(f_info)});
            // @compileLog("type tag: " ++ @tagName(f_info));

            switch (f_info) {
                .pointer => {
                    if (!std.mem.eql(u8, f_a, f_b)) {
                        tlog.debug("a: {any} and b: {any} dont match on {s}", .{f_a, f_b, f_name});
                        return false;
                    }
                },
                .int => {
                    if (f_a != f_b) {
                        tlog.debug("a: {any} and b: {any} dont match on {s}", .{f_a, f_b, f_name});
                        return false;
                    }
                },
                else => unreachable
            }
        }
        return true;
    }

    test "fresh fat32 is read as expected with all backup info in sector 6" {
        testing.log_level = .debug;
        var fs_handler = try FilesystemHandler.init(t_alloc, FAT32_PATH);
        var fs = try fs_handler.determine_filesystem();
        defer fs_handler.deinit();
        defer fs.deinit();

        switch (fs) {
            .fat32 => |fat32| {
                const bkp_bs = try fat32.get_backup_boot_sector();
                const bkp_bpb = fat32.get_backup_bios_parameter_block();
                try expect(custom_slice_and_int_eql(fat32.boot_sector, bkp_bs));
                try expect(custom_slice_and_int_eql(fat32.bios_parameter_block, bkp_bpb));
            },
            else => unreachable
        }
    }

    test "read root cluster" {
    }
};
