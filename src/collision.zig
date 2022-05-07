const std = @import("std");

const system = @import("system.zig");
const Position = system.Position;
const Size = system.Size;
const graphics = @import("graphics.zig");

pub fn isPointInRectangle(point_position: Position, rectangle_position: Position, rectangle_size: Size) bool {
    return point_position.x >= rectangle_position.x and point_position.y >= rectangle_position.y and // Top-left sides
        point_position.x < rectangle_position.x + rectangle_size.width and // Bottom-right sides
        point_position.y < rectangle_position.y + rectangle_size.height;
}

pub const Rectangle = struct {
    position: Position,
    size: Size,

    fn draw(self: Rectangle) void {
        graphics.drawOutlinedRectangle(self.position, self.size, graphics.colors.SolidColor{ .color = graphics.colors.green });
    }

    pub fn touchesPoint(self: Rectangle, point_position: Position) bool {
        if (@import("builtin").mode == .Debug) self.draw();
        return isPointInRectangle(point_position, self.position, self.size);
    }
};
