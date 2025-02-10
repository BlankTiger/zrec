const std = @import("std");

pub fn set_fields_alignment(comptime fields: []const std.builtin.Type.StructField, alignment: comptime_int) []std.builtin.Type.StructField {
    var new_fields: [fields.len]std.builtin.Type.StructField = undefined;
    inline for (fields, 0..) |f, idx| {
        var new_f = f;
        new_f.alignment = alignment;
        new_fields[idx] = new_f;
    }
    return &new_fields;
}

pub fn set_fields_alignment_in_struct(Struct: type, alignment: comptime_int) type {
    const info = @typeInfo(Struct).@"struct";
    const fields = info.fields;
    const new_fields = set_fields_alignment(fields, alignment);
    return @Type(.{
        .@"struct" = .{
            .fields = new_fields,
            .decls = info.decls,
            .backing_integer = info.backing_integer,
            .is_tuple = info.is_tuple,
            .layout = info.layout,
        }
    });
}

test set_fields_alignment_in_struct {
    comptime {
        const t = std.testing;

        const _A = struct {
            a: u8,
            c: [3]u8,
            d: u32,
            e: usize,
            b: u3,
            f: []u8,
        };
        const A = set_fields_alignment_in_struct(_A, 1);

        const fields_before = @typeInfo(_A).@"struct".fields;
        const fields_after = @typeInfo(A).@"struct".fields;
        const expected_before = &[_]comptime_int{ 1, 1, 4, 8, 1, 8 };
        const expected_after = &[_]comptime_int{ 1 } ** fields_after.len;
        for (fields_before, fields_after, 0..) |fb, fa, idx| {
            try t.expectEqual(expected_before[idx], fb.alignment);
            try t.expectEqual(expected_after[idx], fa.alignment);
        }
    }
}
