const std = @import("std");

const system = @import("system.zig");
const graphics = @import("graphics.zig");
const Window = @import("window.zig").Window;
const pointer = @import("pointer.zig");
const executable = @import("executable.zig");

pub const File = struct { content: std.ArrayList(u8) };

const Process = struct {
    program: []const u8,
    files: []File,

    /// Runs the process and returns a status code on exit.
    fn run(self: Process, allocator: std.mem.Allocator) !u8 {
        try executable.run(allocator, self.program, self.files);
        return 0;
    }
};

const Terminal = struct {
    process: Process,
    window: Window,

    fn draw(self: Terminal) !void {
        const stdout = self.process.files[1];

        try graphics.drawText(self.window.getContentPosition(), stdout.content.items, .{}, graphics.colors.SolidColor{ .color = graphics.colors.white });
    }
};

fn run_terminal(allocator: std.mem.Allocator, terminal: Terminal) void {
    _ = terminal.process.run(allocator) catch unreachable;
}

pub fn main() !void {
    // Allocators 101
    // - GPA: for debugging (or for convenience)
    // - Arena: when you allocate in a hot loop and free (or for convenience)
    // - Otherwise when you free manually (fastest): c_allocator or a custom allocator with a particular strategy etc.
    const allocator = if (@import("builtin").mode == .Debug) allocator: {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        break :allocator gpa.allocator();
    } else allocator: {
        break :allocator std.heap.c_allocator;
    };

    system.screen.init(.{ .width = 500, .height = 500 });

    const standard_files = &[_]File{
        .{ .content = std.ArrayList(u8).init(allocator) }, // stdin
        .{ .content = std.ArrayList(u8).init(allocator) }, // stdout
        .{ .content = std.ArrayList(u8).init(allocator) }, // stderr
    };

    var terminal = Terminal{
        .process = .{ .program = @embedFile("../hello.wasm"), .files = standard_files },
        .window = Window{
            .position = .{ .x = 10, .y = 20 },
            .size = .{ .width = 200, .height = 150 },
            .title = "title",
        },
    };

    _ = try std.Thread.spawn(.{}, run_terminal, .{ allocator, terminal });

    try graphics.init(allocator);

    while (true) {
        terminal.window.update();

        system.screen.startDrawing();
        defer system.screen.endDrawing();

        try terminal.window.draw();
        try terminal.draw();
        pointer.draw(system.pointer.getPosition());
    }
}
