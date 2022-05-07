const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const fmt = std.fmt;
const ArrayList = std.ArrayList;
const unicode = std.unicode;
const system = @import("../../system.zig");
const Position = system.Position;
const Size = system.Size;
const Color = system.Color;

// https://en.wikipedia.org/wiki/Computer_font#Bitmap_fonts

// There are generally two kind of fonts kinds: bitmap fonts (BDF, FONTX, etc.), and scalable fonts (TrueType, OpenType, etc.)

/// The BDF font format.
///
/// References:
///
/// * https://en.wikipedia.org/wiki/Glyph_Bitmap_Distribution_Format
pub const BDF = struct {
    const Self = @This();

    const BoundingBox = struct {
        width: u8,
        height: u8,
        x: i32,
        y: i32,

        fn parse(split_line: *mem.SplitIterator(u8)) !BoundingBox {
            return BoundingBox{
                .width = try fmt.parseUnsigned(u8, split_line.next() orelse return error.UnexpectedEnd, 10),
                .height = try fmt.parseUnsigned(u8, split_line.next() orelse return error.UnexpectedEnd, 10),
                .x = try fmt.parseInt(i32, split_line.next() orelse return error.UnexpectedEnd, 10),
                .y = try fmt.parseInt(i32, split_line.next() orelse return error.UnexpectedEnd, 10),
            };
        }
    };

    pub const Glyph = struct {
        bitmap: std.ArrayList(u8),
        bounding_box: BoundingBox,
        spacing_size: Size,
    };

    glyphs: std.AutoHashMap(u21, Glyph),
    max_bounding_box: BoundingBox,

    pub fn parse(allocator: mem.Allocator, bytes: []const u8) !Self {
        var lines = mem.split(u8, bytes, "\n");

        // Read metadata
        var max_bounding_box: ?BoundingBox = null;
        var character_count: ?u32 = 0;
        while (lines.next()) |line| {
            var split_line = mem.split(u8, line, " ");
            const keyword = split_line.next() orelse return error.UnexpectedEnd;
            if (mem.eql(u8, keyword, "FONTBOUNDINGBOX")) {
                max_bounding_box = try BoundingBox.parse(&split_line);
            } else if (mem.eql(u8, keyword, "CHARS")) {
                character_count = try fmt.parseUnsigned(u32, split_line.next() orelse return error.UnexpectedEnd, 10);
                _ = lines.next(); // Skip STARTCHAR statement
                break;
            }
        }

        // Read glyphs
        var glyphs = std.AutoHashMap(u21, Glyph).init(allocator);
        try glyphs.ensureTotalCapacity(character_count orelse return error.NoCharacterCount);
        var code_point: ?u21 = null;
        var spacing_size: ?Size = null;
        var bounding_box: ?BoundingBox = null;
        while (lines.next()) |line| {
            var split_line = mem.split(u8, line, " ");
            const keyword = split_line.next() orelse return error.UnexpectedEnd;

            if (mem.eql(u8, keyword, "ENCODING")) {
                code_point = try fmt.parseUnsigned(u21, split_line.next() orelse return error.UnexpectedEnd, 10);
            } else if (mem.eql(u8, keyword, "DWIDTH")) {
                spacing_size = .{
                    .width = try fmt.parseUnsigned(usize, split_line.next() orelse return error.UnexpectedEnd, 10),
                    .height = try fmt.parseUnsigned(usize, split_line.next() orelse return error.UnexpectedEnd, 10),
                };
            } else if (mem.eql(u8, keyword, "BBX")) {
                bounding_box = try BoundingBox.parse(&split_line);
            } else if (mem.eql(u8, keyword, "BITMAP")) {
                const glyph_bounding_box = bounding_box orelse return error.NoBoundingBox;
                var glyph = Glyph{
                    .bitmap = try std.ArrayList(u8).initCapacity(allocator, glyph_bounding_box.height),
                    .bounding_box = glyph_bounding_box,
                    .spacing_size = spacing_size orelse return error.NoSpacingSize,
                };
                while (lines.next()) |byte_line| {
                    if (mem.eql(u8, byte_line, "ENDCHAR")) {
                        break;
                    } else {
                        const byte = try fmt.parseUnsigned(u8, byte_line, 16);
                        try glyph.bitmap.append(byte);
                    }
                }
                // TODO: use `toOwnedSlice` on `glyph.bitmap` here
                //       or maybe use `allocator.alloc(...)` to have no ArrayList in the first place.
                //       Error if `glyph_bounding_box.height` doesn't match with the amount of lines above
                glyphs.putAssumeCapacityNoClobber(code_point orelse return error.NoCodePoint, glyph);
                glyph.bitmap.toOwnedSlice
                _ = lines.next(); // Skip STARTCHAR statement
            }
        }

        return Self{ .glyphs = glyphs, .max_bounding_box = max_bounding_box orelse return error.NoMaxBoundingBox };
    }

    // fn getGlyph(self: Self, char: u21) Glyph {
    //     for (self.glyphs.items) |glyph| {
    //         if (glyph.code_point == char) {
    //             return glyph;
    //         }
    //     }
    //     @panic
    //     std.debug.panic("failed to get glyph for unknown {}", .{char});
    // }

    // fn drawChar(
    //     glyph: Glyph,
    //     position: Position,
    //     size: Size,
    //     color: Color,
    // ) void {
    //     @import("../main.zig").pixel_size = size.width;
    //     const alignment = (max_glyph_height - @intCast(usize, glyph.bounding_box.height)) - @intCast(usize, glyph.bounding_box.y);
    //     drawBitmap(
    //         Position{ .x = position.x, .y = position.y + alignment },
    //         color,
    //         &glyph.bitmap,
    //         Size{ .width = glyph.bounding_box.width, .height = glyph.bounding_box.height },
    //     );
    //     @import("../main.zig").pixel_size = 1;
    // }

    const Spacing = enum { monospace, proportional };

    // pub fn drawUnicodeTextLine(self: Self, position: Position, size: Size, color: Color, spacing: Spacing, line: []const u8) void {
    //     var iterator = unicode.Utf8Iterator{ .bytes = line, .i = 0 };
    //     var relative_x: usize = 0;
    //     while (iterator.nextCodepoint()) |char| {
    //         const glyph = self.getGlyph(char);

    //         drawChar(glyph, Position{
    //             .x = position.x + relative_x,
    //             .y = position.y,
    //         }, size, color);

    //         switch (spacing) {
    //             .monospace => relative_x += self.bounding_box.width,
    //             .proportional => relative_x += glyph.bounding_box.width + size.width,
    //         }
    //     }
    // }

    // pub fn getWidth(self: Self, size: Scale!, spacing: Spacing, line: []const u8) u32 {
    //     switch (spacing) {
    //         .monospace => {
    //             return @intCast(u32, line.len) * size.width;
    //         },
    //         .proportional => {
    //             var width: u32 = 0;

    //             var iterator = unicode.Utf8Iterator{ .bytes = line, .i = 0 };
    //             while (iterator.nextCodepoint()) |char| {
    //                 const glyph = self.getGlyph(char);
    //                 width += (glyph.bounding_box.width +
    //                     1 // The actual spacing
    //                 ) * size.width;
    //             }

    //             return width;
    //         },
    //     }
    // }
};
