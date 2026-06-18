const std = @import("std");
const rlz = @import("raylib_zig");

pub fn build(b: *std.Build) !void {
    var target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_web = target.query.os_tag == .emscripten;

    // Enable SIMD for wasm
    if (is_web) {
        var query = target.query;
        query.cpu_features_add.addFeature(@intFromEnum(std.Target.wasm.Feature.simd128));
        target = b.resolveTargetQuery(query);
    }

    const raylib_config: []const u8 = if (is_web) "-msimd128" else "";

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .config = raylib_config,
    });

    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    if (is_web) {
        const emsdk = rlz.emsdk;

        const lib = b.addLibrary(.{
            .linkage = .static,
            .name = "zig_invaders",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        lib.root_module.addImport("raylib", raylib);

        lib.use_llvm = true;
        lib.use_lld = true;

        const install_dir: std.Build.InstallDir = .{ .custom = "web" };

        var emcc_flags = emsdk.emccDefaultFlags(b.allocator, .{ .optimize = optimize });
        try emcc_flags.put("-sALLOW_MEMORY_GROWTH=1", {});
        try emcc_flags.put("-sASSERTIONS=1", {});
        try emcc_flags.put("-msimd128", {});

        const emcc_settings = emsdk.emccDefaultSettings(b.allocator, .{ .optimize = optimize });

        const emcc_step = emsdk.emccStep(b, raylib_artifact, lib, .{
            .optimize = optimize,
            .flags = emcc_flags,
            .settings = emcc_settings,
            .shell_file_path = b.path("resources/index.html"),
            .install_dir = install_dir,
        });

        b.getInstallStep().dependOn(emcc_step);
        const html_filename = std.fmt.allocPrint(
            b.allocator,
            "{s}.html",
            .{lib.name},
        ) catch @panic("OOM");

        const run_step = b.step("run", "Run locally with emrun server");

        const emrun_step = emsdk.emrunStep(
            b,
            b.getInstallPath(install_dir, html_filename),
            &.{},
        );

        emrun_step.dependOn(emcc_step);
        run_step.dependOn(emrun_step);

        const web_step = b.step("web", "Build web");
        web_step.dependOn(emcc_step);
    } else {
        const exe = b.addExecutable(.{
            .name = "zig_invaders",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        if (target.result.os.tag == .linux) {
            exe.use_llvm = true;
            exe.use_lld = true;
        }

        exe.root_module.addImport("raylib", raylib);

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run native app");
        run_step.dependOn(&run_cmd.step);
    }
}
