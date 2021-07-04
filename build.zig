const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const test_step = b.step("test", "Run library tests.");
    const test_filter = b.option([]const u8, "test-filter", "A glob to filter through what tests are to be ran.");

    const file = b.addTest("ed25519.zig");
    file.setTarget(target);
    file.setBuildMode(mode);

    setupEd25519Donna(file, ".");

    if (test_filter) |tf| file.setFilter(tf);
    test_step.dependOn(&file.step);

    const bench_step = b.step("bench", "Run library benchmarks.");

    const bench = b.addExecutable("benchmark", "benchmarks/ed25519.zig");
    bench.setTarget(target);
    bench.setBuildMode(mode);

    setupEd25519Donna(bench, ".");
    bench.addPackagePath("ed25519-donna", "ed25519.zig");

    const bench_run_step = bench.run();
    bench_step.dependOn(&bench_run_step.step);
}

pub fn setupEd25519Donna(step: *std.build.LibExeObjStep, comptime dir: []const u8) void {
    step.linkLibC();
    step.linkSystemLibrary("crypto");
    step.addIncludeDir(dir ++ "/lib");

    var defines: std.ArrayListUnmanaged([]const u8) = .{};
    defer defines.deinit(step.builder.allocator);

    if (std.Target.x86.featureSetHas(step.target.getCpuFeatures(), .sse2)) {
        defines.append(step.builder.allocator, "-DED25519_SSE2") catch unreachable;
    }

    step.addCSourceFile(dir ++ "/lib/ed25519.c", defines.items);
}
