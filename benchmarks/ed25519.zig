const std = @import("std");

pub fn main() !void {
    try benchmarkEd25519();
    try benchmarkEd25519ThreadPool();
    try benchmarkEd25519Donna();
    try benchmarkEd25519DonnaThreadPool();
}

pub fn benchmarkEd25519() !void {
    std.debug.print("=== ed25519-std (single thread) ===\n\n", .{});

    const keys = try std.crypto.sign.Ed25519.KeyPair.create(null);

    const message = &[_]u8{0} ** 256;
    const signature = try std.crypto.sign.Ed25519.sign(message, keys, null);

    var timer = try std.time.Timer.start();

    {
        timer.reset();

        var count: usize = 0;
        while (count < 100_000) : (count += 1) {
            std.mem.doNotOptimizeAway(try std.crypto.sign.Ed25519.sign(message, keys, null));
        }
        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 100_000.0 / seconds;

        std.debug.print("sign: took {d:.4} second(s)\n", .{seconds});
        std.debug.print("sign: {d:.4} signatures/sec\n\n", .{ops_per_second});
    }

    {
        timer.reset();

        var count: usize = 0;
        while (count < 100_000) : (count += 1) {
            try std.crypto.sign.Ed25519.verify(signature, message, keys.public_key);
        }
        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 100_000.0 / seconds;

        std.debug.print("verify: took {d:.4} second(s)\n", .{seconds});
        std.debug.print("verify: {d:.4} signatures/sec\n\n", .{ops_per_second});
    }

    inline for (.{ 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096 }) |batch_size| {
        var batch: [batch_size]std.crypto.sign.Ed25519.BatchElement = undefined;
        for (batch) |*element| element.* = .{ .sig = signature, .msg = message, .public_key = keys.public_key };

        timer.reset();

        var count: usize = 0;
        while (count < 100_000) : (count += batch_size) {
            try std.crypto.sign.Ed25519.verifyBatch(batch_size, batch);
        }
        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 100_000.0 / seconds;

        std.debug.print("batch_verify({}): took {d:.4} second(s)\n", .{ batch_size, seconds });
        std.debug.print("batch_verify({}): {d:.4} signatures/sec\n\n", .{ batch_size, ops_per_second });
    }
}

