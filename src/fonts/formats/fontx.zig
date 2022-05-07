const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const utils = @import("utils");
const Pos = utils.Pos;
const Size = utils.Size;
const system = @import("../system.zig");
const screen = system.screen;
const graphics = @import("../graphics.zig");

// TODO:
// font choices:
// * petme64/commodore64 font - this is the one that VVVVVV uses!
// * https://littlelimit.net/font.htm
// * https://github.com/Fussmatte/space-station-font
// * https://littlelimit.net/misaki.htm
// * https://github.com/rewtnull/amigafonts
// Formats:
// * https://en.wikipedia.org/wiki/Portable_Compiled_Format
// * https://wiki.osdev.org/PC_Screen_Font
// * https://wiki.osdev.org/Scalable_Screen_Font
// also, reading the font from a PNG

/// The FONTX font format.
///
/// References:
///
/// * http://elm-chan.org/docs/dosv/fontx_e.html
/// * https://www.unifoundry.com/japanese/index.html
pub const FONTX = struct {
    const Self = @This();

    bytes: []const u8,
    i: usize,
    header: Header,

    const Type = enum { SingleByte, DoubleByte };

    const Header = struct { font_name: []const u8, font_width: u8, font_height: u8, font_size: u8, type: Type, code_block_count: u8 };

    fn readHeader(bytes: []const u8, i: *usize) !Header {
        const ParsingError = error{ MissingHeader, UnknownCodeFlag };

        var header: Header = undefined;

        if (bytes.len < 16) {
            return ParsingError.MissingHeader;
        }

        assert(mem.eql(u8, bytes[i.*..6], "FONTX2"));
        i.* += 6; // Skip signature

        header.font_name = bytes[i.* .. i.* + 8];
        i.* += 8;

        header.font_width = bytes[i.*];
        i.* += 1;
        header.font_height = bytes[i.*];
        i.* += 1;

        header.font_size = (header.font_width + 7) / 8 * header.font_height;

        const code_flag = bytes[i.*];
        i.* += 1;

        switch (code_flag) {
            0 => { // ANK (Alphabet, Numerals, and Katakana, a single-byte, half-width Japanese font)
                // This means the font image follows immediately
                header.type = Type.SingleByte;
            },
            1 => { // Shift JIS
                header.type = Type.DoubleByte;

                header.code_block_count = bytes[i.*];
                i.* += 1;
            },
            else => return error.UnknownCodeFlag,
        }

        return header;
    }

    fn drawSingleByteChar(
        self: Self,
        pos: Pos,
        size: Size,
        color: screen.Color,
        char: u8,
    ) void {
        const bitmap_offset = self.bytes[self.i + char * self.header.font_size ..];
        graphics.drawBitmap(pos, size, color, bitmap_offset, Size{ .w = self.header.font_size, .h = 8 });
    }

    fn drawDoubleByteChar(
        self: Self,
        pos: Pos,
        size: Size,
        color: screen.Color,
        char: u16,
    ) void {
        var code_count: usize = 0;

        var i = self.i;
        var code_block_i: usize = 0;
        while (code_block_i < self.header.code_block_count) : (code_block_i += 1) {
            const code_block_start = @intCast(u16, self.bytes[i]) + @intCast(u16, self.bytes[i + 1]) * 0x100;
            i += 2;
            const code_block_end = @intCast(u16, self.bytes[i]) + @intCast(u16, self.bytes[i + 1]) * 0x100;
            i += 2;

            // Is the character inside this code block?
            if (char >= code_block_start and char <= code_block_end) {
                code_count += char - code_block_start;
                const bitmap_offset = self.bytes[18 + 4 * @intCast(u32, self.header.code_block_count) + code_count * self.header.font_size ..];
                graphics.drawBitmap(pos, size, color, bitmap_offset, Size{ .w = self.header.font_size, .h = 8 });
                return;
            }
            code_count += code_block_end - code_block_start + 1;
        }
    }

    pub fn drawChar(self: Self, pos: Pos, size: Size, color: screen.Color, char: u16) void {
        switch (self.header.type) {
            .SingleByte => self.drawSingleByteChar(pos, size, color, @truncate(u8, utf8.toANK(char))),
            .DoubleByte => self.drawDoubleByteChar(pos, size, color, utf8.toShiftJIS(char)),
        }
    }

    pub fn parse(bytes: []const u8) !Self {
        var i: usize = 0;
        const header = try readHeader(bytes, &i);

        return Self{ .bytes = bytes, .i = i, .header = header };
    }

    pub fn getCharWidth(self: Self, char_count: usize) u32 {
        return @intCast(u32, char_count) * self.header.font_width;
    }
};

pub fn toANK(char: u16) u8 {
    switch (char) {
        '｡'...'ﾟ' => { // Half-width katakana
            return @intCast(u8, char - '｡') +
                0x00A1; // '｡' in ANK
        },
        else => return @truncate(u8, char),
    }
}

pub fn toShiftJIS(char: u16) u16 {
    switch (char) {
        'ぁ'...'ゖ' => { // Full-width hiragana
            return char - 'ぁ' +
                0x829f; // Shift JIS 'ぁ'
        },
        'ァ'...'ヺ' => { // Full-width katakana
            return char - 'ァ' +
                0x8340; // Shift JIS 'ァ'
        },
        'A'...'Z' => { // Half-width uppercase alphabet
            return char - 'A' +
                0x8260; // Full-width uppercase 'A'
        },
        'a'...'z' => { // Half-width lowercase alphabet
            return char - 'a' +
                0x8281; // Full-width lowercase 'a'
        },
        else => return char,
    }
}
