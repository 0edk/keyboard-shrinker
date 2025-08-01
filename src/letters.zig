const std = @import("std");
const Allocator = std.mem.Allocator;
pub const String = std.ArrayList(u8);

pub const Letter = u5;

pub fn charToLetter(char: u8) ?Letter {
    return switch (char) {
        'A'...'Z' => @intCast(char - 'A'),
        'a'...'z' => @intCast(char - 'a'),
        '\'' => 26,
        '_' => 27,
        else => null,
    };
}

pub fn charsToLetters(
    allocator: Allocator,
    str: []const u8,
) Allocator.Error!std.ArrayList(Letter) {
    var projected = std.ArrayList(Letter).init(allocator);
    for (str) |c| {
        if (charToLetter(c)) |l| {
            try projected.append(l);
        }
    }
    return projected;
}

pub fn letterToChar(letter: Letter) ?u8 {
    return switch (letter) {
        0...25 => @as(u8, letter) + 'a',
        26 => '\'',
        27 => '_',
        else => null,
    };
}

pub fn lettersToChars(
    allocator: Allocator,
    letters: []const Letter,
) Allocator.Error!std.ArrayList(u8) {
    var s = try String.initCapacity(allocator, letters.len);
    for (letters) |l| {
        if (letterToChar(l)) |c| {
            try s.append(c);
        }
    }
    return s;
}
