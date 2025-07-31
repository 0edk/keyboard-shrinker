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
    var word_list = score.WordList.init(main_alloc);
    var wc: compile.Weight = 0;
    while (try wlr.readUntilDelimiterOrEofAlloc(main_alloc, '\n', 128)) |line| {
        wc += 1;
        const lowered = try std.ascii.allocLowerString(main_alloc, line);
        if (word_list.getPtr(lowered)) |ww| {
            ww.weight += 1 / wc;
            main_alloc.free(lowered);
        } else {
            try word_list.put(lowered, .{ .word = line, .weight = 1 / wc });
        }
    }
    std.debug.print("loaded {d} words\n", .{wc});

    var buf: [32]u8 = undefined;
    var rng = std.Random.DefaultPrng.init(20520420150291);
    var rand = rng.random();
    while (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        _ = line;
        var start_subset = compile.LettersSubset.initEmpty();
        for (0..alphabet.len) |i| {
            start_subset.setValue(i, rand.boolean());
        }
        try showSubset(stdout, start_subset);
        try stdout.print(" -> ", .{});
        const final_subset = try score.climbToLen(word_list, start_subset, 8);
        try showSubset(stdout, final_subset);
        const final_score = try score.badnessSubset(word_list, final_subset);
        try stdout.print(" ({d})\n", .{final_score});
        try bw.flush();
    }

    var it = word_list.iterator();
    while (it.next()) |entry| {
        main_alloc.free(entry.key_ptr.*);
        main_alloc.free(entry.value_ptr.word);
    }
}
