const std = @import("std");
const letters = @import("letters.zig");
const trie = @import("trie.zig");
const compile = @import("compile.zig");
const score = @import("score.zig");
const Allocator = std.mem.Allocator;
const Word = []const letters.Letter;
const alphabet = "abcdefghijklmnopqrstuvwxyz";

fn showSubset(writer: anytype, set: compile.LettersSubset) !void {
    for (0..alphabet.len, alphabet) |i, c| {
        if (set.isSet(i)) {
            try writer.print("{u}", .{c});
        }
    }
}

fn sortLeaf(_: void, leaf: std.ArrayList(compile.WeightedWord)) void {
    std.mem.sort(compile.WeightedWord, leaf.items, {}, score.lessThanWord);
}

fn partlyUpper(s: []const u8) bool {
    var n: usize = 0;
    for (s) |c| n += @intFromBool(std.ascii.isUpper(c));
    return n > 0 and n < s.len;
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
    std.debug.print("loading from '{s}'\n", .{ word_list_filename });
    const word_list_file = try std.fs.cwd().openFile(word_list_filename, .{});
    const wlr = word_list_file.reader();
    var word_list = score.WordList.init(main_alloc);
    var wc: compile.Weight = 1;
    while (try wlr.readUntilDelimiterOrEofAlloc(main_alloc, '\n', 128)) |line| {
        const after_indent = std.mem.trim(u8, line, " \t");
        var word: []const u8 = undefined;
        var weight: compile.Weight = undefined;
        if (std.mem.indexOf(u8, after_indent, " ")) |sep| {
            word = after_indent[sep + 1..];
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

    const default_chars = "arstneio";
    const default_subset = compile.charsToSubset(default_chars);
    std.debug.print("using subset '{s}'\n", .{default_chars});
    var dict_trie = compile.CompiledTrie.init(main_alloc);
    var it = word_list.iterator();
    while (it.next()) |entry| {
        try compile.contractAddWord(&dict_trie, default_subset, entry.value_ptr.*);
    }
    compile.normalise(&dict_trie);
    dict_trie.deepForEach({}, null, sortLeaf);

    while (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (true) {
            const input_letters = try letters.charsToLetters(main_alloc, line);
            defer input_letters.deinit();
            if ((try dict_trie.get(input_letters.items)).leaf) |matches| {
                for (matches.items) |ww| {
                    try stdout.print("{s}\t{d}\n", .{ ww.word, ww.weight });
                }
            } else {
                try stdout.print("{s}\t0\n", .{ line });
            }
            try bw.flush();
        } else {
            var start_subset = compile.LettersSubset.initEmpty();
            if (line.len > 0) {
                for (line) |c| {
                    if (letters.charToLetter(c)) |l| {
                        start_subset.set(l);
                    }
                }
            } else {
                for (0..alphabet.len) |i| {
                    start_subset.setValue(i, rand.boolean());
                }
            }
            try showSubset(stdout, start_subset);
            try stdout.print(" -> ", .{});
            try bw.flush();
            const final_subset = try score.climbToLen(word_list, start_subset, 8);
            try showSubset(stdout, final_subset);
            const final_score = try score.badnessSubset(word_list, final_subset);
            try stdout.print(" ({d})\n", .{final_score});
            try bw.flush();
        }
    }
}
