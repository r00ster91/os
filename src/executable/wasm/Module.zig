//! Why use Wasm as the format for executables?
//! * Completely independent of hardware, architecture, platform, or language.
//!   Compile once, run anywhere.
//! * It is the most lightweight modern format that is in active use.
//!   The binary size is incredibly small and minimal compared to other modern executable formats, such as ELF, Mach-O, or COFF.
//! * Very fast and efficient parsing.
//!   Wasm can be parsed byte by byte right as it comes over the wire or out of a file etc.
//!
//! wasm32 is used. The reason is performance.
//! See also: https://webassembly.org/docs/faq/#why-have-wasm32-and-wasm64-instead-of-just-using-8-bytes-for-storing-pointers
//!
//! References:
//! * The specification:
//!   https://webassembly.github.io/spec/core/_download/WebAssembly.pdf
//!   I recommend downloading and viewing it locally because it is quite big.
//! * The official specification is quite formal and hard to understand,
//!   so there is also this:
//!   https://github.com/sunfishcode/wasm-reference-manual/blob/master/WebAssembly.md
//! * A tool that explains the meaning of each byte:
//!   https://webassembly.github.io/wabt/demo/wat2wasm
//! * wasm2wat
//! * https://github.com/ziglang/zig/blob/master/src/link/Wasm/Object.zig

const std = @import("std");
const wasm = std.wasm;
const mem = std.mem;
const log = std.log;

const Module = @This();

types: []wasm.Type = &.{},
imports: []wasm.Import = &.{},
functions: []wasm.Func = &.{},
// tables: [] wasm.Table = &.{},
memories: []wasm.Memory = &.{},
globals: []wasm.Global = &.{},
exports: []wasm.Export = &.{},
codes: []Code = &.{},
data_segments: []DataSegment = &.{},

pub fn deinit(self: Module, allocator: mem.Allocator) void {
    for (self.types) |*@"type"| {
        allocator.free(@"type".params);
        allocator.free(@"type".returns);
    }
    allocator.free(self.types);
    for (self.imports) |*import| {
        allocator.free(import.module_name);
        allocator.free(import.name);
    }
    allocator.free(self.imports);
    allocator.free(self.functions);
    allocator.free(self.memories);
    allocator.free(self.globals);
    for (self.exports) |*@"export"| {
        allocator.free(@"export".name);
    }
    allocator.free(self.exports);
    for (self.codes) |*code| {
        allocator.free(code.bytes);
        for (code.local_declaration_groups) |local_declaration_group| {
            allocator.free(local_declaration_group);
        }
        allocator.free(code.local_declaration_groups);
    }
    allocator.free(self.codes);
    for (self.data_segments) |*data_segment| {
        allocator.free(data_segment.data.data);
    }
    allocator.free(self.data_segments);
}

pub const Code = struct {
    local_declaration_groups: []const LocalDeclaration,
    /// The bytes, excluding the terminating `wasm.opcode(.end)`.
    bytes: []const u8,

    const LocalDeclaration = []const wasm.Valtype;
};
const DataSegment = union(enum) {
    data: struct { address: i32, data: []const u8 },
    todo1,
    todo2,
};

pub fn parse(allocator: mem.Allocator, bytes: []const u8) !Module {
    var parser = Parser{ .bytes = bytes, .allocator = allocator };
    return parser.parse();
}

