const std = @import("std");
const trie = @import("trie.zig");
const compile = @import("compile.zig");
const score = @import("score.zig");
const Allocator = std.mem.Allocator;
const alphabet = "abcdefghijklmnopqrstuvwxyz";
const Word = []const trie.Letter;

pub fn main() !void {
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    var arena = std.heap.ArenaAllocator.init(debug_alloc.allocator());
    defer arena.deinit();
    const main_alloc = arena.allocator();

    const word_list_filename = "dicts/google_10000";
    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const word_list_file = try std.fs.cwd().openFile(word_list_filename, .{});
    const wlr = word_list_file.reader();
    var word_list = std.StringHashMap(compile.WeightedWord).init(main_alloc);
    var wc: compile.Weight = 0;
    while (try wlr.readUntilDelimiterOrEofAlloc(main_alloc, '\n', 128)) |line| {
        wc += 1;
        const lowered = try std.ascii.allocLowerString(main_alloc, line);
        if (word_list.getPtr(lowered)) |ww| {
            ww.weight += 1 / wc;
        } else {
            try word_list.put(lowered, .{ .word = line, .weight = 1 / wc });
        }
    }
    std.debug.print("loaded {d} words\n", .{wc});

    var buf: [32]u8 = undefined;
    while (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const letters = try trie.charsToLetters(main_alloc, line);
        defer letters.deinit();
        var subset = compile.charsToSubset(line);
        var best: struct { u8, compile.Weight } = .{'a', std.math.inf(compile.Weight)};
        for (0..alphabet.len, alphabet) |i, c| {
            subset[i] = !subset[i];
            var dict_trie = compile.CompiledTrie.init(main_alloc);
            defer dict_trie.deinit();
            var it = word_list.iterator();
            while (it.next()) |entry| {
                try compile.contractAddWord(&dict_trie, subset, entry.value_ptr.*);
            }
            compile.normalise(&dict_trie);
            const badness = score.badnessLeaves(&dict_trie);
            if (badness < best[1]) {
                best = .{c, badness};
            }
            try stdout.print("{u}\t{d:.2}\n", .{c, @log(badness)});
            subset[i] = !subset[i];
        }
        try stdout.print("best\t{u}\n", .{best[0]});
        try bw.flush();
    }
}
