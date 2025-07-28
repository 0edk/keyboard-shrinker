const std = @import("std");
const trie = @import("trie.zig");
const matcher = @import("matcher.zig");
const alphabet = "abcdefghijklmnopqrstuvwxyz";

pub fn main() !void {
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    var arena = std.heap.ArenaAllocator.init(debug_alloc.allocator());
    defer arena.deinit();
    const main_alloc = arena.allocator();
    const word_list_filename = "dicts/google_100";
    const word_list_file = try std.fs.cwd().openFile(word_list_filename, .{});
    const wlr = word_list_file.reader();
    var dict_trie = trie.WordTrie.init(main_alloc);
    defer dict_trie.deinit();
    var i: u32 = 0;
    var buf: [128]u8 = undefined;
    while (try wlr.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        i += 1;
        (try dict_trie.get((try trie.charsToLetters(main_alloc, line)).items)).leaf = 1000 / i;
    }
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();
    const subset = matcher.charsToSubset("etao");
    while (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const letters = try trie.charsToLetters(main_alloc, line);
        defer letters.deinit();
        var it = try matcher.expandInput(subset, &dict_trie, letters.items);
        while (try it.next()) |match| {
            const display = try trie.lettersToChars(main_alloc, match);
            defer display.deinit();
            try stdout.print("{s}\n", .{display.items});
            try bw.flush();
        }
    }
}
