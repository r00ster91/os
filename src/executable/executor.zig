//! https://pengowray.github.io/wasm-ops/
//! https://github.com/WebAssembly/wasi-libc/blob/main/libc-bottom-half/headers/public/wasi/api.h
//! Also use `std.os.wasi` as a reference.

const std = @import("std");
const wasm = std.wasm;
const log = std.log;
const mem = std.mem;
const Module = @import("wasm/Module.zig");
const File = @import("../main.zig").File;
const assert = std.debug.assert;

pub fn run(allocator: mem.Allocator, module: Module, files: []File) !void {
    const functions = try allocator.alloc(Function, module.codes.len);
    defer allocator.free(functions);
    for (module.codes) |code, index| {
        const @"type" = module.types[module.types.len - 1 - index];
        functions[index] = .{ .type = @"type", .code = code };
    }

    var start_function_index = for (module.exports) |@"export"| {
        if (@"export".kind == .function and std.mem.eql(u8, @"export".name, "_start")) {
            break @"export".index;
        }
    } else return error.NoStartFunction;
    start_function_index -= @intCast(u32, module.imports.len);

    const start_function = functions[start_function_index];
    std.debug.print("{any}\n", .{start_function});
    var stream = std.io.fixedBufferStream(start_function.code.bytes);

    const globals = try instantiateGlobals(allocator, module);
    defer allocator.free(globals);

    const locals = try instantiateLocals(allocator, start_function.code);
    defer allocator.free(locals);

    const memory = try instantiateMemory(allocator, module);
    defer if (memory) |usable_memory|
        allocator.free(usable_memory);

    return interpret(allocator, stream.reader(), files, module, memory, globals, locals);
}

const Function = struct { type: wasm.Type, code: Module.Code };

const Global = struct { value: Value, mutable: bool };

fn instantiateGlobals(allocator: mem.Allocator, module: Module) ![]Global {
    var globals = try allocator.alloc(Global, module.globals.len);
    var index: usize = 0;
    for (module.globals) |global| {
        globals[index] = .{
            .value = switch (global.init) {
                .i32_const => |value| .{ .i32 = value },
                else => unreachable,
            },
            .mutable = global.global_type.mutable,
        };
    }
    return globals;
}

fn instantiateLocals(allocator: mem.Allocator, code: Module.Code) ![]Value {
    var locals_length: usize = 0;
    for (code.local_declaration_groups) |local_declaration_group|
        locals_length += local_declaration_group.len;
    var locals = try allocator.alloc(Value, locals_length);
    var index: usize = 0;
    for (code.local_declaration_groups) |local_declaration_group|
        for (local_declaration_group) |local_declaration| {
            locals[index] = switch (local_declaration) {
                .i32 => .{ .i32 = 0 },
                .i64 => .{ .i64 = 0 },
                .f32 => .{ .f32 = 0 },
                .f64 => .{ .f64 = 0 },
            };
            index += 1;
        };
    return locals;
}

fn instantiateMemory(allocator: mem.Allocator, module: Module) !?[]u8 {
    if (module.memories.len == 0) {
        return null;
    } else if (module.memories.len == 1) {
        const memory_limits = module.memories[0].limits;
        // `memory_limits.min` defines the initial amount of memory.
        // `memory_limits.max` defines the maximum amount of memory that can be grown to.

        if (memory_limits.max) |_| @panic("memory max limit currently unsupported");

        // https://github.com/ziglang/zig/issues/11559#issuecomment-1115857943
        var memory = try allocator.alloc(u8, wasm.page_size * memory_limits.min);
        std.mem.set(u8, memory, 0);

        // Active data segments are loaded into memory automatically.
        // Passive data segments have to be loaded by the user.
        for (module.data_segments) |data_segment| {
            log.debug("{}", .{data_segment.data.data.len});
            const address = @intCast(usize, data_segment.data.address);
            std.mem.copy(
                u8,
                memory[address .. address + data_segment.data.data.len],
                data_segment.data.data,
            );
        }
        return memory;
    } else {
        return error.MoreThanOneMemory;
    }
}

/// Reads a LEB128 (Little Endian Base 128) value.
fn readInteger(reader: anytype, comptime T: type) !T {
    if (comptime std.meta.trait.isUnsignedInt(T))
        return std.leb.readULEB128(T, reader)
    else
        return std.leb.readILEB128(T, reader);
}

const Value = union(enum) { i32: i32, i64: i64, f32: f32, f64: f64 };

