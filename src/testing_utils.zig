const std = @import("std");
const lib = @import("lib.zig");

pub fn should_skip_slow_test() !bool {
    const config = @import("test_config");
    if (@hasDecl(config, "skip_slow_tests")) {
        return config.skip_slow_tests;
    }

    return false;
}

pub fn skip_slow_test() error{SkipZigTest}!void {
    if (should_skip_slow_test() catch return error.SkipZigTest) return error.SkipZigTest;
}
