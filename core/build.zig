const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Named module: Zig hosts (engines/native) import the core directly instead of going through the C ABI.
    const mod = b.addModule("sbd_core", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shared = b.addLibrary(.{ .linkage = .dynamic, .name = "sbd_core", .root_module = mod });
    const static = b.addLibrary(.{ .linkage = .static, .name = "sbd_core_static", .root_module = mod });
    b.installArtifact(shared);
    b.installArtifact(static);
    b.installFile("include/sbd.h", "include/sbd.h");

    const tests = b.addTest(.{ .root_module = mod });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const abi_exe = b.addExecutable(.{
        .name = "abi_test",
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
    });
    abi_exe.root_module.addCSourceFile(.{ .file = b.path("tests/abi_test.c"), .flags = &.{"-std=c11"} });
    abi_exe.root_module.addIncludePath(b.path("include"));
    abi_exe.root_module.linkLibrary(shared);
    const abi_step = b.step("abi-test", "Compile tests/abi_test.c against sbd.h and run it");
    abi_step.dependOn(&b.addRunArtifact(abi_exe).step);
}
