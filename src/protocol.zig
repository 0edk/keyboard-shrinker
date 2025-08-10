const std = @import("std");
const compile = @import("compile.zig");
const input = @import("input.zig");
const dvorak = @import("dvorak.zig");

const non_letters = "\t\r\n !\"#$%&()*+,./:;<=>?@[\\]^`{|}";

fn shouldEscape(c: u8) bool {
    return switch (c) {
        0...31, ':', '\\' => true,
        else => false,
    };
}

pub fn populateFromRaw(dict: *compile.WordList, reader: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(dict.allocator);
    defer arena.deinit();
    const wl_alloc = arena.allocator();
    while (try reader.readUntilDelimiterOrEofAlloc(dict.allocator, '\n', 1024)) |line| {
        var it = std.mem.tokenizeAny(u8, line, non_letters);
        while (it.next()) |word| {
            const lowered = try std.ascii.allocLowerString(wl_alloc, word);
            if (dict.getPtr(lowered)) |ww| {
                ww.weight += 1;
            } else {
                try dict.put(lowered, .{ .word = word, .weight = 1 });
            }
        }
    }
}

pub fn handleKeysym(ime: *input.ShrunkenInputMethod, key: u8, writer: anytype) !void {
    if (dvorak.charToNormal(key)) |normal_action| {
        if (dvorak.charToInsert(key)) |insert_action| {
            switch (try ime.handleAction(insert_action, normal_action, false)) {
                .silent => try writer.print(
                    "word:{s}\x1b[1m{s}\x1b[0m\n",
                    .{ ime.literal.items, try ime.getCompletion() },
                ),
                .text => |s| {
                    defer ime.dict.allocator.free(s);
                    try writer.writeAll("text:");
                    // TODO
                    var start: usize = 0;
                    while (std.mem.indexOfAnyPos(u8, s, start, "\n:\\")) |esc_ind| {
                        try writer.writeAll(s[start..esc_ind]);
                        try writer.writeByte('\\');
                        try writer.writeByte(s[esc_ind]);
                        start = esc_ind + 1;
                    }
                    try writer.writeAll(s[start..]);
                    try writer.writeByte('\n');
                },
                .pass => try writer.print(
                    "text:{s}{c}\n",
                    .{ if (shouldEscape(key)) "\\" else "", key },
                ),
            }
        }
    } else {
        try writer.print("text:{s}{c}\n", .{ if (shouldEscape(key)) "\\" else "", key });
    }
}
