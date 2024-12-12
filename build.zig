const std = @import("std");

var target: std.Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;

fn test_step(b: *std.Build) void {
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_s = b.step("test", "Run unit tests");
    test_s.dependOn(&run_exe_unit_tests.step);
}

fn build_and_run_step(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "zrec",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run = b.step("run", "Run the app");
    run.dependOn(&run_cmd.step);
}

pub fn build(b: *std.Build) void {
    target = b.standardTargetOptions(.{});
    optimize = b.standardOptimizeOption(.{});

    build_and_run_step(b);
    test_step(b);
}
