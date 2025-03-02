const std = @import("std");
const log = std.log.scoped(.build);

var target: std.Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;
var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena_state.allocator();

pub fn build(b: *std.Build) !void {
    defer arena_state.deinit();
    target = b.standardTargetOptions(.{});
    optimize = b.standardOptimizeOption(.{});

    clean_all_step(b);
    const clean = clean_step(b);
    const create_fs = try create_filesystems_step(b);

    const filters: []const []const u8 =
        b.option([]const []const u8, "test-filter", "Only run tests matching this") orelse &.{};

    const test_s = test_step(b, "test", "Run unit tests (only fast tests)", true, false, filters);
    test_s.dependOn(clean);
    test_s.dependOn(create_fs);

    const all_test_s = test_step(b, "test-all", "Run all unit tests including slow ones", false, false, filters);
    all_test_s.dependOn(clean);
    all_test_s.dependOn(create_fs);

    const kcov_test_s = test_step(b, "test-kcov", "Run all unit tests with kcov", false, true, filters);
    kcov_test_s.dependOn(clean);
    kcov_test_s.dependOn(create_fs);

    bench_step(b, clean, create_fs);
    docs_step(b);
    try build_and_run_step(b);
}

fn build_and_run_step(b: *std.Build) !void {
    const run = b.step("run", "Run the app");

    const build_gui = b.option(bool, "build_gui", "Build as a GUI app instead of a TUI app.") orelse false;
    const log_level = b.option(std.log.Level, "log_level", "App log_level.") orelse .info;
    const fps = b.option(u16, "fps", "GUI refresh rate.") orelse 120;
    const options = b.addOptions();
    options.addOption(u16, "fps", fps);
    options.addOption(bool, "build_gui", build_gui);
    options.addOption(std.log.Level, "log_level", log_level);
    log.debug("building gui: {any}", .{build_gui});
    log.debug("log_level: {any}", .{log_level});

    const exe = b.addExecutable(.{
        .name = "zrec",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (build_gui) {
        const cmake_optimize = try std.fmt.allocPrint(allocator, "-DCMAKE_BUILD_TYPE={s}", .{
            switch (optimize) {
                .Debug        => "Debug",
                .ReleaseSmall => "MinSizeRel",
                .ReleaseSafe  => "RelWithDebInfo",
                .ReleaseFast  => "Release",
            }}
        );
        const sdl3_cmake_prepare = b.addSystemCommand(&[_][]const u8{
            "cmake",
            "-S",
            "./src/gui/SDL3",
            "-B",
            "./build/SDL3",
            cmake_optimize,
            "--log-level=ERROR"
        });

        const sdl3_cmake_build = b.addSystemCommand(&[_][]const u8{
            "cmake",
            "--build",
            "./build/SDL3",
            "--parallel",
            "8",
            "--",
            "--quiet"
        });

        sdl3_cmake_build.step.dependOn(&sdl3_cmake_prepare.step);
        exe.step.dependOn(&sdl3_cmake_build.step);
        exe.addLibraryPath(std.Build.LazyPath{ .cwd_relative = "./build/SDL3" });
        exe.addIncludePath(std.Build.LazyPath{ .cwd_relative = "./src/gui/SDL3/include" });
        exe.linkSystemLibrary("SDL3");
        exe.linkSystemLibrary("m");
        exe.linkLibC();

        const raylib_dep = b.dependency("raylib", .{
            .target = target,
            .optimize = optimize,
            .shared = false,
        });
        const raylib = raylib_dep.artifact("raylib");

        var gen_step = b.addWriteFiles();
        raylib.step.dependOn(&gen_step.step);

        const raygui_c_path = gen_step.add(
            "raygui.c",
            \\#define RAYGUI_IMPLEMENTATION
            \\#include "raygui.h"
        );
        exe.addCSourceFile(.{ .file = raygui_c_path });
        exe.addIncludePath(b.path("./src/gui/raygui/src"));
        exe.addIncludePath(b.path("./src/gui/raylib/src"));
        exe.linkLibC();
        exe.linkLibrary(raylib);
    }

    exe.root_module.addOptions("config", options);

    const mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zrec", mod);

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
        for (args, 0..) |a, idx| log.debug("cmd_arg {d}: {s}", .{idx+1, a});
        run_cmd.addArgs(args);
    }
    run.dependOn(&run_cmd.step);
}

fn test_step(
    b: *std.Build,
    name: []const u8,
    description: []const u8,
    skip_slow_tests: bool,
    kcov: bool,
    filters: []const []const u8,
) *std.Build.Step {
    const step = b.step(name, description);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .filters = filters,
    });
    if (kcov) exe_unit_tests.setExecCmd(&.{
        "kcov",
        "--include-path=./src",
        "docs",
        null,
    });

    const test_options = create_test_options(b, skip_slow_tests);
    exe_unit_tests.root_module.addOptions("test_config", test_options);

    const mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.root_module.addImport("zrec", mod);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .filters = filters,
    });
    lib_unit_tests.root_module.addOptions("test_config", test_options);
    if (kcov) lib_unit_tests.setExecCmd(&.{
        "kcov",
        "docs",
        null,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    step.dependOn(&run_exe_unit_tests.step);
    step.dependOn(&run_lib_unit_tests.step);

    return step;
}

fn create_test_options(b: *std.Build, skip_slow_tests: bool) *std.Build.Step.Options {
    const test_options = b.addOptions();
    test_options.addOption(bool, "skip_slow_tests", skip_slow_tests);
    return test_options;
}

fn bench_step(b: *std.Build, clean: *std.Build.Step, create_fs: *std.Build.Step) void {
    const bench_s = b.step("bench", "Run benchmarks");
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/benchmarks/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.root_module.addImport("zrec", mod);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    bench_s.dependOn(clean);
    bench_s.dependOn(create_fs);
    bench_s.dependOn(&run_exe_unit_tests.step);
}

fn clean_step(b: *std.Build) *std.Build.Step {
    const clean = b.step("clean", "Clean app output");
    const remove_output_dir = b.addRemoveDirTree(b.path("./output"));
    const create_output_dir = b.addSystemCommand(&[_][]const u8{ "mkdir", "./output" });
    clean.dependOn(&remove_output_dir.step);
    clean.dependOn(&create_output_dir.step);
    return clean;
}

fn clean_all_step(b: *std.Build) void {
    const clean = b.step("clean-all", "Clean app output and filesystems");
    const remove_output_dir = b.addRemoveDirTree(b.path("./output"));
    const remove_filesystems_dir = b.addRemoveDirTree(b.path("./filesystems"));
    clean.dependOn(&remove_output_dir.step);
    clean.dependOn(&remove_filesystems_dir.step);
}

fn create_filesystems_step(b: *std.Build) !*std.Build.Step {
    const create = b.step("create-filesystems", "Create filesystems for testing");
    const fs_dir_doesnt_exist = std.fs.cwd().openDir("./filesystems", .{}) == error.FileNotFound;

    if (fs_dir_doesnt_exist) {
        const mkdir_fs = b.addSystemCommand(&.{"mkdir", "-p", "./filesystems"});
        create.dependOn(&mkdir_fs.step);

        const ext2_creator = b.addExecutable(.{
            .name = "create_test_ext2_filesystem",
            .root_source_file = b.path("scripts/create_test_ext2_filesystem.zig"),
            .target = target,
            .optimize = optimize,
        });

        const run_ext2_creator = b.addRunArtifact(ext2_creator);
        run_ext2_creator.step.dependOn(&mkdir_fs.step);
        create.dependOn(&run_ext2_creator.step);

        const fat32_creator = b.addExecutable(.{
            .name = "create_test_fat32_filesystem",
            .root_source_file = b.path("scripts/create_test_fat32_filesystem.zig"),
            .target = target,
            .optimize = optimize,
        });

        const run_fat32_creator = b.addRunArtifact(fat32_creator);
        run_fat32_creator.step.dependOn(&mkdir_fs.step);
        create.dependOn(&run_fat32_creator.step);

        const ntfs_creator = b.addExecutable(.{
            .name = "create_test_ntfs_filesystem",
            .root_source_file = b.path("scripts/create_test_ntfs_filesystem.zig"),
            .target = target,
            .optimize = optimize,
        });

        const run_ntfs_creator = b.addRunArtifact(ntfs_creator);
        run_ntfs_creator.step.dependOn(&mkdir_fs.step);
        create.dependOn(&run_ntfs_creator.step);
    }

    return create;
}

fn docs_step(b: *std.Build) void {
    const step = b.step("docs", "Emit docs");

    const lib = b.addStaticLibrary(.{
        .name = "zrec",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const docs_install = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "docs",
        .source_dir = lib.getEmittedDocs(),
    });

    step.dependOn(&docs_install.step);
    b.default_step.dependOn(step);
}
