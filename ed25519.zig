const std = @import("std");
const c = @cImport(@cInclude("ed25519.h"));

const testing = std.testing;

/// Sign a message given an Ed25519 keypair, yielding an Ed25519 signature.
pub inline fn sign(message: []const u8, key_pair: std.crypto.sign.Ed25519.KeyPair) ![64]u8 {
    var signature: [64]u8 = undefined;
    c.ed25519_sign(message.ptr, message.len, &key_pair.secret_key, &key_pair.public_key, &signature);
    return signature;
}

/// Verify an Ed25519 signature given a message and Ed25519 public key.
pub inline fn verify(signature: [64]u8, message: []const u8, public_key: [32]u8) !void {
    if (c.ed25519_sign_open(message.ptr, message.len, &public_key, &signature) != 0) {
        return error.SignatureVerificationFailed;
    }
}

/// Verify a batch of Ed25519 signatures given a batch of messages and Ed25519 public keys.
///
/// This method is provided to maintain API compatibility with the Zig standard library's implementation
/// of Ed25519 batch signature verification. It is recommended to use `BatchVerifier` instead, as it
/// reports which of the signatures out of the batch of signatures provided have failed verification.
pub inline fn verifyBatch(comptime count: usize, signature_batch: [count]std.crypto.sign.Ed25519.BatchElement) !void {
    var public_keys: [count]*const [32]u8 = undefined;
    var signatures: [count]*const [64]u8 = undefined;
    var message_ptrs: [count][*]const u8 = undefined;
    var message_lens: [count]usize = undefined;
    var results: [count]c_int = undefined;

    for (signature_batch) |*element, i| {
        public_keys[i] = &element.public_key;
        signatures[i] = &element.sig;
        message_ptrs[i] = element.msg.ptr;
        message_lens[i] = element.msg.len;
    }

    const rc = c.ed25519_sign_open_batch(
        @ptrCast([*c][*c]const u8, &message_ptrs),
        &message_lens,
        @ptrCast([*c][*c]const u8, &public_keys),
        @ptrCast([*c][*c]const u8, &signatures),
        count,
        &results,
    );
    if (rc != 0) {
        return error.SignatureVerificationFailed;
    }
}

/// Maintains a batch of Ed25519 signatures, message, and Ed25519 public keys that are to be batch-verified.
/// Unlike the `verifyBatch` method, a `BatchVerifier` reports which of the signatures out of the batch of
/// signatures provided have failed veriifcation. 
pub const BatchVerifier = struct {
    const Entry = struct {
        public_key: *const [32]u8,
        signature: *const [64]u8,
        message_ptr: [*]const u8,
        message_len: usize,
        result: c_int,
    };

    entries: std.MultiArrayList(Entry) = .{},

    /// Deinitializes and frees all elements appended to this verifiers batch.
    pub fn deinit(self: *BatchVerifier, allocator: *std.mem.Allocator) void {
        self.entries.deinit(allocator);
    }

    /// Append a Ed25519 signature, message, and Ed25519 public key to this verifiers batch.
    pub fn add(self: *BatchVerifier, allocator: *std.mem.Allocator, entry: struct {
        public_key: *const [32]u8,
        signature: *const [64]u8,
        message: []const u8,
    }) !void {
        try self.entries.append(allocator, .{
            .public_key = entry.public_key,
            .signature = entry.signature,
            .message_ptr = entry.message.ptr,
            .message_len = entry.message.len,
            .result = undefined,
        });
    }

    /// Verify all Ed25519 signatures, messages, and Ed25519 public keys appended to this verifiers
    /// batch `x`.
    ///
    /// It returns a slice of c_int's `y` where y[i] = 1 if x[i] passed signature verification, and
    /// y[i] = 0 if x[i] failed signature verification where i is an index of `x`. 
    pub fn verify(self: *BatchVerifier) ![]const c_int {
        const slice = self.entries.slice();
        const results = slice.items(.result);

        const rc = c.ed25519_sign_open_batch(
            @ptrCast([*c][*c]const u8, slice.items(.message_ptr).ptr),
            slice.items(.message_len).ptr,
            @ptrCast([*c][*c]const u8, slice.items(.public_key).ptr),
            @ptrCast([*c][*c]const u8, slice.items(.signature).ptr),
            slice.len,
            results.ptr,
        );
        if (rc != 0) {
            return error.SignatureVerificationFailed;
        }

        return results;
    }
};

test {
    testing.refAllDecls(@This());
}

test "ed25519: sign and verify a message" {
    const ed25519 = @This();

    const keys = try std.crypto.sign.Ed25519.KeyPair.create(null);

    const message = "hello world";
    const signature = try ed25519.sign(message, keys);
    try ed25519.verify(signature, message, keys.public_key);
}

test "ed25519: verify a batch of signatures using verifyBatch()" {
    const ed25519 = @This();

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
    const ed25519 = @This();

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
