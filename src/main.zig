const std = @import("std");
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

// https://ziggit.dev/t/how-to-read-arrow-key/7405
fn enableRawMode() !std.posix.termios {
    const original = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
    var raw = original;
    raw.iflag.IGNBRK = false;
    raw.iflag.BRKINT = false;
    raw.iflag.PARMRK = false;
    raw.iflag.INLCR = false;
    raw.iflag.IGNCR = false;
    raw.iflag.ICRNL = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.IXON = false;
    raw.oflag.OPOST = false;
    raw.lflag.ECHO = false;
    raw.lflag.ECHONL = false;
    raw.lflag.ICANON = false;
    raw.lflag.IEXTEN = false;
    raw.lflag.ISIG = false;
    raw.cflag.PARENB = false;
    raw.cflag.CSIZE = .CS8;
    //raw.c_cc[c.VMIN] = 1;
    //raw.c_cc[c.VTIME] = 0;
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);
    //std.process.cleanExit(disableRawMode);
    return original;
}

fn restoreTerminal(state: std.posix.termios) !void {
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, state);
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
    const word_list_filename = args.next() orelse "no filename";

    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var arena = std.heap.ArenaAllocator.init(main_alloc);
    defer arena.deinit();
    const wl_alloc = arena.allocator();
    std.debug.print("loading from '{s}'\n", .{word_list_filename});
    const word_list_file = try std.fs.cwd().openFile(word_list_filename, .{});
    defer word_list_file.close();
    const wlr = word_list_file.reader();
    var word_list = compile.WordList.init(main_alloc);
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
            if (partlyUpper(word) and !partlyUpper(ww.word)) {
                ww.word = word;
            }
        } else {
            wc += 1;
            try word_list.put(lowered, .{ .word = word, .weight = weight });
        }
    }
    std.debug.print("loaded {d} words\n", .{wc});

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

    const original_termios = try enableRawMode();
    defer restoreTerminal(original_termios) catch |e| std.debug.print("error: {any}\n", .{e});
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
        if (dvorak.charToNormal(next_char)) |normal_action| {
            if (dvorak.charToInsert(next_char)) |insert_action| {
                try log_writer.print("{any} {any}\n", .{ insert_action, normal_action });
                switch (try ime.handleAction(insert_action, normal_action, false)) {
                    .silent => {
                        try stdout.print(
                            "\x1b[{d};{d}H\x1b[0K\x1b[4m{s}\x1b[1m{s}\x1b[0m",
                            .{ typing_row, word_column, ime.literal.items, try ime.getCompletion() },
                        );
                        try bw.flush();
                    },
                    .text => |s| {
                        defer main_alloc.free(s);
                        try input_acc.appendSlice(s);
                        var it = std.mem.splitScalar(u8, s, '\n');
                        var first = true;
                        while (it.next()) |line| {
                            if (!first) {
                                typing_row += 1;
                            }
                            try stdout.print("\x1b[{d};{d}H{s}", .{ typing_row, word_column, s });
                            word_column = line.len + if (first) word_column else 1;
                            first = false;
                        }
                        try bw.flush();
                    },
                    .pass => switch (next_char) {
                        0x08, 0x7F => if (input_acc.pop()) |_| {
                            word_column -= 1;
                            try stdout.print("\x1b[{d};{d}H ", .{ typing_row, word_column });
                            try bw.flush();
                        },
                        else => {},
                    },
                }
            }
        }
    }

    std.debug.print("saving typed text\n", .{});
    if (short_buf[0] == 4) {
        const output_file = try std.fs.cwd().createFile("out.txt", .{});
        const output_writer = output_file.writer();
        std.debug.assert(try output_writer.write(input_acc.items) == input_acc.items.len);
        output_file.close();
    }
    std.debug.print("end of program\n", .{});
}