const Stack = struct {
    values: std.ArrayList(Value),

    fn init(allocator: mem.Allocator) Stack {
        return Stack{ .values = std.ArrayList(Value).init(allocator) };
    }

    fn deinit(self: *Stack) void {
        self.values.deinit();
    }

    fn push(self: *Stack, value: Value) !void {
        return self.values.append(value);
    }

    fn pushError(self: *Stack, @"error": std.os.wasi.errno_t) !void {
        try self.push(.{ .i32 = @enumToInt(@"error") });
    }

    fn popType(self: *Stack) !Value {
        return self.values.popOrNull() orelse error.StackUnderflow;
    }

    fn pop(self: *Stack, comptime T: type) !T {
        const value = try self.popType();
        switch (value) {
            .i32 => |actual_value| if (T == i32) return actual_value,
            .i64 => |actual_value| if (T == i64) return actual_value,
            .f32 => |actual_value| if (T == f32) return actual_value,
            .f64 => |actual_value| if (T == f64) return actual_value,
        }
        return error.InvalidType;
    }

    fn peek(self: Stack) !Value {
        if (self.values.items.len == 0) return error.StackUnderflow;
        return self.values.items[self.values.items.len - 1];
    }
};

fn interpret(allocator: mem.Allocator, reader: anytype, files: []File, module: Module, memory: ?[]u8, globals: []Global, locals: []Value) anyerror!void {
    log.debug("Interpreting Wasm", .{});
    var stack = Stack.init(allocator);
    defer stack.deinit();
    while (reader.readByte()) |byte| {
        log.debug("Evaluating {any} ({})", .{ @intToEnum(wasm.Opcode, byte), byte });
        switch (byte) {
            wasm.opcode(.@"unreachable") => {
                log.info("Unreachable condition reached", .{});
                return;
            },
            wasm.opcode(.call) => {
                const callee = try readInteger(reader, u32);
                const function = module.imports[callee];
                const name = function.name;

                const eql = std.mem.eql;
                if (eql(u8, name, "proc_exit")) {
                    log.info("Exiting with status code {}", .{try stack.pop(i32)});
                    return;
                } else if (eql(u8, name, "fd_write")) {
                    const usable_memory = memory orelse return error.NoMemory;

                    const written_pointer = try stack.pop(i32); // FIXME: u64 on wasm64
                    const iovs_length = try stack.pop(i32); // FIXME: u64 on wasm64
                    const iovs_pointer = try stack.pop(i32); // FIXME: u64 on wasm64
                    const fd = try stack.pop(i32);

                    std.debug.assert(iovs_length == 1); // FIXME

                    const memory_reader = std.io.fixedBufferStream(usable_memory[@intCast(u32, iovs_pointer)..]).reader();

                    const base = try memory_reader.readIntLittle(u32); // FIXME: u64 on wasm64
                    const length = try memory_reader.readIntLittle(u32); // FIXME: u64 on wasm64

                    // FIXME
                    const string = mem.trimRight(
                        u8,
                        usable_memory[base .. base + length],
                        "\u{0}",
                    );

                    if (fd < files.len) {
                        var file = &files[@intCast(u32, fd)];
                        file.content.appendSlice(string) catch |@"error"| {
                            switch (@"error") {
                                error.OutOfMemory => try stack.pushError(.NOMEM),
                            }
                            continue;
                        };

                        const memory_writer = std.io.fixedBufferStream(usable_memory[@intCast(u32, written_pointer)..]).writer();
                        try memory_writer.writeIntLittle(i32, @intCast(i32, string.len));

                        try stack.pushError(.SUCCESS);
                    } else {
                        try stack.pushError(.BADF);
                    }
                } else if (eql(u8, name, "poll_oneoff")) {
                    const usable_memory = memory orelse return error.NoMemory;

                    const nevents = try stack.pop(i32); // FIXME: u64 on wasm64
                    const nsubscriptions = try stack.pop(i32); // FIXME: u64 on wasm64
                    const out = try stack.pop(i32); // FIXME: u64 on wasm64
                    const in = try stack.pop(i32);

                    _ = out; // FIXME
                    _ = nevents; // FIXME

                    const memory_reader = std.io.fixedBufferStream(usable_memory[@intCast(u32, in)..]).reader();

                    std.debug.assert(nsubscriptions == 1); // FIXME

                    const subscription = try memory_reader.readStruct(std.os.wasi.subscription_t);

                    _ = subscription.userdata;

                    switch (subscription.u.tag) {
                        0 => {
                            const clock = subscription.u.u.clock;
                            _ = clock.id;
                            std.time.sleep(clock.timeout);
                            assert(clock.precision == 0);
                            assert(clock.flags == 0);
                            try stack.pushError(.SUCCESS);
                        },
                        1 => unreachable,
                        2 => unreachable,
                        else => unreachable,
                    }
                } else {
                    @panic("unknown function");
                }
            },
            wasm.opcode(.global_get) => {
                const global = module.globals[try readInteger(reader, u32)];
                switch (global.init) {
                    .i32_const => |value| try stack.push(.{ .i32 = value }),
                    else => unreachable,
                }
            },
            wasm.opcode(.i32_const) => {
                try stack.push(.{ .i32 = try readInteger(reader, i32) });
            },
            wasm.opcode(.i64_const) => {
                try stack.push(.{ .i64 = try readInteger(reader, i64) });
            },
            wasm.opcode(.i32_sub) => {
                const subtrahend = try stack.pop(i32);
                const minuend = try stack.pop(i32);
                var result: i32 = undefined;
                _ = @subWithOverflow(i32, minuend, subtrahend, &result);
                try stack.push(.{ .i32 = result });
            },
            wasm.opcode(.i32_add) => {
                const augend = try stack.pop(i32);
                const addend = try stack.pop(i32);
                var result: i32 = undefined;
                _ = @addWithOverflow(i32, augend, addend, &result);
                try stack.push(.{ .i32 = result });
            },
            wasm.opcode(.local_get) => {
                try stack.push(locals[try readInteger(reader, u32)]);
            },
            wasm.opcode(.local_tee) => {
                locals[try readInteger(reader, u32)] = try stack.peek();
            },
            wasm.opcode(.global_set) => {
                var global = globals[try readInteger(reader, u32)];
                if (!global.mutable) return error.MutatingNonMutableGlobal;
                global.value = try stack.popType();
            },
            wasm.opcode(.i32_store) => try store(&stack, reader, memory, i32, i32),
            wasm.opcode(.i32_store8) => try store(&stack, reader, memory, i32, i8),
            wasm.opcode(.i32_store16) => try store(&stack, reader, memory, i32, i16),
            wasm.opcode(.i64_store) => try store(&stack, reader, memory, i64, i64),
            wasm.opcode(.i32_load) => {
                const usable_memory = memory orelse return error.NoMemory;

                const alignment = try readInteger(reader, u32);
                const offset = try readInteger(reader, u32); // FIXME: on wasm64 this would be u64

                const base = try stack.pop(i32); // FIXME: on wasm64 this would be i64

                const address = try getAddress(offset, base, alignment);
                if (address > usable_memory.len) return error.OutOfBounds;

                const memory_reader = std.io.fixedBufferStream(usable_memory[address..]).reader();
                try stack.push(.{ .i32 = try memory_reader.readIntLittle(i32) });
            },
            wasm.opcode(.drop) => {
                _ = try stack.popType();
            },
            wasm.opcode(.end) => {
                log.debug("Final stack: {any}", .{stack.values.items});
                return;
            },
            wasm.opcode(.loop) => {
                const block_type_byte = try reader.readByte();
                if (block_type_byte == 0x40) {
                    const block_type = .void;
                    _ = block_type;
                    try interpret(allocator, reader, files, module, memory, globals, locals);
                } else unreachable;
            },
            wasm.opcode(.br) => {
                const break_depth = try reader.readByte();
                _ = break_depth; // FIXME
                reader.context.pos = 0; // FIXME
            },
            else => unreachable,
        }
    } else |@"error"| return @"error";
}

