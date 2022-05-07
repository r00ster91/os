pub const std = @import("std");

pub const system = @import("system.zig");
pub const Position = system.Position;
pub const Size = system.Size;
pub const Color = system.Color;
pub const colors = @import("graphics/colors.zig");

pub const Scale = struct { x: usize = 1, y: usize = 1 };

// https://rxi.github.io/cached_software_rendering.html
// Basically, each of the following functions will be a draw command.
// They're all deterministic so the name + arguments can be made into an enum or something (DrawCommand)
// Then, you hash the draw commands and then do some comparisons with those hashes and figure out
// whether the operation is required or not

pub fn drawHorizontalLine(position: Position, width: usize, color: anytype) void {
    var x: usize = 0;
    while (x < width) : (x += 1) {
        const actual_position = .{ .x = position.x + x, .y = position.y };
        const actual_color = switch (@TypeOf(color)) {
            colors.SolidColor => color.get(),
            colors.InvertedColor => color.get(actual_position),
            else => unreachable,
        };
        system.screen.drawPixel(actual_position, actual_color);
    }
}

pub fn drawVerticalLine(position: Position, height: usize, color: anytype) void {
    var y: usize = 0;
    while (y < height) : (y += 1) {
        const actual_position = .{ .x = position.x, .y = position.y + y };
        const actual_color = switch (@TypeOf(color)) {
            colors.SolidColor => color.get(),
            colors.InvertedColor => color.get(actual_position),
            else => unreachable,
        };
        system.screen.drawPixel(actual_position, actual_color);
    }
}

pub fn drawFilledRectangle(position: Position, size: Size, color: anytype) void {
    var y: usize = 0;
    while (y < size.height) : (y += 1) {
        drawHorizontalLine(.{ .x = position.x, .y = position.y + y }, size.width, color);
    }
}

pub fn drawOutlinedRectangle(position: Position, size: Size, color: anytype) void {
    drawHorizontalLine(position, size.width, color);
    drawVerticalLine(.{ .x = position.x, .y = position.y + 1 }, size.height - 2, color);
    drawVerticalLine(.{ .x = position.x + size.width - 1, .y = position.y + 1 }, size.height - 2, color);
    drawHorizontalLine(.{ .x = position.x, .y = position.y + size.height - 1 }, size.width, color);
}

const bdf = @import("fonts/formats/bdf.zig");
var font: bdf.BDF = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    font = try bdf.BDF.parse(
        allocator,
        // @embedFile("fonts/misaki_bdf_2021-05-05/misaki_gothic_2nd.bdf"),
        @embedFile("fonts/leggie/leggie-12.bdf"),
    );
}

pub fn drawText(position: Position, text: []const u8, scale: Scale, color: anytype) !void {
    var index: usize = 0;
    var spacing = Size{};
    while (index < text.len) : (index += 1) {
        const glyph = font.glyphs.get(text[index]) orelse return error.UnknownGlyph;
        const vertical_alignment = font.max_bounding_box.height - glyph.bounding_box.height;
        drawGlyph(
            .{
                .x = position.x + spacing.width,
                .y = position.y + vertical_alignment + spacing.height,
            },
            glyph,
            scale,
            color,
        );
        spacing.width += glyph.spacing_size.width;
        spacing.height += glyph.spacing_size.height;
    }
}

pub fn getTextSize(text: []const u8) !Size {
    var index: usize = 0;
    var size = Size{};
    while (index < text.len) : (index += 1) {
        const glyph = font.glyphs.get(text[index]) orelse return error.UnknownGlyph;
        if (index != text.len - 1) {
            size.width += glyph.spacing_size.width;
            size.height += glyph.spacing_size.height;
        }
    }
    return size;
}

fn drawGlyph(position: Position, glyph: bdf.BDF.Glyph, scale: Scale, color: anytype) void {
    const bitmap = glyph.bitmap.items;
    var y: usize = 0;
    while (y < bitmap.len) : (y += 1) {
        drawBits(
            .{
                .x = @intCast(usize, @maximum(0, @intCast(isize, position.x) + glyph.bounding_box.x)),
                .y = @intCast(usize, @maximum(0, @intCast(isize, position.y) + glyph.bounding_box.y)) + y,
            },
            u8,
            bitmap[y],
            scale,
            color,
        );
    }
}

fn drawBits(position: Position, comptime T: type, bits: anytype, scale: Scale, color: anytype) void {
    const byte_row = @bitReverse(T, bits);
    var x: u5 = 0;
    while (x < @bitSizeOf(T)) : (x += 1) {
        const is_bit_set = byte_row & (@as(u32, 1) << x) != 0;
        if (is_bit_set)
            drawFilledRectangle(.{ .x = (position.x + x) * scale.x, .y = position.y * scale.y }, @bitCast(Size, scale), color);
    }
}
