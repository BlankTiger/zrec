var data = {lines:[
{"lineNum":"    1","line":"const std = @import(\"std\");"},
{"lineNum":"    2","line":"const filetypes = @import(\"filetypes.zig\");"},
{"lineNum":"    3","line":"const reader = @import(\"reader.zig\");"},
{"lineNum":"    4","line":"const printer = @import(\"printer.zig\");"},
{"lineNum":"    5","line":"const utils = @import(\"utils.zig\");"},
{"lineNum":"    6","line":"pub const FilesystemHandler = @import(\"FilesystemHandler.zig\");"},
{"lineNum":"    7","line":""},
{"lineNum":"    8","line":"pub const ReadReader = reader.ReadReader;"},
{"lineNum":"    9","line":"pub const MmapReader = reader.MmapReader;"},
{"lineNum":"   10","line":"/// Choice of Reader over the application and tests is made here"},
{"lineNum":"   11","line":"/// changing the line below should change implementation in all"},
{"lineNum":"   12","line":"/// necessary places."},
{"lineNum":"   13","line":"pub const Reader = MmapReader;"},
{"lineNum":"   14","line":"pub const JPGRecoverer = filetypes.JPGRecoverer;"},
{"lineNum":"   15","line":"pub const PNGRecoverer = filetypes.PNGRecoverer;"},
{"lineNum":"   16","line":"pub const Filetypes = filetypes.Filetypes;"},
{"lineNum":"   17","line":"pub const print = printer.print;"},
{"lineNum":"   18","line":"pub const PrintOpts = printer.Opts;"},
{"lineNum":"   19","line":"pub const set_fields_alignment = utils.set_fields_alignment;"},
{"lineNum":"   20","line":"pub const set_fields_alignment_in_struct = utils.set_fields_alignment_in_struct;"},
{"lineNum":"   21","line":""},
{"lineNum":"   22","line":"test {","class":"lineCov","hits":"1","order":"1","possible_hits":"1",},
{"lineNum":"   23","line":"    std.testing.refAllDecls(@This());","class":"lineCov","hits":"1","order":"2","possible_hits":"1",},
{"lineNum":"   24","line":"}"},
]};
var percent_low = 25;var percent_high = 75;
var header = { "command" : "test", "date" : "2025-02-27 20:56:12", "instrumented" : 2, "covered" : 2,};
var merged_data = [];
