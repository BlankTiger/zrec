const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const win = std.os.windows;
const log = std.log.scoped(.reader);

pub const ReadReader = struct {
    file: *const std.fs.File,
    reader: std.fs.File.Reader,

    // BUG: buffered reader was causing seeking to fail because of the internal buffering
    // maybe write a custom buffered reader?
    // pub const BufferedReader = std.io.BufferedReader(4096, std.fs.File.Reader);
    // reader: BufferedReader,

    const Self = @This();
    const Error = std.fs.File.ReadError || std.fs.File.SeekError;

    pub fn init(file: *const std.fs.File) Error!Self {
        const reader = file.reader();
        return Self { .file = file, .reader = reader };
    }

    pub fn deinit(self: Self) void {
        self.file.close();
    }

    pub fn read(self: *Self, dest: []u8) !usize {
        return self.reader.read(dest);
    }

    pub fn seek_by(self: *Self, offset: i64) !void {
        return self.file.seekBy(offset);
    }
};


// TODO: make it work on windows, possibly a problem:
// https://learn.microsoft.com/en-us/windows/win32/memory/creating-a-file-mapping-object
// The size of a file mapping object that is backed by a named file is limited by disk space. The size of a file view is limited to the largest available contiguous block of unreserved virtual memory. This is at most 2 GB minus the virtual memory already reserved by the process.
// on linux I think that there is no such limit as 2 GB, needs more testing too
//
// extern "kernel32" fn CreateFileMappingA(
//     hFile: win.HANDLE,
//     lpFileMappingAttributes: *const std.os.windows.SECURITY_ATTRIBUTES,
//     flProtect: win.DWORD,
//     dwMaximumSizeHigh: win.DWORD,
//     dwMaximumSizeLow: win.DWORD,
//     lpName: win.LPCSTR,
// ) win.HANDLE;
//
// fn mmap(
//     ptr: ?[*]align(std.heap.pageSize()) u8,
//     length: usize,
//     prot: u32,
//     flags: posix.system.MAP,
//     fd: posix.fd_t,
//     offset: u64,
// ) posix.MMapError!MmapReader.MemT {
//     _ = offset;
//     _ = fd;
//     _ = flags;
//     _ = prot;
//     _ = length;
//     _ = ptr;
//
//     switch (builtin.os.tag) {
//         .linux => {},
//         .windows => {},
//         else => unreachable,
//     }
// }

