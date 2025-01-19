const std = @import("std");
const log = std.log.scoped(.reader);

pub const Reader = struct {
    file: *const std.fs.File,
    reader: std.fs.File.Reader,

    // BUG: buffered reader was causing seeking to fail because of the internal buffering
    // maybe write a custom buffered reader?
    // pub const BufferedReader = std.io.BufferedReader(4096, std.fs.File.Reader);
    // reader: BufferedReader,

    const Self = @This();
    pub fn init(file: *const std.fs.File) Self {
        const reader = file.reader();
        return Self {
            .file = file,
            .reader = reader,
        };
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

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    const expect = std.testing.expect;

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
            var r = Reader.init(&f);
            const read_bytes1 = try r.read(&buf1);
            try r.seek_by(-@as(i64, @intCast(read_bytes1)));
            const read_bytes2 = try r.read(&buf2);

            try expect(wrote_bytes == read_bytes1);
            try expect(wrote_bytes == read_bytes2);
        }

        try expect(std.mem.eql(u8, &buf1, &buf2));
        try expect(std.mem.eql(u8, msg, &buf1));
        try expect(std.mem.eql(u8, msg, &buf2));
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
            var r = Reader.init(&f);
            const read_bytes1 = try r.read(&buf1);
            try r.seek_by(-@as(i64, @intCast(read_bytes1)));
            const read_bytes2 = try r.read(&buf2);
            try r.seek_by(-@as(i64, @intCast(read_bytes1/2)));
            const read_bytes3 = try r.read(&buf3);
            try r.seek_by(-3);
            const read_bytes4 = try r.read(&buf4);

            try expect(wrote_bytes == read_bytes1);
            try expect(wrote_bytes == read_bytes2);
            try expect(wrote_bytes/2 == read_bytes3);
            try expect(read_bytes4 == 3);
        }

        try expect(std.mem.eql(u8, &buf1, &buf2));
        try expect(std.mem.eql(u8, msg, &buf1));
        try expect(std.mem.eql(u8, msg, &buf2));
        try expect(std.mem.eql(u8, msg[msg.len/2..], &buf3));
        try expect(std.mem.eql(u8, msg[msg.len-3..], &buf4));
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
            var r = Reader.init(&f);
            const read_bytes = try r.read(&buf_all);
            try r.seek_by(-@as(i64, @intCast(read_bytes/2)));

            try expect(wrote_bytes == read_bytes);
            try expect(std.mem.eql(u8, msg, &buf_all));

            for (0..10000) |idx| {
                const read = try r.read(&buf);
                try expect(read == 5);
                log.debug("try count: {d}", .{idx});
                try expect(std.mem.eql(u8, &buf, correct_bytes));
                try r.seek_by(-5);
            }
        }

    }
};
