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
    const main_alloc = debug_alloc.allocator();

    const word_list_filename = "dicts/google_10000";
    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var arena = std.heap.ArenaAllocator.init(main_alloc);
    defer arena.deinit();
    const wl_alloc = arena.allocator();
    const word_list_file = try std.fs.cwd().openFile(word_list_filename, .{});
    const wlr = word_list_file.reader();
    var word_list = score.WordList.init(main_alloc);
    var wc: compile.Weight = 0;
    while (try wlr.readUntilDelimiterOrEofAlloc(main_alloc, '\n', 128)) |line| {
        wc += 1;
        const lowered = try std.ascii.allocLowerString(wl_alloc, line);
        if (word_list.getPtr(lowered)) |ww| {
            ww.weight += 1 / wc;
        } else {
            try word_list.put(lowered, .{ .word = line, .weight = 1 / wc });
        }
    }
    std.debug.print("loaded {d} words\n", .{wc});

    var buf: [32]u8 = undefined;
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    var rng = std.Random.DefaultPrng.init(seed);
    var rand = rng.random();
    while (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
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
