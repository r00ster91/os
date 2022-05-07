const std = @import("std");

const system = @import("system.zig");
const graphics = @import("graphics.zig");
const Position = system.Position;
const Size = system.Size;
const Color = system.Color;
const collision = @import("collision.zig");

const DraggableRectangle = struct {
    /// This is updated continuously.
    collision_rectangle: collision.Rectangle = undefined,
    dragged: bool = false,

    fn init(position: Position, size: Size) DraggableRectangle {
        return DraggableRectangle{ .collision_rectangle = .{ .position = position, .size = size } };
    }

    /// Updates the draggable and returns whether it is dragged.
    fn update(self: *DraggableRectangle) bool {
        if (system.pointer.isPressed()) {
            if (self.collision_rectangle.touchesPoint(system.pointer.getPosition()))
                self.dragged = true;
        } else {
            self.dragged = false;
        }
        return self.dragged;
    }
};

pub const Window = struct {
    position: Position,
    size: Size,
    title: []const u8,

    previous_pointer_position: Position = .{},

    draggable_handle: DraggableRectangle = .{},
    bottom_resizer: DraggableRectangle = .{},
    bottom_right_resizer: DraggableRectangle = .{},
    bottom_left_resizer: DraggableRectangle = .{},

    const handle_height = 10;
    const resizer_size = 5;

    pub fn draw(self: Window) !void {
        // Handle
        graphics.drawFilledRectangle(
            self.position,
            .{ .width = self.size.width, .height = handle_height },
            graphics.colors.SolidColor{ .color = graphics.colors.gray },
        );
        try graphics.drawText(
            .{
                .x = self.position.x + self.size.width / 2 - (try graphics.getTextSize(self.title)).width / 2,
                .y = self.position.y,
            },
            self.title,
            .{},
            graphics.colors.SolidColor{ .color = graphics.colors.white },
        );

        // Shadow
        const shadow_size = 5;
        graphics.drawFilledRectangle(
            .{ .x = self.position.x -| shadow_size, .y = self.position.y + shadow_size },
            .{ .width = shadow_size, .height = self.size.height + shadow_size },
            graphics.colors.SolidColor{ .color = graphics.colors.darkgray },
        );
        graphics.drawFilledRectangle(
            .{ .x = self.position.x -| shadow_size, .y = self.position.y + self.size.height + shadow_size * 2 },
            .{ .width = self.size.width, .height = shadow_size },
            graphics.colors.SolidColor{ .color = graphics.colors.darkgray },
        );

        // Content
        graphics.drawFilledRectangle(
            .{ .x = self.position.x, .y = self.position.y + handle_height },
            self.size,
            graphics.colors.SolidColor{ .color = graphics.colors.black },
        );
    }

    pub fn getContentPosition(self: Window) Position {
        return .{ .x = self.position.x, .y = self.position.y + handle_height };
    }

    pub fn update(self: *Window) void {
        const pointer_position = system.pointer.getPosition();

        self.draggable_handle.collision_rectangle = collision.Rectangle{
            .position = self.position,
            .size = .{ .width = self.size.width, .height = handle_height },
        };
        const bottom_resizer_y = self.position.y + self.size.height + handle_height;
        self.bottom_resizer.collision_rectangle = collision.Rectangle{
            .position = .{ .x = self.position.x, .y = bottom_resizer_y },
            .size = .{ .width = self.size.width, .height = resizer_size },
        };
        self.bottom_right_resizer.collision_rectangle = collision.Rectangle{
            .position = .{ .x = self.position.x + self.size.width, .y = bottom_resizer_y },
            .size = .{ .width = resizer_size, .height = resizer_size },
        };
        self.bottom_left_resizer.collision_rectangle = collision.Rectangle{
            .position = .{ .x = self.position.x -| resizer_size, .y = bottom_resizer_y },
            .size = .{ .width = resizer_size, .height = resizer_size },
        };

        var draggables = [_]*DraggableRectangle{ &self.draggable_handle, &self.bottom_resizer, &self.bottom_right_resizer, &self.bottom_left_resizer };

        // We want to make sure to update only one dragged draggable at a time
        // to prevent the pointer from starting to drag other draggables
        // on accident when hovering them
        var dragged_draggable: ?*DraggableRectangle = null;
        for (draggables) |draggable| {
            if (draggable.dragged) {
                dragged_draggable = draggable;
                break;
            }
        }
        if (dragged_draggable) |draggable|
            _ = draggable.update()
        else {
            for (draggables) |draggable|
                if (draggable.update()) break;
        }

        const delta_x = @intCast(isize, self.previous_pointer_position.x) - @intCast(isize, pointer_position.x);
        const delta_y = @intCast(isize, self.previous_pointer_position.y) - @intCast(isize, pointer_position.y);
        if (self.draggable_handle.dragged) {
            self.position = .{
                .x = @intCast(usize, @maximum(0, @intCast(isize, self.position.x) - delta_x)),
                .y = @intCast(usize, @maximum(0, @intCast(isize, self.position.y) - delta_y)),
            };
        } else if (self.bottom_resizer.dragged) {
            self.size.height = @intCast(usize, @maximum(0, @intCast(isize, self.size.height) - delta_y));
        } else if (self.bottom_right_resizer.dragged) {
            self.size = .{
                .width = @intCast(usize, @maximum(0, @intCast(isize, self.size.width) - delta_x)),
                .height = @intCast(usize, @maximum(0, @intCast(isize, self.size.height) - delta_y)),
            };
        } else if (self.bottom_left_resizer.dragged) {
            self.position = .{
                .x = @intCast(usize, @maximum(0, @intCast(isize, self.position.x) - delta_x)),
                .y = self.position.y,
            };
            self.size = .{
                .width = @intCast(usize, @maximum(0, @intCast(isize, self.size.width) + delta_x)),
                .height = @intCast(usize, @maximum(0, @intCast(isize, self.size.height) - delta_y)),
            };
        }

        self.previous_pointer_position = pointer_position;
    }
};
