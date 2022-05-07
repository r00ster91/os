const std = @import("std");

const system = @import("../system.zig");
const Position = system.Position;
const Color = system.Color;

fn floatColor(r: f16, g: f16, b: f16) Color {
    return Color{
        .r = @floatToInt(u8, r * 255),
        .g = @floatToInt(u8, g * 255),
        .b = @floatToInt(u8, b * 255),
    };
}

pub const black = floatColor(0, 0, 0);
pub const gray = floatColor(0.5, 0.5, 0.5);
pub const darkgray = floatColor(0.25, 0.25, 0.25);
pub const white = floatColor(1, 1, 1);
pub const green = floatColor(0, 1, 0);

fn interpolate(start: usize, end: usize, fraction: f16) usize {
    const start_float = @intToFloat(f16, start);
    const end_float = @intToFloat(f16, end);
    return @floatToInt(usize, (end_float - start_float) * fraction + start_float);
}

fn interpolateColor(start: Color, color: Color, fraction: f16) Color {
    return .{
        .r = @intCast(u8, interpolate(start.r, color.r, fraction)),
        .g = @intCast(u8, interpolate(start.g, color.g, fraction)),
        .b = @intCast(u8, interpolate(start.b, color.b, fraction)),
        .a = @intCast(u8, interpolate(start.a, color.a, fraction)),
    };
}

fn hue2rgb(p: f16, q: f16, t: f16) f16 {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
}

fn HSLColor(h: f16, s: f16, l: f16) Color {
    if (s == 0) {
        return floatColor(l, l, l); // Achromatic
    } else {
        var q = if (l < 0.5) {
            l * (1 + s);
        } else {
            l + s - l * s;
        };
        var p = 2 * l - q;
        const r = hue2rgb(p, q, h + 1 / 3);
        const g = hue2rgb(p, q, h);
        const b = hue2rgb(p, q, h - 1 / 3);
        return floatColor(r, g, b);
    }
}

// pub const Color = struct {
//     r: u8,
//     g: u8,
//     b: u8,
//     a: u8,

//     fn getComponent(value: f16) u8 {
//         std.debug.assert(value >= 0 and value <= 1);
//         return @floatToInt(u8, value * 255);
//     }

//     fn init(r: f16, g: f16, b: f16) Color {
//         return .{
//             .r = getComponent(r),
//             .g = getComponent(g),
//             .b = getComponent(b),
//             .a = 255,
//         };
//     }

// fn darken(color: Color, addend: f16) Color {
//     const component = Color.getComponent(addend);
//     return .{
//         .r = self.r -| component,
//         .g = self.g -| component,
//         .b = self.b -| component,
//         .a = self.a,
//     };
// }

// fn lighten(color: Color, addend: f16) Color {
//     const component = Color.getComponent(addend);
//     return .{
//         .r = self.r +| component,
//         .g = self.g +| component,
//         .b = self.b +| component,
//         .a = self.a,
//     };
// }

// fn multiply(color: Color, multiplicand: f16) Color {
//     return .{
//         .r = @floatToInt(u8, @intToFloat(f16, self.r) * multiplicand),
//         .g = @floatToInt(u8, @intToFloat(f16, self.g) * multiplicand),
//         .b = @floatToInt(u8, @intToFloat(f16, self.b) * multiplicand),
//     };
// }

pub fn invert(color: Color) Color {
    return .{
        .r = 255 - color.r,
        .g = 255 - color.g,
        .b = 255 - color.b,
    };
}

// const GradientColor = struct {
//     start: Color,
//     end: Color,

//     fn get(self: GradientColor, fraction: f16) Color {
//         return interpolateColor(self.start, self.end, fraction);
//     }
// };

pub const SolidColor = struct {
    color: Color,

    pub fn get(self: SolidColor) Color {
        return self.color;
    }
};

pub const InvertedColor = struct {
    pub fn get(self: InvertedColor, position: Position) Color {
        _ = self;
        return invert(system.screen.getPixel(position));
    }
};
