const std = @import("std");
const lib = @import("../lib.zig");
const Reader = lib.Reader;
const Allocator = std.mem.Allocator;

alloc: Allocator,
reader: Reader,

vbr: VBR,

const NTFS = @This();

/// Volume Boot Record
const VBR = extern struct {
    jump_instruction:          [3]u8   align(1),
    oem_id:                    [8]u8   align(1),
    bytes_per_sector:          u16     align(1),
    sectors_per_cluster:       u8      align(1),
    reserved_sectors:          u16     align(1),
    always_zero1:              [3]u8   align(1),
    always_zero2:              u16     align(1),
    media_descriptor:          u8      align(1),
    always_zero3:              u16     align(1),
    sectors_per_track:         u16     align(1),
    number_of_heads:           u16     align(1),
    hidden_sectors:            u32     align(1),
    always_zero4:              u32     align(1),
    not_used1:                 u32     align(1),
    total_sectors:             u64     align(1),
    mft_lcn:                   u64     align(1),
    mftmirr_lcn:               u64     align(1),
    clusters_per_mft_record:   i8      align(1),
    not_used2:                 [3]u8   align(1),
    clusters_per_index_buffer: i8      align(1),
    not_used3:                 [3]u8   align(1),
    volume_serial_number:      u64     align(1),
    checksum:                  u32     align(1),
    boot_code:                 [426]u8 align(1),
    signature:                 u16     align(1),

    const SIGNATURE = 0x55AA;
    const OEM_ID: [:0]const u8 = "NTFS    ";
    const Self = @This();

    pub fn init(reader: *Reader) !Self {
        var self = std.mem.zeroInit(Self, .{});
        const dst = std.mem.asBytes(&self);

        try reader.seek_to(0);
        const bytes_read = try reader.read_struct_endian(VBR, &self, .little);
        if (bytes_read != dst.len) return error.ReadTooLittleForVBR;

        if (self.signature != SIGNATURE)            return error.NotNTFSWrongSignature;
        if (!std.mem.eql(u8, &self.oem_id, OEM_ID)) return error.NotNTFSBadOEM_ID;

        return self;
    }
};

pub const Error =
    Allocator.Error
    || std.fs.File.ReadError
    || error{
        NotNTFSWrongSignature,
        NotNTFSBadOEM_ID,
        InvalidJmpBoot,
        UnimplementedCurrently,
        ReadTooLittleForVBR
    };

pub fn estimate(alloc: Allocator, reader: *Reader) f32 {
    _ = alloc;
    _ = reader;
    return 0;
}

pub fn init(alloc: Allocator, reader: *Reader) Error!NTFS {
    return .{
        .alloc = alloc,
        .reader = reader.*,
        .vbr = try .init(reader),
    };
}

pub fn deinit(self: *NTFS) void {
    self.reader.deinit();
    self.* = undefined;
}

pub fn get_size(self: NTFS) f64 {
    _ = self;
    unreachable;
}

pub fn get_free_size(self: NTFS) f64 {
    _ = self;
    unreachable;
}

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    const t = std.testing;
    const PATH = "./filesystems/ntfs_filesystem.img";
    const t_utils = @import("testing_utils.zig");
    const t_alloc = std.testing.allocator;

    fn create_ntfs() !NTFS {
        const reader = try create_reader();
        return try .init(t_alloc, &reader);
    }

    fn create_reader() !Reader {
        const f = try std.fs.cwd().openFile(PATH, .{});
        return try Reader.init(&f);
    }

    test "parsing VBR" {
        var reader = try create_reader();
        defer reader.deinit();

        const vbr: VBR = try .init(&reader);
        try t.expectEqual(VBR.SIGNATURE, vbr.signature);
    }
};