fn store(
    stack: *Stack,
    reader: anytype,
    memory: ?[]u8,
    from: type,
    to: type,
) !void {
    log.debug("{} {}", .{ from, to });

    const usable_memory = memory orelse return error.NoMemory;

    const alignment = try readInteger(reader, u32);
    const offset = try readInteger(reader, u32); // FIXME: on wasm64 this would be u64

    const value = @truncate(to, try stack.pop(from));
    const base = try stack.pop(i32); // FIXME: on wasm64 this would be i64

    const address = try getAddress(offset, base, alignment);
    if (address > usable_memory.len) return error.OutOfBounds;

    const memory_writer = std.io.fixedBufferStream(usable_memory[address..]).writer();
    try memory_writer.writeIntLittle(to, value);
}

fn getAddress(offset: u32, base: i32, encoded_alignment: u32) !u32 {
    // Alignment is optional but useful for performance reasons
    const unaligned_address = @intCast(u32, @intCast(i32, offset) + base); // FIXME: should we wrap on overflow?

    const decoded_alignment = try std.math.powi(u32, 2, encoded_alignment);

    log.debug("Address offset: {}, base: {}, alignment: {}", .{ offset, base, decoded_alignment });

    const aligned_address = @intCast(u32, mem.alignBackward(unaligned_address, decoded_alignment));
    return aligned_address;
}
