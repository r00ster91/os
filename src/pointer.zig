//! The pointing device.

const std = @import("std");

const system = @import("system.zig");
const graphics = @import("graphics.zig");
const Position = system.Position;
const Size = system.Size;
const Color = system.Color;

const size: usize = 9;

comptime {
    std.debug.assert(size % 2 == 1);
}

pub fn draw(position: Position) void {
    graphics.drawVerticalLine(.{ .x = position.x, .y = position.y -| size / 2 }, size, graphics.colors.InvertedColor{});
    graphics.drawHorizontalLine(.{ .x = position.x -| size / 2, .y = position.y }, size, graphics.colors.InvertedColor{});
}
