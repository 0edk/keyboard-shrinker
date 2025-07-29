const std = @import("std");
const trie = @import("trie.zig");
const compile = @import("compile.zig");
const Allocator = std.mem.Allocator;
const alphabet = "abcdefghijklmnopqrstuvwxyz";
const Word = []const trie.Letter;

pub fn main() !void {
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    var arena = std.heap.ArenaAllocator.init(debug_alloc.allocator());
    defer arena.deinit();
    const main_alloc = arena.allocator();
    const word_list_filename = "dicts/google_100";
    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();
    var buf: [32]u8 = undefined;
    const subset = compile.charsToSubset(try stdin.readUntilDelimiterOrEof(&buf, '\n') orelse "etao");
    const word_list_file = try std.fs.cwd().openFile(word_list_filename, .{});
    const wlr = word_list_file.reader();
    var dict_trie = compile.CompiledTrie.init(main_alloc);
    defer dict_trie.deinit();
    var i: compile.Weight = 0;
    while (try wlr.readUntilDelimiterOrEofAlloc(main_alloc, '\n', 128)) |line| {
        i += 1;
        try compile.contractAddWord(&dict_trie, subset, .{ .word = line, .weight = 1000 / i });
    }
    compile.normalise(&dict_trie);
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    std.debug.print("loaded {d} words\n", .{i});
    while (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const letters = try trie.charsToLetters(main_alloc, line);
        defer letters.deinit();
        for ((try dict_trie.get(letters.items)).leaf.items) |ww| {
            try stdout.print("{s}\t{d}\n", .{ ww.word, ww.weight });
        }
        try bw.flush();
    }
}
