// hello.wasm:  zig build-exe -target wasm32-freestanding-none -O ReleaseSmall hello.zig
//              zig build-exe -target wasm32-wasi-none -O ReleaseSmall hello.zig

const std = @import("std");

/// Prints "hello" every second.
pub fn main() !void {
    while (true) {
        _ = std.io.getStdOut().write("hello") catch unreachable;
        std.time.sleep(std.time.ns_per_s);
    }
}