// TODO: implement the std io reader interface to get a lot of functionality for free
pub const MmapReader = struct {
    pub const MemT = []align(std.heap.pageSize()) u8;

    mem: MemT,
    mem_shared: bool = false,
    idx: usize = 0,

    const Self = @This();
    const Error = posix.MMapError || posix.FStatError;

    /// `file` is closed internally and should be passed in opened.
    pub fn init(file: *const std.fs.File) Error!Self {
        defer file.close();
        const fd = file.handle;
        const stats = try posix.fstat(fd);
        const len: usize = @intCast(stats.size);
        const mem = switch (builtin.os.tag) {
            .linux => try posix.mmap(null, len, posix.PROT.READ, .{ .TYPE = .SHARED }, fd, 0),
            .windows => try win.mmap(),
            else => unreachable,
        };
        return .{ .mem = mem };
    }

    pub fn init_with_mem(mem: MemT) Self {
        return .{
            .mem = mem,
            .mem_shared = true,
        };
    }

    pub fn deinit(self: Self) void {
        if (!self.mem_shared) _ = posix.munmap(self.mem);
    }

    pub fn read(self: *Self, dest: []u8) !usize {
        if (self.idx > self.mem.len) return 0;

        if (self.mem.len < self.idx + dest.len) {
            const bytes_left = self.mem.len - self.idx;
            @memcpy(dest[0..bytes_left], self.mem[self.idx..self.idx+bytes_left]);
            self.idx += bytes_left;
            return bytes_left;
        }

        @memcpy(dest, self.mem[self.idx..self.idx+dest.len]);
        self.idx += dest.len;
        return dest.len;
    }

    pub fn read_u32(self: *Self) u32 {
        const idx = self.idx;
        const bytes: [4]u8 = .{ self.mem[idx], self.mem[idx+1], self.mem[idx+2], self.mem[idx+3] };
        self.idx += 4;
        return std.mem.readInt(u32, &bytes, .little);
    }

    pub fn read_u16(self: *Self) u16 {
        const idx = self.idx;
        const bytes: [2]u8 = .{ self.mem[idx], self.mem[idx+1] };
        self.idx += 2;
        return std.mem.readInt(u16, &bytes, .little);
    }

    pub fn read_u8(self: *Self) u8 {
        self.idx += 1;
        return self.mem[self.idx-1];
    }

    pub fn seek_by(self: *Self, offset: i64) !void {
        const _idx: i64 = @intCast(self.idx);
        if (_idx + offset < 0) self.idx = 0;
        if (_idx + offset > self.mem.len) self.idx = self.mem.len;
        self.idx = @intCast(_idx + offset);
    }

    pub fn seek_to(self: *Self, idx: usize) !void {
        self.idx = idx;
    }
};

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    const t = std.testing;
    const t_utils = @import("testing_utils.zig");

    test "MmapReader read full fat32 image, result should be equivalent to reading via read system calls, seeking works too" {
        try t_utils.skip_slow_test();

        const path = "filesystems/fat32_filesystem.img";
        var read_call_buf: [512]u8 = undefined;
        var mmap_call_buf: [512]u8 = undefined;
        const f_read = try std.fs.cwd().openFile(path, .{});
        const f_mmap = try std.fs.cwd().openFile(path, .{});
        var reader_read = try ReadReader.init(&f_read);
        defer reader_read.deinit();
        var reader_mmap = try MmapReader.init(&f_mmap);
        defer reader_mmap.deinit();

        var bytes_read_read = try reader_read.read(&read_call_buf);
        var bytes_read_mmap = try reader_mmap.read(&mmap_call_buf);
        try t.expectEqual(bytes_read_read, bytes_read_mmap);
        try t.expectEqualSlices(u8, &read_call_buf, &mmap_call_buf);
        while (bytes_read_read > 0) {
            bytes_read_read = try reader_read.read(&read_call_buf);
            bytes_read_mmap = try reader_mmap.read(&mmap_call_buf);
            try t.expectEqual(bytes_read_read, bytes_read_mmap);
            try t.expectEqualSlices(u8, &read_call_buf, &mmap_call_buf);
        }

        try reader_read.seek_by(-1000);
        try reader_mmap.seek_by(-1000);
        while (bytes_read_read > 0) {
            bytes_read_read = try reader_read.read(&read_call_buf);
            bytes_read_mmap = try reader_mmap.read(&mmap_call_buf);
            try t.expectEqual(bytes_read_read, bytes_read_mmap);
            try t.expectEqualSlices(u8, &read_call_buf, &mmap_call_buf);
        }
    }

    test "reader can go back by using seek_by on underlying file" {
        const path = "temp_reader_test_file";
        const msg = "hola senorita";
        var wrote_bytes: usize = 0;
        defer std.fs.cwd().deleteFile(path) catch {};

        {
            const f = try std.fs.cwd().createFile(path, .{});
            defer f.close();
            wrote_bytes = try f.writer().write(msg);
        }
        var buf1: [msg.len]u8 = undefined;
        var buf2: [msg.len]u8 = undefined;
        {
            const f = try std.fs.cwd().openFile(path, .{});
            defer f.close();
            var r = try ReadReader.init(&f);
            const read_bytes1 = try r.read(&buf1);
            try r.seek_by(-@as(i64, @intCast(read_bytes1)));
            const read_bytes2 = try r.read(&buf2);

            try t.expectEqual(wrote_bytes, read_bytes1);
            try t.expectEqual(wrote_bytes, read_bytes2);
        }

        try t.expectEqualStrings(&buf1, &buf2);
        try t.expectEqualStrings(msg, &buf1);
        try t.expectEqualStrings(msg, &buf2);
    }

    test "make sure it works when std.io.BufferedReader's buf is filled and we go back" {
        const path = "temp_reader_test_file2";
        const msg = "hola senorita" ** 4096;
        var wrote_bytes: usize = 0;
        defer std.fs.cwd().deleteFile(path) catch {};

        {
            const f = try std.fs.cwd().createFile(path, .{});
            defer f.close();
            try f.writer().writeAll(msg);
            wrote_bytes = msg.len;
        }
        var buf1: [msg.len]u8 = undefined;
        var buf2: [msg.len]u8 = undefined;
        var buf3: [msg.len/2]u8 = undefined;
        var buf4: [3]u8 = undefined;
        {
            const f = try std.fs.cwd().openFile(path, .{});
            defer f.close();
            var r = try ReadReader.init(&f);
            const read_bytes1 = try r.read(&buf1);
            try r.seek_by(-@as(i64, @intCast(read_bytes1)));
            const read_bytes2 = try r.read(&buf2);
            try r.seek_by(-@as(i64, @intCast(read_bytes1/2)));
            const read_bytes3 = try r.read(&buf3);
            try r.seek_by(-3);
            const read_bytes4 = try r.read(&buf4);

            try t.expectEqual(wrote_bytes, read_bytes1);
            try t.expectEqual(wrote_bytes, read_bytes2);
            try t.expectEqual(wrote_bytes/2, read_bytes3);
            try t.expectEqual(read_bytes4, 3);
        }

        try t.expectEqualStrings(&buf1, &buf2);
        try t.expectEqualStrings(msg, &buf1);
        try t.expectEqualStrings(msg, &buf2);
        try t.expectEqualStrings(msg[msg.len/2..], &buf3);
        try t.expectEqualStrings(msg[msg.len-3..], &buf4);
    }

    test "seeking correctly goes back when used repeatedly" {
        const path = "temp_reader_test_file3";
        const msg = "hola senorita" ** 4096;
        var wrote_bytes: usize = 0;
        defer std.fs.cwd().deleteFile(path) catch {};

        {
            const f = try std.fs.cwd().createFile(path, .{});
            defer f.close();
            try f.writer().writeAll(msg);
            wrote_bytes = msg.len;
        }
        var buf: [5]u8 = undefined;
        const correct_bytes: []const u8 = msg[wrote_bytes/2..wrote_bytes/2+5];
        var buf_all: [msg.len]u8 = undefined;
        {
            const f = try std.fs.cwd().openFile(path, .{});
            defer f.close();
            var r = try ReadReader.init(&f);
            const read_bytes = try r.read(&buf_all);
            try r.seek_by(-@as(i64, @intCast(read_bytes/2)));

            try t.expectEqual(wrote_bytes, read_bytes);
            try t.expectEqualStrings(msg, &buf_all);

            for (0..10000) |idx| {
                const read = try r.read(&buf);
                try t.expectEqual(5, read);
                log.debug("try count: {d}", .{idx});
                try t.expectEqualStrings(&buf, correct_bytes);
                try r.seek_by(-5);
            }
        }

    }
};
