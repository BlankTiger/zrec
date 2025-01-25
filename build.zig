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
    const create_fs = create_filesystems_step(b);
    test_step(b, clean, create_fs);
    bench_step(b, clean, create_fs);
    docs_step(b);
    try build_and_run_step(b);
}

fn build_and_run_step(b: *std.Build) !void {
    const run = b.step("run", "Run the app");

    const build_gui = b.option(bool, "build_gui", "Build as a GUI app instead of a TUI app.") orelse false;
    const log_level = b.option(std.log.Level, "log_level", "App log_level.") orelse .info;
    const options = b.addOptions();
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
        const fps = b.option(u16, "fps", "GUI refresh rate.") orelse 120;
        options.addOption(u16, "fps", fps);
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
            "./src/gui/SDL",
            "-B",
            "./build/SDL",
            cmake_optimize,
            "--log-level=ERROR"
        });

        const sdl3_cmake_build = b.addSystemCommand(&[_][]const u8{
            "cmake",
            "--build",
            "./build/SDL",
            "--parallel",
            "8",
            "--",
            "--quiet"
        });

        const sdl3_ttf_cmake_prepare = b.addSystemCommand(&[_][]const u8{
            "cmake",
            "-S",
            "./src/gui/SDL_ttf",
            "-B",
            "./build/SDL_ttf",
            cmake_optimize,
            "--log-level=ERROR"
        });

        const sdl3_ttf_cmake_build = b.addSystemCommand(&[_][]const u8{
            "cmake",
            "--build",
            "./build/SDL_ttf",
            "--parallel",
            "8",
            "--",
            "--quiet"
        });
        sdl3_cmake_build.step.dependOn(&sdl3_cmake_prepare.step);
        sdl3_ttf_cmake_build.setEnvironmentVariable("SDL3_DIR", "./build/SDL");
        sdl3_ttf_cmake_build.step.dependOn(&sdl3_ttf_cmake_prepare.step);
        sdl3_ttf_cmake_build.step.dependOn(&sdl3_ttf_cmake_prepare.step);
        exe.step.dependOn(&sdl3_cmake_build.step);
        exe.step.dependOn(&sdl3_ttf_cmake_build.step);
        exe.addLibraryPath(std.Build.LazyPath{ .cwd_relative = "./build/SDL" });
        exe.addLibraryPath(std.Build.LazyPath{ .cwd_relative = "./build/SDL_ttf" });
        exe.addIncludePath(std.Build.LazyPath{ .cwd_relative = "./src/gui/SDL/include" });
        exe.addIncludePath(std.Build.LazyPath{ .cwd_relative = "./src/gui/SDL_ttf/include" });
        exe.linkSystemLibrary("SDL3");
        exe.linkSystemLibrary("SDL3_ttf");
        exe.linkSystemLibrary("m");
        exe.linkLibC();
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

fn test_step(b: *std.Build, clean: *std.Build.Step, create_fs: *std.Build.Step) void {
    const test_s = b.step("test", "Run unit tests");
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
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
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    test_s.dependOn(clean);
    test_s.dependOn(create_fs);
    test_s.dependOn(&run_exe_unit_tests.step);
    test_s.dependOn(&run_lib_unit_tests.step);
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
