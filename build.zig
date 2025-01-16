const std = @import("std");

var target: std.Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;


pub fn build(b: *std.Build) void {
    target = b.standardTargetOptions(.{});
    optimize = b.standardOptimizeOption(.{});

    clean_all_step(b);
    const clean = clean_step(b);
    const create_fs = create_filesystems_step(b);
    test_step(b, clean, create_fs);
    build_and_run_step(b);
}

fn build_and_run_step(b: *std.Build) void {
    const run = b.step("run", "Run the app");

    const exe = b.addExecutable(.{
        .name = "zrec",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const build_lib = b.option(bool, "build_lib", "Build a static library") orelse false;
    if (build_lib) {
        const lib = b.addStaticLibrary(.{
            .name = "zrec",
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        });
        b.installArtifact(lib);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        for (args) |a| std.log.debug("{s}", .{a});
        run_cmd.addArgs(args);
    }
    run.dependOn(&run_cmd.step);
}

fn test_step(b: *std.Build, clean: *std.Build.Step, create_fs: *std.Build.Step) void {
    const test_s = b.step("test", "Run unit tests");
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    test_s.dependOn(clean);
    test_s.dependOn(create_fs);
    test_s.dependOn(&run_exe_unit_tests.step);
    test_s.dependOn(&run_lib_unit_tests.step);
}

fn clean_step(b: *std.Build) *std.Build.Step {
    const clean = b.step("clean", "Clean app output");
    const remove_output_dir = b.addRemoveDirTree("./output");
    const create_output_dir = b.addSystemCommand(&[_][]const u8{ "mkdir", "./output" });
    clean.dependOn(&remove_output_dir.step);
    clean.dependOn(&create_output_dir.step);
    return clean;
}

fn clean_all_step(b: *std.Build) void {
    const clean = b.step("clean-all", "Clean app output and filesystems");
    const remove_output_dir = b.addRemoveDirTree("./output");
    const remove_filesystems_dir = b.addRemoveDirTree("./filesystems");
    clean.dependOn(&remove_output_dir.step);
    clean.dependOn(&remove_filesystems_dir.step);
}

fn create_filesystems_step(b: *std.Build) *std.Build.Step {
    const create = b.step("create-filesystems", "Create filesystems for testing");
    const fs_dir_doesnt_exist = std.fs.cwd().openDir("./filesystems", .{}) == error.FileNotFound;
    if (fs_dir_doesnt_exist) {
        const create_fat32 = b.addSystemCommand(&[_][]const u8{ "bash", "scripts/create_test_fat32_filesystem.sh" });
        create.dependOn(&create_fat32.step);
    }
    return create;
}
