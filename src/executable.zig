const std = @import("std");
const Module = @import("executable/wasm/Module.zig");
const executor = @import("executable/executor.zig");
const File = @import("main.zig").File;

const identifier = std.wasm.magic ++ std.wasm.version;

pub fn run(allocator: std.mem.Allocator, bytes: []const u8, files: [] File) !void {
    const module = try Module.parse(allocator, bytes);
    defer module.deinit(allocator);
    try executor.run(allocator, module, files);
}
