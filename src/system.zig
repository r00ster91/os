//! This includes all minimal functionality required for the system to function.
//!
//! Some functions are optional and will be provided with fallbacks if necessary.
//! The purpose of optional functions is to give the backend the chance to do
//! an operation more efficiently than the fallback could.

const std = @import("std");

const backend = @import("backend");

// Here's also inspiration for an API: https://github.com/aduros/wasm4/blob/main/cli/assets/templates/zig/src/wasm4.zig

pub const Position = struct { x: usize = 0, y: usize = 0 };
pub const Size = struct { width: usize = 0, height: usize = 0 };

pub const Color = struct { r: u8, g: u8, b: u8 };

pub const screen = struct {
    pub const init: fn (Size) void = backend.screen.init;
    /// Sets up a new, black frame to draw on.
    pub const startDrawing: fn () void = backend.screen.startDrawing;
    /// Draws a single pixel to the screen, the smallest possible unit.
    pub const drawPixel: fn (Position, Color) void = backend.screen.drawPixel;
    // pub const drawFilledRectangle: ?fn (Position, Size, Color) void = backend.screen.drawFilledRectangle;
    // pub const drawStraightLine: ?fn (Position, Position, Color) void = backend.screen.drawStraightLine;
    pub const getPixel: fn (Position) Color = backend.screen.getPixel;
    /// Makes the frame visible on the display and clears the frame to color black.
    pub const endDrawing: fn () void = backend.screen.endDrawing;
    pub const deinit: fn () void = backend.screen.deinit;
};

/// A pointing device.
pub const pointer = struct {
    pub const getPosition: fn () Position = backend.pointer.getPosition;
    pub const isPressed: fn () bool = backend.pointer.isPressed;
};