pub fn benchmarkEd25519ThreadPool() !void {
    std.debug.print("=== ed25519-std (multiple threads) ===\n\n", .{});

    const ThreadPool = @import("ThreadPool.zig");
    const allocator = std.heap.c_allocator;

    const keys = try std.crypto.sign.Ed25519.KeyPair.create(null);

    const message = &[_]u8{0} ** 256;
    const signature = try std.crypto.sign.Ed25519.sign(message, keys, null);

    var pool: ThreadPool = undefined;
    try pool.init(allocator);
    defer pool.deinit();

    var events = try allocator.create([500_000]std.Thread.AutoResetEvent);
    defer allocator.destroy(events);

    for (events) |*event| event.* = .{};

    var timer = try std.time.Timer.start();

    inline for (.{1}) |batch_size| {
        const Test = struct {
            pub fn run(k: std.crypto.sign.Ed25519.KeyPair, m: []const u8, e: *std.Thread.AutoResetEvent) void {
                comptime var i: usize = 0;
                inline while (i < batch_size) : (i += 1) {
                    std.mem.doNotOptimizeAway(std.crypto.sign.Ed25519.sign(m, k, null) catch unreachable);
                }
                e.set();
            }
        };

        timer.reset();

        var count: usize = 0;
        while (count < events.len) : (count += batch_size) {
            try pool.spawn(Test.run, .{ keys, message, &events[count / batch_size] });
        }
        for (events[0 .. 500_000 / batch_size]) |*event| event.wait();

        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 500_000.0 / seconds;

        std.debug.print("sign({}): took {d:.4} second(s)\n", .{ batch_size, seconds });
        std.debug.print("sign({}): {d:.4} signatures/sec\n\n", .{ batch_size, ops_per_second });
    }

    inline for (.{1}) |batch_size| {
        const Test = struct {
            pub fn run(pk: [32]u8, s: [64]u8, m: []const u8, e: *std.Thread.AutoResetEvent) void {
                comptime var i: usize = 0;
                inline while (i < batch_size) : (i += 1) {
                    std.crypto.sign.Ed25519.verify(s, m, pk) catch unreachable;
                }
                e.set();
            }
        };

        timer.reset();

        var count: usize = 0;
        while (count < events.len) : (count += batch_size) {
            try pool.spawn(Test.run, .{ keys.public_key, signature, message, &events[count / batch_size] });
        }
        for (events[0 .. 500_000 / batch_size]) |*event| event.wait();

        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 500_000.0 / seconds;

        std.debug.print("verify({}): took {d:.4} second(s)\n", .{ batch_size, seconds });
        std.debug.print("verify({}): {d:.4} signatures/sec\n\n", .{ batch_size, ops_per_second });
    }

    inline for (.{ 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096 }) |batch_size| {
        var batch: [batch_size]std.crypto.sign.Ed25519.BatchElement = undefined;
        for (batch) |*element| element.* = .{ .sig = signature, .msg = message, .public_key = keys.public_key };

        const Test = struct {
            pub fn Case(comptime memoized_size: comptime_int) type {
                return struct {
                    pub fn run(b: *[memoized_size]std.crypto.sign.Ed25519.BatchElement, e: *std.Thread.AutoResetEvent) void {
                        std.crypto.sign.Ed25519.verifyBatch(memoized_size, b.*) catch unreachable;
                        e.set();
                    }
                };
            }
        };

        var count: usize = 0;
        while (count < events.len) : (count += batch_size) {
            try pool.spawn(Test.Case(batch_size).run, .{ &batch, &events[count / batch_size] });
        }
        for (events[0 .. 500_000 / batch_size]) |*event| event.wait();

        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 500_000.0 / seconds;

        std.debug.print("batch_verify({}): took {d:.4} second(s)\n", .{ batch_size, seconds });
        std.debug.print("batch_verify({}): {d:.4} signatures/sec\n\n", .{ batch_size, ops_per_second });
    }
}

pub fn benchmarkEd25519Donna() !void {
    std.debug.print("=== ed25519-donna (single thread) ===\n\n", .{});

    const ed25519 = @import("ed25519-donna");

    const keys = try std.crypto.sign.Ed25519.KeyPair.create(null);

    const message = &[_]u8{0} ** 256;
    const signature = try ed25519.sign(message, keys);

    var timer = try std.time.Timer.start();

    {
        timer.reset();

        var count: usize = 0;
        while (count < 100_000) : (count += 1) {
            std.mem.doNotOptimizeAway(try ed25519.sign(message, keys));
        }
        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 100_000.0 / seconds;

        std.debug.print("sign: took {d:.4} second(s)\n", .{seconds});
        std.debug.print("sign: {d:.4} signatures/sec\n\n", .{ops_per_second});
    }

    {
        timer.reset();

        var count: usize = 0;
        while (count < 100_000) : (count += 1) {
            try ed25519.verify(signature, message, keys.public_key);
        }
        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 100_000.0 / seconds;

        std.debug.print("verify: took {d:.4} second(s)\n", .{seconds});
        std.debug.print("verify: {d:.4} signatures/sec\n\n", .{ops_per_second});
    }

    inline for (.{ 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096 }) |batch_size| {
        var batch: [batch_size]std.crypto.sign.Ed25519.BatchElement = undefined;
        for (batch) |*element| element.* = .{ .sig = signature, .msg = message, .public_key = keys.public_key };

        timer.reset();

        var count: usize = 0;
        while (count < 100_000) : (count += batch_size) {
            try ed25519.verifyBatch(batch_size, batch);
        }
        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 100_000.0 / seconds;

        std.debug.print("batch_verify({}): took {d:.4} second(s)\n", .{ batch_size, seconds });
        std.debug.print("batch_verify({}): {d:.4} signatures/sec\n\n", .{ batch_size, ops_per_second });
    }
}

