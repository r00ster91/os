const std = @import("std");

const system = @import("../system.zig");
const Position = system.Position;
const Size = system.Size;
const Color = system.Color;

const raylib = @cImport({
    @cInclude("raylib.h");
});

pub const screen = struct {
    var size: Size = undefined;
    var framebuffer: [1024 * 1024]Color = undefined;

    pub fn init(new_size: Size) void {
        size = new_size;

        raylib.SetTraceLogLevel(4); // enable warnings and higher-ranked logs

        raylib.InitWindow(@intCast(c_int, size.width), @intCast(c_int, size.height), "OS");

        raylib.HideCursor();

        raylib.SetWindowState(0x00000004); // make the window resizable

        raylib.SetTargetFPS(60);
    }

    pub fn startDrawing() void {
        raylib.BeginDrawing();
        raylib.ClearBackground(.{ .r = 0, .g = 0, .b = 0, .a = 255 });

        framebuffer = std.mem.zeroes(@TypeOf(framebuffer));
    }

    fn getIndex(position: Position) usize {
        return position.x + size.width * position.y;
    }

    pub fn drawPixel(position: Position, color: Color) void {
        raylib.DrawPixel(
            @intCast(c_int, position.x),
            @intCast(c_int, position.y),
            .{ .r = color.r, .g = color.g, .b = color.b, .a = 255 },
        );
        framebuffer[getIndex(position)] = color;
    }

    // pub fn drawFilledRectangle(position: Position, size: Size, color: Color) void {
    //     raylib.DrawRectangle(
    //         @intCast(c_int, position.x),
    //         @intCast(c_int, position.y),
    //         @intCast(c_int, size.width),
    //         @intCast(c_int, size.height),
    //         .{ .r = color.r, .g = color.g, .b = color.b, .a = 255 },
    //     );
    // }

    // pub fn drawStraightLine(start_position: Position, end_position: Position, color: Color) void {
    //     raylib.DrawLine(
    //         @intCast(c_int, start_position.x),
    //         @intCast(c_int, start_position.y),
    //         @intCast(c_int, end_position.x),
    //         @intCast(c_int, end_position.y),
    //         .{ .r = color.r, .g = color.g, .b = color.b, .a = 255 },
    //     );
    // }

    pub fn getPixel(position: Position) Color {
        return framebuffer[getIndex(position)];
    }

    pub fn endDrawing() void {
        raylib.EndDrawing();
    }

    pub fn deinit() void {
        raylib.CloseWindow();
    }
};

pub const pointer = struct {
    pub fn getPosition() Position {
        const mouse_position = raylib.GetMousePosition();
        return .{ .x = @floatToInt(usize, @maximum(0, mouse_position.x)), .y = @floatToInt(usize, @maximum(0, mouse_position.y)) };
    }

    pub fn isPressed() bool {
        return raylib.IsMouseButtonDown(0);
    }
};
