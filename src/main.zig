const std = @import("std");
const letters = @import("letters.zig");
const trie = @import("trie.zig");
const compile = @import("compile.zig");
const score = @import("score.zig");
const Allocator = std.mem.Allocator;
const Word = []const letters.Letter;
const alphabet = "abcdefghijklmnopqrstuvwxyz'_";
const default_keys = "acdeinorst";

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

    var buf: [32]u8 = undefined;
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    var rng = std.Random.DefaultPrng.init(seed);
    var rand = rng.random();

    const default_subset = compile.charsToSubset(default_keys);
    std.debug.print("using subset '{s}'\n", .{default_keys});
    var dict_trie = compile.CompiledTrie.init(main_alloc);
    try compile.loadWords(&dict_trie, default_subset, word_list);

    while (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (false) {
            const input_letters = try letters.charsToLetters(main_alloc, line);
            defer input_letters.deinit();
            if (dict_trie.getOrNull(input_letters.items)) |node| {
                if (node.leaf) |matches| {
                    for (matches.items) |ww| {
                        try stdout.print("{s}\t{d}\n", .{ ww.word, ww.weight });
                    }
                }
            } else {
                try stdout.print("{s}\t0\n", .{line});
            }
            try bw.flush();
        } else {
            var climb_subset = compile.LettersSubset.initEmpty();
            if (line.len > 0) {
                for (line) |c| {
                    if (letters.charToLetter(c)) |l| {
                        climb_subset.set(l);
                    }
                }
            } else {
                for (0..alphabet.len) |i| {
                    climb_subset.setValue(i, rand.boolean());
                }
            }
            try showSubset(stdout, climb_subset);
            try stdout.print(" ->\n", .{});
            try bw.flush();
            while (climb_subset.count() < 14) {
                climb_subset.set(try score.climbStep(word_list, climb_subset, false) orelse break);
                try showSubset(stdout, climb_subset);
                try stdout.print(" ({d})\n", .{try score.badnessSubset(word_list, climb_subset)});
                try bw.flush();
            }
        }
    }
}
