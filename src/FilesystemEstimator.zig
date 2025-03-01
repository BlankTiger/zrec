const std = @import("std");
const Filesystem = @import("Filesystem.zig");

const Estimator = @This();

pub fn init(allocator: Allocator) Estimator {}

pub fn deinit(self: Estimator) void {}

/// Estimates the confidence level that data that `Estimator` was initialized
/// with is one of the implemented filesystems. Returns filesystems that have
/// their estimated confidence level >= `min_confidence_level`.
pub fn estimate(self: Estimator, min_confidence_level: f32) []Filesystem {
    assert(min_confidence_level > 0 and min_confidence_level <= 1);
}
