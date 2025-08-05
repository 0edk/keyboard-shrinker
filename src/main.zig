const std = @import("std");
const ansi = @import("ansi.zig");
const letters = @import("letters.zig");
const trie = @import("trie.zig");
const compile = @import("compile.zig");
const score = @import("score.zig");
const input = @import("input.zig");
const dvorak = @import("dvorak.zig");
const Allocator = std.mem.Allocator;
const Word = []const letters.Letter;
const alphabet = "abcdefghijklmnopqrstuvwxyz'_";

fn showSubset(writer: anytype, set: compile.LettersSubset) !void {
    for (0..alphabet.len, alphabet) |i, c| {
        if (set.isSet(i)) {
            try writer.print("{u}", .{c});
        }
    }
}

fn partlyUpper(s: []const u8) bool {
    var uppers: usize = 0;
    var lowers: usize = 0;
    for (s) |c| {
        uppers += @intFromBool(std.ascii.isUpper(c));
        lowers += @intFromBool(std.ascii.isLower(c));
    }
    return uppers > 0 and lowers < 0;
}

fn note(s: []const u8) void {
    std.debug.print("{s}\n", .{s});
}

pub fn main() !void {
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    const main_alloc = debug_alloc.allocator();

    var args = try std.process.argsWithAllocator(main_alloc);
    defer args.deinit();
    _ = args.next().?;
    const typed_filename = args.next() orelse "out.txt";

    var word_list = compile.WordList.init(main_alloc);
    while (args.next()) |word_list_filename| {
        std.debug.print("loading from '{s}'\n", .{word_list_filename});
        const word_list_file = try std.fs.cwd().openFile(word_list_filename, .{});
        defer word_list_file.close();
        const wlr = word_list_file.reader();
        var arena = std.heap.ArenaAllocator.init(main_alloc);
        defer arena.deinit();
        const wl_alloc = arena.allocator();
        var wc: compile.Weight = 1;
        while (try wlr.readUntilDelimiterOrEofAlloc(main_alloc, '\n', 128)) |line| {
            const after_indent = std.mem.trim(u8, line, " \t");
            var word: []const u8 = undefined;
            var weight: compile.Weight = undefined;
            if (std.mem.indexOf(u8, after_indent, " ")) |sep| {
                word = after_indent[sep + 1 ..];
                weight = @floatFromInt(try std.fmt.parseInt(usize, after_indent[0..sep], 10));
            } else {
                word = after_indent;
                weight = 1 / wc;
            }
            const lowered = try std.ascii.allocLowerString(wl_alloc, word);
            if (word_list.getPtr(lowered)) |ww| {
                ww.weight += weight;
            } else {
                wc += 1;
                try word_list.put(lowered, .{ .word = word, .weight = weight });
            }
        }
        std.debug.print("loaded {d} words\n", .{wc});
    }
    compile.normalise(&word_list);

    var ime = input.ShrunkenInputMethod.init(main_alloc);
    defer ime.deinit();
    ime.usable_keys = dvorak.default_subset;
    std.debug.print("using subset '{s}'\n", .{dvorak.default_letters});
    try compile.loadWords(&ime.dict, ime.usable_keys, word_list);
    var input_acc = letters.String.init(main_alloc);
    defer input_acc.deinit();

    const log_file = try std.fs.cwd().createFile("out.log", .{});
    defer log_file.close();
    const log_writer = log_file.writer();

    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const original_termios = try ansi.enableRawMode();
    defer ansi.restoreTerminal(original_termios) catch |e| std.debug.print("error: {any}\n", .{e});
    try stdout.print("\x1b[6n", .{});
    try bw.flush();
    const cursor_pos = try stdin.readUntilDelimiterAlloc(main_alloc, 'R', 16);
    const bracket = std.mem.indexOfScalar(u8, cursor_pos, '[').?;
    const semicolon = std.mem.indexOfScalar(u8, cursor_pos, ';').?;
    var typing_row = try std.fmt.parseInt(usize, cursor_pos[bracket + 1 .. semicolon], 10);
    _ = &typing_row;
    var word_column: usize = 1;

    var short_buf: [1]u8 = undefined;
    while (try stdin.read(&short_buf) == 1 and short_buf[0] != 3 and short_buf[0] != 4) {
        const next_char = short_buf[0];
        if (next_char >= 1 and next_char <= 26) {
            switch (next_char) {
                '\n', '\r' => {
                    try input_acc.append('\n');
                    typing_row += 1;
                    word_column = 1;
                    try stdout.writeByte('\n');
                    try ansi.moveTo(stdout, typing_row, word_column);
                    try bw.flush();
                },
                '\t' => {
                    try input_acc.appendNTimes(' ', 4);
                    word_column += 4;
                    try stdout.writeByteNTimes(' ', 4);
                    try ansi.moveTo(stdout, typing_row, word_column);
                    try bw.flush();
                },
                else => {},
            }
        } else if (dvorak.charToNormal(next_char)) |normal_action| {
            if (dvorak.charToInsert(next_char)) |insert_action| {
                try log_writer.print("{any} {any} '{s}'\n", .{
                    insert_action,
                    normal_action,
                    ime.literal.items,
                });
                switch (try ime.handleAction(insert_action, normal_action, false)) {
                    .silent => {
                        try ansi.moveTo(stdout, typing_row, word_column);
                        try stdout.print("\x1b[0K\x1b[4m{s}\x1b[1m{s}\x1b[0m", .{
                            ime.literal.items,
                            if (try ime.getCompletion()) |comp| comp.word else "?",
                        });
                        try bw.flush();
                    },
                    .text => |s| {
                        defer main_alloc.free(s);
                        try input_acc.appendSlice(s);
                        try ansi.moveTo(stdout, typing_row, word_column);
                        try stdout.writeAll(s);
                        word_column += s.len;
                        try bw.flush();
                    },
                    .pass => if (ime.mode == .normal and normal_action == .backspace) {
                        if (input_acc.pop() != null) {
                            word_column -= 1;
                            try ansi.moveTo(stdout, typing_row, word_column);
                            try stdout.writeByte(' ');
                            try bw.flush();
                        }
                    },
                }
            }
        }
    }

    std.debug.print("saving typed text\n", .{});
    if (short_buf[0] == 4) {
        const output_file = try std.fs.cwd().createFile(typed_filename, .{ .truncate = false });
        defer output_file.close();
        try output_file.seekFromEnd(0);
        const output_writer = output_file.writer();
        std.debug.assert(try output_writer.write(input_acc.items) == input_acc.items.len);
    }
    std.debug.print("end of program\n", .{});
}
