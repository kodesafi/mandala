const std = @import("std");
const glfw = @import("libs/mach-glfw/build.zig");
const sys_sdk = @import("libs/mach-glfw/system_sdk.zig");
const gpu_sdk = @import("libs/mach-gpu/sdk.zig");
const dawn_sdk = @import("libs/mach-gpu-dawn/sdk.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gpu_dawn = dawn_sdk.Sdk(.{
        .glfw_include_dir = "libs/mach-glfw/upstream/glfw/include",
        .system_sdk = sys_sdk,
    });

    const gpu = gpu_sdk.Sdk(.{
        .gpu_dawn = gpu_dawn,
    });

    const gpu_dawn_opts = gpu_dawn.Options{
        .from_source = b.option(bool, "dawn-from-source", "Build Dawn from source") orelse false,
        .debug = b.option(bool, "dawn-debug", "Use a debug build of Dawn") orelse
            false,
    };

    const exe = b.addExecutable(.{
        .name = "shawig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("gpu", gpu.module(b));
    exe.addModule("glfw", glfw.module(b));
    try gpu.link(b, exe, .{ .gpu_dawn_options = gpu_dawn_opts });
    try glfw.link(b, exe, .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