const Parser = struct {
    bytes: []const u8,
    allocator: mem.Allocator,

    module: Module = .{},

    fn parse(self: *Parser) !Module {
        try self.parseModule();
        return self.module;
    }

    const ModuleParsingError = error{ NoMagicNumber, NoVersionNumber };

    fn parseModule(self: *Parser) (ModuleParsingError || anyerror)!void {
        self.skipSlice(&wasm.magic) catch return error.NoMagicNumber;
        self.skipSlice(&wasm.version) catch return error.NoVersionNumber;
        while (true) {
            const done = try self.parseSection();
            if (done)
                break;
        }
    }

    const Section = union(enum) { types: []const wasm.Type, functions: []const wasm.Func };

    /// Parses a section and returns whether or not all sections have been parsed.
    ///
    /// Non-custom sections occur at most once and in a prescribed order.
    fn parseSection(self: *Parser) !bool {
        const id = self.readByte() catch |err| if (err == error.EndReached) return true;
        const length = try self.readLength();
        log.debug("Parsing section {} of length {}", .{ @intToEnum(wasm.Section, id), length });
        switch (id) {
            wasm.section(.custom) => try self.parseCustomSection(length),
            wasm.section(.type) => try self.parseTypeSection(),
            wasm.section(.import) => try self.parseImportSection(),
            wasm.section(.function) => try self.parseFunctionSection(),
            wasm.section(.table) => unreachable,
            wasm.section(.memory) => try self.parseMemorySection(),
            wasm.section(.global) => try self.parseGlobalSection(),
            wasm.section(.@"export") => try self.parseExportSection(),
            wasm.section(.start) => {
                // This decodes into a start function index which references
                // a certain function to be ran on startup (like the `main`).
                // The problem is that during the time this function runs,
                // module exports can not be used.
                // Because of that this section is not very useful and we ignore it.
                // See also: https://github.com/WebAssembly/tool-conventions/blob/main/Linking.md#start-section
                const start_function_index = try self.readInteger(u32);
                _ = start_function_index;
            },
            wasm.section(.element) => unreachable,
            wasm.section(.code) => try self.parseCodeSection(),
            wasm.section(.data) => try self.parseDataSection(),
            wasm.section(.data_count) => unreachable,
            else => return error.InvalidSectionId,
        }
        log.debug("Parsed section {}", .{@intToEnum(wasm.Section, id)});
        return false;
    }

    fn parseCustomSection(self: *Parser, length: u32) !void {
        const previous_index = @ptrToInt(self.bytes.ptr);
        const name = try self.readName();
        defer self.allocator.free(name);
        const name_length = @ptrToInt(self.bytes.ptr) - previous_index;

        log.debug("Skipping custom section {s}", .{name});

        const bytes_length = length - name_length;
        self.bytes = self.bytes[bytes_length..];
    }

    fn parseTypeSection(self: *Parser) !void {
        for (try self.readVector(&self.module.types)) |*function_type| {
            try self.skipByte(wasm.function_type);
            for (try self.readVector(&function_type.params)) |*result_type|
                result_type.* = try std.meta.intToEnum(wasm.Valtype, try self.readByte());
            for (try self.readVector(&function_type.returns)) |*result_type|
                result_type.* = try std.meta.intToEnum(wasm.Valtype, try self.readByte());
        }
    }

    fn parseImportSection(self: *Parser) !void {
        for (try self.readVector(&self.module.imports)) |*import| {
            import.* = wasm.Import{
                .module_name = try self.readName(),
                .name = try self.readName(),
                .kind = kind: {
                    try self.skipByte(0); // FIXME
                    break :kind wasm.Import.Kind{ .function = try self.readInteger(u32) };
                },
            };
        }
    }

    fn parseFunctionSection(self: *Parser) !void {
        for (try self.readVector(&self.module.functions)) |*function|
            function.* = wasm.Func{ .type_index = try self.readByte() };
    }

    fn parseMemorySection(self: *Parser) !void {
        for (try self.readVector(&self.module.memories)) |*memory| {
            const flags = try self.readInteger(u32);

            const min = try self.readInteger(u32);

            const max = if (flags == 1) try self.readInteger(u32) else null;

            memory.* = wasm.Memory{ .limits = .{ .min = min, .max = max } };
        }
    }

    fn parseGlobalSection(self: *Parser) !void {
        for (try self.readVector(&self.module.globals)) |*global| {
            const global_type = wasm.GlobalType{
                .valtype = try std.meta.intToEnum(wasm.Valtype, try self.readByte()),
                .mutable = (try self.readByte()) == 1,
            };

            // This is also called a constant expression
            const init_expression: wasm.InitExpression = switch (try self.readByte()) {
                wasm.opcode(.i32_const) => .{ .i32_const = try self.readInteger(i32) },
                wasm.opcode(.i64_const) => .{ .i64_const = try self.readInteger(i64) },
                wasm.opcode(.f32_const) => unreachable, //.{ .f32_const = try self.readInteger(f32) },
                wasm.opcode(.f64_const) => unreachable, //.{ .f64_const = try self.readInteger(f64) },
                wasm.opcode(.global_get) => unreachable,
                else => return error.InvalidInitExpressionOpcode,
            };
            global.* = wasm.Global{ .global_type = global_type, .init = init_expression };
        }
        try self.skipByte(@enumToInt(wasm.Opcode.end));
    }

    fn parseExportSection(self: *Parser) !void {
        for (try self.readVector(&self.module.exports)) |*code|
            code.* = wasm.Export{
                .name = try self.readName(),
                .kind = try std.meta.intToEnum(wasm.ExternalKind, try self.readByte()),
                .index = try self.readInteger(u32),
            };
    }

    fn parseCodeSection(self: *Parser) !void {
        for (try self.readVector(&self.module.codes)) |*code| {
            var function_body_size = try self.readLength();
            function_body_size -= 1;
            for (try self.readVector(&code.local_declaration_groups)) |*local_declaration_group| {
                function_body_size -= 1;
                for (try self.readVector(local_declaration_group)) |*local_declaration| {
                    function_body_size -= 1;
                    local_declaration.* = try std.meta.intToEnum(wasm.Valtype, try self.readByte());
                }
            }
            for (try self.readVectorWithLength(&code.bytes, function_body_size)) |*byte|
                byte.* = try self.readByte();
        }
    }

    fn parseDataSection(self: *Parser) !void {
        for (try self.readVector(&self.module.data_segments)) |*data_segment| {
            try self.skipByte(0); // FIXME: assuming `.data` for flag
            data_segment.* = .{
                .data = .{
                    .address = address: {
                        try self.skipByte(wasm.opcode(.i32_const)); // FIXME
                        const address = try self.readInteger(i32);
                        try self.skipByte(wasm.opcode(.end));
                        break :address address;
                    },
                    .data = try self.readBytes(),
                },
            };
        }
    }

    // fn readExpression(self: *Parser) ![]const wasm.Opcode {
    //     var opcodes = std.ArrayList(wasm.Opcode).init(self.allocator);
    //     while (true) {
    //         const opcode = try std.meta.intToEnum(wasm.Opcode, try self.readByte());
    //         if (opcode == .end) return opcodes.items;
    //         try opcodes.append(opcode);
    //     }
    // }

    fn readBytes(self: *Parser) ![]const u8 {
        return self.readName();
    }

    /// Reads a string.
    // FIXME: validate UTF-8?
    fn readName(self: *Parser) ![]const u8 {
        const length = try self.readLength();
        var name = try self.allocator.alloc(u8, length);
        var index: usize = 0;
        while (index < length) : (index += 1)
            name[index] = try self.readByte();
        return name;
    }

    fn readLength(self: *Parser) !u32 {
        return self.readInteger(u32);
    }

    /// Reads a vector's length and returns a slice.
    fn readVector(self: *Parser, pointer: anytype) ![]ElementType(@TypeOf(pointer)) {
        const length = try self.readLength();
        const slice = try self.allocator.alloc(ElementType(@TypeOf(pointer)), length);
        pointer.* = slice;
        return slice;
    }

    fn readVectorWithLength(self: *Parser, pointer: anytype, length: usize) ![]ElementType(@TypeOf(pointer)) {
        const slice = try self.allocator.alloc(ElementType(@TypeOf(pointer)), length);
        pointer.* = slice;
        return slice;
    }

    fn ElementType(comptime Pointer: type) type {
        const NonPointer = std.meta.Child(Pointer);
        return std.meta.Elem(NonPointer);
    }

    /// Reads a LEB128 (Little Endian Base 128) value.
    fn readInteger(self: *Parser, comptime T: type) !T {
        var stream = std.io.fixedBufferStream(self.bytes);
        const value = if (comptime std.meta.trait.isUnsignedInt(T))
            std.leb.readULEB128(T, stream.reader())
        else
            std.leb.readILEB128(T, stream.reader());
        self.bytes = self.bytes[stream.pos..];
        log.debug("Parsed LEB128 value {}", .{value});
        return value;
    }

    fn readByte(self: *Parser) error{EndReached}!u8 {
        if (self.bytes.len >= 1) {
            const byte = self.bytes[0];
            log.debug("Advancing from byte {any}", .{byte});
            self.bytes = self.bytes[1..];
            return byte;
        } else {
            return error.EndReached;
        }
    }

    fn skipSlice(self: *Parser, bytes: []const u8) error{NotEqual}!void {
        if (mem.startsWith(u8, self.bytes, bytes)) {
            log.debug("Skipping bytes {any}", .{bytes});
            self.bytes = self.bytes[bytes.len..];
        } else {
            return error.NotEqual;
        }
    }

    fn skipByte(self: *Parser, byte: u8) error{NotEqual}!void {
        return self.skipSlice(&[_]u8{byte});
    }
};
