# ed25519-donna-zig

Minimal [Zig](https://ziglang.org/) bindings to [ed25519-donna](https://github.com/floodyberry/ed25519-donna).

ed25519-donna is [Andrew Moon](https://github.com/floodyberry/)'s implementation of ed25519 signing, verification, and batch verification.

These bindings require that the OpenSSL crypto library is available in your environment for cryptographically-secure random number generation and SHA-512 hashing.

Support for custom hash functions and random number generation functions is not available at the moment, but will be made available once Zig's standard library implementation of SHA-512 hashing yields better benchmark results.

In order to generate ed25519 keys, refer to Zig's standard library ed25519 implementation. If you have a need for ed25519-donna's key generation implementation, please file an issue describing your use case.

These bindings were built and tested against Zig's master branch over all possible optimization modes.

## Motivation

These bindings were built for a few applications I am working on that makes heavy use of Ed25519 signing and batch verification. I found Zig's standard library ed25519 implementation to be a tad too slow, so I wrote some bindings to ed25519-donna instead.

When the time comes that Zig's standard library ed25519 implementation yields better benchmark results, it should be trivial to migrate over to making use of Zig's standard library ed25519 implementation as these bindings feature API parity with Zig's standard library ed25519 implementation.

## Setup

In your build.zig:

```zig
const exe = b.addExecutable("your_executable_here", "main.zig");

// ... set target, build mode, and other settings here.

exe.linkLibC();
exe.linkSystemLibrary("crypto");
exe.addIncludeDir("ed25519-donna-zig/lib");

var defines: std.ArrayListUnmanaged([]const u8) = .{};
defer defines.deinit(exe.builder.allocator);

if (std.Target.x86.featureSetHas(exe.target.getCpuFeatures(), .sse2)) {
    defines.append(exe.builder.allocator, "-DED25519_SSE2") catch unreachable;
}

exe.addCSourceFile("ed25519-donna-zig/lib/ed25519.c", defines.items);
exe.addPackagePath("ed25519-donna", "ed25519-donna-zig/ed25519.zig");
```

## Example

```zig
test "ed25519: sign and verify a message" {
    const ed25519 = @import("ed25519-donna");

    const keys = try std.crypto.sign.Ed25519.KeyPair.create(null);

    const message = "hello world";
    const signature = try ed25519.sign(message, keys);
    try ed25519.verify(signature, message, keys.public_key);
}

test "ed25519: verify a batch of signatures using verifyBatch()" {
    const ed25519 = @import("ed25519-donna");

    const keys = try std.crypto.sign.Ed25519.KeyPair.create(null);

    const message = "hello world";
    const signature = try ed25519.sign(message, keys);

    var batch: [64]std.crypto.sign.Ed25519.BatchElement = undefined;
    for (batch) |*element| {
        element.* = .{
            .sig = signature,
            .msg = message,
            .public_key = keys.public_key,
        };
    }

    try ed25519.verifyBatch(64, batch);
}

test "ed25519: verify a batch of signatures using the BatchVerifier API" {
    const ed25519 = @import("ed25519-donna");

    const keys = try std.crypto.sign.Ed25519.KeyPair.create(null);

    const message = "hello world";
    const signature = try ed25519.sign(message, keys);

    var verifier: ed25519.BatchVerifier = .{};
    defer verifier.deinit(testing.allocator);

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        try verifier.add(testing.allocator, .{
            .public_key = &keys.public_key,
            .signature = &signature,
            .message = message,
        });
    }

    const results = try verifier.verify();
    try testing.expect(std.mem.allEqual(c_int, results, 1));
}
```

## Benchmarks

Single-threaded and multi-threaded benchmarks which compares the performance of these bindings to the Zig standard library's ed25519 implementation may be found [here](benchmarks/ed25519.zig).

For the single-threaded benchmarks, ed25519 signing, verification, and batch verification are performed 100,000 times. For the multi-threaded benchmarks, ed25519 signing, verification, and batch verification are performed 500,000 times.

The benchmarks make use of the generic thread pool implementation available in the source code of Zig's self-hosted compiler.

Results from running these benchmarks on my laptop may be found below. Take these benchmarks and results with a grain of salt.

```
$ cat /proc/cpuinfo | grep 'model name' | uniq
model name : Intel(R) Core(TM) i7-7700HQ CPU @ 2.80GHz

$ zig build bench -Drelease-fast
=== ed25519-std (single thread) ===

sign: took 6.0919 second(s)
sign: 16415.1814 signatures/sec

verify: took 7.5878 second(s)
verify: 13179.0926 signatures/sec

batch_verify(1): took 16.2880 second(s)
batch_verify(1): 6139.4747 signatures/sec

batch_verify(2): took 10.2503 second(s)
batch_verify(2): 9755.7721 signatures/sec

batch_verify(4): took 7.0835 second(s)
batch_verify(4): 14117.2217 signatures/sec

batch_verify(8): took 5.2012 second(s)
batch_verify(8): 19226.2152 signatures/sec

batch_verify(16): took 4.4654 second(s)
batch_verify(16): 22394.4535 signatures/sec

batch_verify(32): took 3.6738 second(s)
batch_verify(32): 27219.8045 signatures/sec

batch_verify(64): took 3.5673 second(s)
batch_verify(64): 28032.4098 signatures/sec

batch_verify(128): took 3.5383 second(s)
batch_verify(128): 28262.1541 signatures/sec

batch_verify(256): took 3.7326 second(s)
batch_verify(256): 26791.3165 signatures/sec

batch_verify(512): took 3.5267 second(s)
batch_verify(512): 28354.9587 signatures/sec

batch_verify(1024): took 3.6137 second(s)
batch_verify(1024): 27672.1112 signatures/sec

batch_verify(2048): took 3.7741 second(s)
batch_verify(2048): 26496.2290 signatures/sec

batch_verify(4096): took 4.0136 second(s)
batch_verify(4096): 24915.1312 signatures/sec

=== ed25519-std (multiple threads) ===

sign(1): took 8.4394 second(s)
sign(1): 59246.0867 signatures/sec

verify(1): took 10.4988 second(s)
verify(1): 47624.6976 signatures/sec

batch_verify(1): took 22.2592 second(s)
batch_verify(1): 22462.6215 signatures/sec

batch_verify(2): took 12.7288 second(s)
batch_verify(2): 39280.8696 signatures/sec

batch_verify(4): took 8.7091 second(s)
batch_verify(4): 57411.1779 signatures/sec

batch_verify(8): took 7.0137 second(s)
batch_verify(8): 71289.1977 signatures/sec

batch_verify(16): took 5.4052 second(s)
batch_verify(16): 92503.5592 signatures/sec

batch_verify(32): took 4.6896 second(s)
batch_verify(32): 106618.9187 signatures/sec

batch_verify(64): took 5.0738 second(s)
batch_verify(64): 98545.5489 signatures/sec

batch_verify(128): took 4.4141 second(s)
batch_verify(128): 113272.1161 signatures/sec

batch_verify(256): took 4.2404 second(s)
batch_verify(256): 117914.0667 signatures/sec

batch_verify(512): took 4.2700 second(s)
batch_verify(512): 117097.2778 signatures/sec

batch_verify(1024): took 4.5000 second(s)
batch_verify(1024): 111111.7824 signatures/sec

batch_verify(2048): took 4.9844 second(s)
batch_verify(2048): 100312.7273 signatures/sec

batch_verify(4096): took 4.7750 second(s)
batch_verify(4096): 104711.3968 signatures/sec

=== ed25519-donna (single thread) ===

sign: took 2.2230 second(s)
sign: 44985.2332 signatures/sec

verify: took 6.2735 second(s)
verify: 15940.1595 signatures/sec

batch_verify(1): took 6.0811 second(s)
batch_verify(1): 16444.2659 signatures/sec

batch_verify(2): took 6.3051 second(s)
batch_verify(2): 15860.2567 signatures/sec

batch_verify(4): took 5.1554 second(s)
batch_verify(4): 19397.3004 signatures/sec

batch_verify(8): took 4.1382 second(s)
batch_verify(8): 24165.0065 signatures/sec

batch_verify(16): took 3.6343 second(s)
batch_verify(16): 27515.2660 signatures/sec

batch_verify(32): took 3.3876 second(s)
batch_verify(32): 29519.5212 signatures/sec

batch_verify(64): took 3.1428 second(s)
batch_verify(64): 31818.7612 signatures/sec

batch_verify(128): took 3.3215 second(s)
batch_verify(128): 30107.2936 signatures/sec

batch_verify(256): took 3.1791 second(s)
batch_verify(256): 31455.2151 signatures/sec

batch_verify(512): took 3.3029 second(s)
batch_verify(512): 30276.1243 signatures/sec

batch_verify(1024): took 3.2536 second(s)
batch_verify(1024): 30735.0100 signatures/sec

batch_verify(2048): took 3.1686 second(s)
batch_verify(2048): 31559.9908 signatures/sec

batch_verify(4096): took 3.3008 second(s)
batch_verify(4096): 30295.6094 signatures/sec

=== ed25519-donna (multiple threads) ===

sign(1): took 2.4315 second(s)
sign(1): 205634.2979 signatures/sec

verify(1): took 6.9973 second(s)
verify(1): 71456.5081 signatures/sec

batch_verify(1): took 7.2783 second(s)
batch_verify(1): 68697.8065 signatures/sec

batch_verify(2): took 7.3983 second(s)
batch_verify(2): 67582.6513 signatures/sec

batch_verify(4): took 6.5533 second(s)
batch_verify(4): 76297.7575 signatures/sec

batch_verify(8): took 5.2693 second(s)
batch_verify(8): 94889.5635 signatures/sec

batch_verify(16): took 4.5523 second(s)
batch_verify(16): 109834.6577 signatures/sec

batch_verify(32): took 4.1214 second(s)
batch_verify(32): 121318.9474 signatures/sec

batch_verify(64): took 3.7905 second(s)
batch_verify(64): 131909.4312 signatures/sec

batch_verify(128): took 3.6549 second(s)
batch_verify(128): 136803.2566 signatures/sec

batch_verify(256): took 3.7900 second(s)
batch_verify(256): 131924.9328 signatures/sec

batch_verify(512): took 3.7148 second(s)
batch_verify(512): 134596.8465 signatures/sec

batch_verify(1024): took 3.7415 second(s)
batch_verify(1024): 133637.4161 signatures/sec

batch_verify(2048): took 3.7712 second(s)
batch_verify(2048): 132583.3362 signatures/sec

batch_verify(4096): took 3.7512 second(s)
batch_verify(4096): 133289.6401 signatures/sec
```