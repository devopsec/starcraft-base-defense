//! Native backend: a Zig executable that imports the core as a module (no FFI) and presents with
//! SDL3 (window, input, gamepads), wgpu-native (rendering) and OpenXR (optional, loaded at runtime).
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const os = target.result.os.tag;

    const core_mod = b.dependency("sbd_core", .{ .target = target, .optimize = optimize }).module("sbd_core");

    // ---- device-independent logic (game, input, balance): unit-tested without SDL/wgpu ----
    const logic_tests = b.addTest(.{ .root_module = logicModule(b, "src/tests.zig", target, optimize, core_mod) });
    const test_step = b.step("test", "Run native host unit tests (no window or GPU needed)");
    test_step.dependOn(&b.addRunArtifact(logic_tests).step);

    // ---- executable ----
    const sdl_lib = b.dependency("sdl", .{ .target = target, .optimize = optimize }).artifact("SDL3");
    const wgpu_name: []const u8 = switch (os) {
        .linux => "wgpu_linux_x86_64",
        .windows => "wgpu_windows_x86_64",
        else => @panic("native backend: wgpu-native is wired for x86_64 Linux and Windows only"),
    };
    if (target.result.cpu.arch != .x86_64) @panic("native backend: wgpu-native is wired for x86_64 only");
    const wgpu = b.lazyDependency(wgpu_name, .{}) orelse return;
    const openxr = b.dependency("openxr", .{});

    const c = b.addTranslateC(.{ .root_source_file = b.path("src/c.h"), .target = target, .optimize = optimize });
    c.addIncludePath(sdl_lib.getEmittedIncludeTree());
    c.addIncludePath(wgpu.path("include"));
    c.addIncludePath(openxr.path("include"));

    const exe_mod = logicModule(b, "src/main.zig", target, optimize, core_mod);
    exe_mod.addImport("c", c.createModule());
    exe_mod.linkLibrary(sdl_lib);
    exe_mod.addLibraryPath(wgpu.path("lib"));
    switch (os) {
        .linux => {
            exe_mod.linkSystemLibrary("wgpu_native", .{ .preferred_link_mode = .dynamic, .use_pkg_config = .no });
            exe_mod.addRPathSpecial("$ORIGIN");
        },
        .windows => exe_mod.addObjectFile(wgpu.path("lib/libwgpu_native.dll.a")),
        else => unreachable,
    }

    // math and XR pose helpers live next to the C code; their tests need the translated headers
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = exe_mod })).step);

    const exe = b.addExecutable(.{ .name = "sbd_native", .root_module = exe_mod });
    b.installArtifact(exe);
    // wgpu-native ships as a shared library: install it next to the executable.
    const shared = if (os == .windows) "wgpu_native.dll" else "libwgpu_native.so";
    const install_wgpu = b.addInstallFileWithDir(wgpu.path(b.fmt("lib/{s}", .{shared})), .bin, shared);
    b.getInstallStep().dependOn(&install_wgpu.step);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    run.addPassthruArgs();
    b.step("run", "Run the native game (pass options after --, e.g. -- --headless)").dependOn(&run.step);

    const smoke = b.addRunArtifact(exe);
    smoke.step.dependOn(b.getInstallStep());
    smoke.addArg("--smoke");
    smoke.expectExitCode(0);
    smoke.addCheck(.{ .expect_stdout_match = "NATIVE SMOKE OK\n" });
    b.step("smoke", "Headless scripted game; expects NATIVE SMOKE OK").dependOn(&smoke.step);
}

fn logicModule(
    b: *std.Build,
    root: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core_mod: *std.Build.Module,
) *std.Build.Module {
    const m = b.createModule(.{ .root_source_file = b.path(root), .target = target, .optimize = optimize, .link_libc = true });
    m.addImport("sbd_core", core_mod);
    // The single balance source of truth, embedded; `--balance <path>` overrides it at runtime.
    m.addAnonymousImport("balance.json", .{ .root_source_file = b.path("../../data/balance.json") });
    return m;
}
