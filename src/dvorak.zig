const std = @import("std");
const letters = @import("letters.zig");
const compile = @import("compile.zig");
const input = @import("input.zig");
const control_code = std.ascii.control_code;

pub const default_letters = "acdeilnorstu";
pub const default_subset = compile.charsToSubset(default_letters);
const capital_numbers = ")!@#$%^&*(";

pub fn charToInsert(c: u8) ?input.Action {
    if (std.ascii.isDigit(c)) {
        return .{ .char = capital_numbers[c - '0'] };
    }
    if (std.mem.indexOfScalar(u8, capital_numbers, c)) |i| {
        const i_cast: u8 = @intCast(i);
        return .{ .char = '0' + i_cast };
    }
    if (std.ascii.isPrint(c)) {
        return .{ .char = c };
    }
    return switch (c) {
        control_code.bs, control_code.del => .backspace,
        control_code.cr, control_code.lf => .{ .char = '\n' },
        else => null,
    };
}

pub fn charToNormal(c: u8) ?input.Action {
    if (letters.charToLetter(c)) |l| {
        if (default_subset.isSet(l)) {
            return .{ .char = c };
        }
    }
    return switch (c) {
        'p' => .{ .char = '-' },
        'y' => .{ .char = '`' },
        'Y' => .{ .char = '~' },
        'g' => .{ .char = '=' },
        'G' => .{ .char = '+' },
        'h' => .next,
        'H' => .previous,
        'q' => .{ .char = '\t' },
        'j' => .to_insert,
        'J' => .finish_partial,
        'k' => .{ .char = '[' },
        'K' => .{ .char = '{' },
        'b' => .{ .char = '\\' },
        'B' => .{ .char = '|' },
        'm' => .{ .char = ']' },
        'M' => .{ .char = '}' },
        'w' => .backspace,
        'W' => .deter,
        'v' => .{ .char = '\n' },
        'z' => .{ .char = '/' },
        'Z' => .{ .char = '?' },
        else => charToInsert(c),
    };
}
