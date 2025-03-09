var data = {lines:[
{"lineNum":"    1","line":"const std = @import(\"std\");"},
{"lineNum":"    2","line":"const lib = @import(\"lib.zig\");"},
{"lineNum":"    3","line":""},
{"lineNum":"    4","line":"pub fn should_skip_slow_test() !bool {","class":"lineCov","hits":"1","order":"17","possible_hits":"1",},
{"lineNum":"    5","line":"    const config = @import(\"test_config\");"},
{"lineNum":"    6","line":"    if (@hasDecl(config, \"skip_slow_tests\")) {"},
{"lineNum":"    7","line":"        return config.skip_slow_tests;","class":"lineCov","hits":"1","order":"18","possible_hits":"1",},
{"lineNum":"    8","line":"    }"},
{"lineNum":"    9","line":""},
{"lineNum":"   10","line":"    return false;"},
{"lineNum":"   11","line":"}"},
{"lineNum":"   12","line":""},
{"lineNum":"   13","line":"pub fn skip_slow_test() error{SkipZigTest}!void {","class":"lineCov","hits":"1","order":"15","possible_hits":"1",},
{"lineNum":"   14","line":"    if (should_skip_slow_test() catch return error.SkipZigTest) return error.SkipZigTest;","class":"lineCov","hits":"1","order":"16","possible_hits":"1",},
{"lineNum":"   15","line":"}"},
]};
var percent_low = 25;var percent_high = 75;
var header = { "command" : "test", "date" : "2025-03-09 09:32:06", "instrumented" : 4, "covered" : 4,};
var merged_data = [];
