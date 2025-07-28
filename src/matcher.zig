const std = @import("std");
const Allocator = std.mem.Allocator;
const trie = @import("trie.zig");

const MatchIteratorLayer = struct {
    node: *const trie.WordTrie,
    start: trie.Letter = 0,
};

const MatchIterator = struct {
    const Self = @This();
    subset: LettersSubset,
    nodes: std.ArrayList(MatchIteratorLayer),
    query: []trie.Letter,
    prefix: std.ArrayList(trie.Letter),
    index: usize = 0,

    pub fn next(self: *Self) Allocator.Error!?[]trie.Letter {
        while (self.nodes.pop()) |layer| {
            for (layer.start..AvailableLetters) |i| {
                if (layer.node.children[i]) |child| {
                    const at_query = self.index < self.query.len and i == self.query[self.index];
                    const outside_subset = !self.subset[i];
                    if (at_query or outside_subset) {
                        try self.nodes.append(.{ .node = layer.node, .start = @intCast(i + 1) });
                        try self.nodes.append(.{ .node = child });
                        try self.prefix.append(@intCast(i));
                        if (at_query) {
                            self.index += 1;
                        }
                        if (child.leaf > 0 and self.index == self.query.len) {
                            return self.prefix.items;
                        }
                        break;
                    }
                }
            } else {
                if (self.prefix.pop()) |last| {
                    if (self.index > 0 and last == self.query[self.index - 1]) {
                        self.index -= 1;
                    }
                }
            }
        }
        self.nodes.deinit();
        self.prefix.deinit();
        return null;
    }
};

pub fn expandInput(subset: LettersSubset, start: *const trie.WordTrie, query: []trie.Letter) Allocator.Error!MatchIterator {
    const alloc = start.allocator;
    var nodes = std.ArrayList(MatchIteratorLayer).init(alloc);
    try nodes.append(.{
        .node = start,
    });
    const prefix = std.ArrayList(trie.Letter).init(alloc);
    return MatchIterator{
        .subset = subset,
        .nodes = nodes,
        .query = query,
        .prefix = prefix,
    };
}

const AvailableLetters = 1 << @typeInfo(trie.Letter).int.bits;
const LettersSubset = [AvailableLetters]bool;

pub fn charsToSubset(str: []const u8) LettersSubset {
    var set: LettersSubset = [_]bool{false} ** AvailableLetters;
    for (str) |c| {
        if (trie.charToLetter(c)) |l| {
            set[l] = true;
        }
    }
    return set;
}

test "match google100" {
    const word_list_file = try std.fs.cwd().openFile("dicts/google_100", .{});
    const wlr = word_list_file.reader();
    var dict_trie = trie.WordTrie.init(std.testing.allocator);
    defer dict_trie.deinit();
    var i: u32 = 0;
    var buf: [128]u8 = undefined;
    while (try wlr.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        i += 1;
        const s = try trie.charsToLetters(std.testing.allocator, line);
        (try dict_trie.get(s.items)).leaf = 1000 / i;
        s.deinit();
    }
    const subset = charsToSubset("etao");
    const queries = [_][]const u8{ "ee", "tat", "ao", "t", "" };
    const answer_lists = [_][]const []const u8{
        &([_][]const u8{ "free", "see", "here", "been", "were", "services", "service" }),
        &([_][]const u8{"that"}),
        &([_][]const u8{"also"}),
        &([_][]const u8{ "this", "with", "it", "but", "first", "its" }),
        &([_][]const u8{ "in", "is", "by", "i", "will", "us", "if", "my", "up", "which", "his", "pm", "c", "s", "click", "x", "find" }),
    };
    var match_set = std.StringHashMap(void).init(std.testing.allocator);
    defer match_set.deinit();
    for (queries, answer_lists) |query, answers| {
        const ql = try trie.charsToLetters(std.testing.allocator, query);
        defer ql.deinit();
        for (answers) |answer| {
            try match_set.put(answer, {});
        }
        var it = try expandInput(subset, &dict_trie, ql.items);
        while (try it.next()) |match| {
            const s = try trie.lettersToChars(std.testing.allocator, match);
            try std.testing.expect(match_set.remove(s.items));
            s.deinit();
        }
        try std.testing.expectEqual(0, match_set.count());
    }
}