pub fn benchmarkEd25519DonnaThreadPool() !void {
    std.debug.print("=== ed25519-donna (multiple threads) ===\n\n", .{});

    const ed25519 = @import("ed25519-donna");
    const ThreadPool = @import("ThreadPool.zig");
    const allocator = std.heap.c_allocator;

    const keys = try std.crypto.sign.Ed25519.KeyPair.create(null);

    const message = &[_]u8{0} ** 256;
    const signature = try ed25519.sign(message, keys);

    var pool: ThreadPool = undefined;
    try pool.init(allocator);
    defer pool.deinit();

    var events = try allocator.create([500_000]std.Thread.AutoResetEvent);
    defer allocator.destroy(events);

    for (events) |*event| event.* = .{};

    var timer = try std.time.Timer.start();

    inline for (.{1}) |batch_size| {
        const Test = struct {
            pub fn run(m: []const u8, k: std.crypto.sign.Ed25519.KeyPair, e: *std.Thread.AutoResetEvent) void {
                comptime var i: usize = 0;
                inline while (i < batch_size) : (i += 1) {
                    std.mem.doNotOptimizeAway(ed25519.sign(m, k) catch unreachable);
                }
                e.set();
            }
        };

        timer.reset();

        var count: usize = 0;
        while (count < events.len) : (count += batch_size) {
            try pool.spawn(Test.run, .{ message, keys, &events[count / batch_size] });
        }
        for (events[0 .. 500_000 / batch_size]) |*event| event.wait();

        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 500_000.0 / seconds;

        std.debug.print("sign({}): took {d:.4} second(s)\n", .{ batch_size, seconds });
        std.debug.print("sign({}): {d:.4} signatures/sec\n\n", .{ batch_size, ops_per_second });
    }

    inline for (.{1}) |batch_size| {
        const Test = struct {
            pub fn run(s: [64]u8, m: []const u8, pk: [32]u8, e: *std.Thread.AutoResetEvent) void {
                comptime var i: usize = 0;
                inline while (i < batch_size) : (i += 1) {
                    ed25519.verify(s, m, pk) catch unreachable;
                }
                e.set();
            }
        };

        timer.reset();

        var count: usize = 0;
        while (count < events.len) : (count += batch_size) {
            try pool.spawn(Test.run, .{ signature, message, keys.public_key, &events[count / batch_size] });
        }
        for (events[0 .. 500_000 / batch_size]) |*event| event.wait();

        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 500_000.0 / seconds;

        std.debug.print("verify({}): took {d:.4} second(s)\n", .{ batch_size, seconds });
        std.debug.print("verify({}): {d:.4} signatures/sec\n\n", .{ batch_size, ops_per_second });
    }

    inline for (.{ 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096 }) |batch_size| {
        var batch: [batch_size]std.crypto.sign.Ed25519.BatchElement = undefined;
        for (batch) |*element| element.* = .{ .sig = signature, .msg = message, .public_key = keys.public_key };

        const Test = struct {
            pub fn Case(comptime memoized_size: comptime_int) type {
                return struct {
                    pub fn run(b: *[memoized_size]std.crypto.sign.Ed25519.BatchElement, e: *std.Thread.AutoResetEvent) void {
                        ed25519.verifyBatch(memoized_size, b.*) catch unreachable;
                        e.set();
                    }
                };
            }
        };

        var count: usize = 0;
        while (count < events.len) : (count += batch_size) {
            try pool.spawn(Test.Case(batch_size).run, .{ &batch, &events[count / batch_size] });
        }
        for (events[0 .. 500_000 / batch_size]) |*event| event.wait();

        const elapsed = timer.lap();
        const seconds = @intToFloat(f64, elapsed) / @intToFloat(f64, std.time.ns_per_s);
        const ops_per_second = 500_000.0 / seconds;

        std.debug.print("batch_verify({}): took {d:.4} second(s)\n", .{ batch_size, seconds });
        std.debug.print("batch_verify({}): {d:.4} signatures/sec\n\n", .{ batch_size, ops_per_second });
    }
}
