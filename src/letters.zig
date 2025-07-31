const std = @import("std");
const Allocator = std.mem.Allocator;
const String = std.ArrayList(u8);

pub const Letter = u5;

pub fn charToLetter(char: u8) ?Letter {
    if (std.ascii.isAlphabetic(char)) {
        return @intCast(std.ascii.toLower(char) - 'a');
    }
    return null;
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

pub fn lettersToChars(
    allocator: Allocator,
    letters: []const Letter,
) Allocator.Error!std.ArrayList(u8) {
    var s = try String.initCapacity(allocator, letters.len);
    for (letters) |l| {
        const c: u8 = l;
        try s.append(c + 'a');
    }
    return s;
}
