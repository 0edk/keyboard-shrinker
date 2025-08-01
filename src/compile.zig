const std = @import("std");
const letters = @import("letters.zig");
const trie = @import("trie.zig");
const Allocator = std.mem.Allocator;

pub const available_letters = 1 << @typeInfo(letters.Letter).int.bits;
pub const LettersSubset = std.bit_set.IntegerBitSet(available_letters);
pub const Weight = f64;
pub const WeightedWord = struct { word: []const u8, weight: Weight };
pub const CompiledTrie = trie.Trie(letters.Letter, std.ArrayList(WeightedWord));
pub const WordList = std.StringHashMap(WeightedWord);

fn contractOutput(
    subset: LettersSubset,
    alloc: Allocator,
    word: []const u8,
) Allocator.Error!std.ArrayList(letters.Letter) {
    var subword = std.ArrayList(letters.Letter).init(alloc);
    for (word) |c| {
        if (letters.charToLetter(c)) |l| {
            if (subset.isSet(l)) {
                try subword.append(l);
            }
        }
    }
    return subword;
}

pub fn charsToSubset(str: []const u8) LettersSubset {
    var set: LettersSubset = LettersSubset.initEmpty();
    for (str) |c| {
        if (letters.charToLetter(c)) |l| {
            set.set(l);
        }
    }
    return set;
}

pub fn freeWords(allocator: Allocator, leaf: std.ArrayList(WeightedWord)) void {
    for (leaf.items) |ww| {
        allocator.free(ww.word);
    }
}

pub fn contractAddWord(
    node: *CompiledTrie,
    subset: LettersSubset,
    ww: WeightedWord,
) Allocator.Error!void {
    const contracted = try contractOutput(subset, node.allocator, ww.word);
    defer contracted.deinit();
    var child: *CompiledTrie = try node.get(contracted.items);
    if (child.leaf) |_| {} else {
        child.leaf = std.ArrayList(WeightedWord).init(child.allocator);
    }
    try child.leaf.?.append(ww);
}

test "compile google100" {
    const word_list_file = try std.fs.cwd().openFile("dicts/google_100", .{});
    const wlr = word_list_file.reader();
    var dict_trie = CompiledTrie.init(std.testing.allocator);
    defer dict_trie.deinit();
    var i: usize = 0;
    const subset = charsToSubset("etao");
    while (try wlr.readUntilDelimiterOrEofAlloc(std.testing.allocator, '\n', 128)) |line| {
        i += 1;
        try contractAddWord(
            &dict_trie,
            subset,
            .{ .word = line, .weight = 1 / @as(f64, @floatFromInt(i)) },
        );
    }
    normalise(&dict_trie);
    try std.testing.expectEqual(1.0, sumLeaves(&dict_trie));
    var it = try dict_trie.iterator();
    var found: usize = 0;
    while (try it.next()) |entry| {
        defer entry.deinit();
        const s = try letters.lettersToChars(std.testing.allocator, entry.key);
        std.debug.print("{s}: {{ ", .{s.items});
        s.deinit();
        for (entry.value.items) |ww| {
            found += 1;
            std.debug.print("{s} ({d}), ", .{ ww.word, ww.weight });
            std.testing.allocator.free(ww.word);
        }
        std.debug.print("}}\n", .{});
    }
    try std.testing.expectEqual(i, found);
}

fn sumLeaf(leaf: []const WeightedWord) Weight {
    var total: Weight = 0;
    for (leaf) |ww| {
        total += ww.weight;
    }
    return total;
}

fn sumLeaves(node: *const CompiledTrie) Weight {
    var total = if (node.leaf) |l| sumLeaf(l.items) else 0;
    for (node.children) |maybe_child| {
        if (maybe_child) |child| {
            total += sumLeaves(child);
        }
    }
    return total;
}

fn unscaleLeaf(divisor: Weight, leaf: std.ArrayList(WeightedWord)) void {
    for (0..leaf.items.len) |i| {
        leaf.items[i].weight /= divisor;
    }
}

pub fn normalise(node: *CompiledTrie) void {
    const total_weight = sumLeaves(node);
    node.deepForEach(total_weight, null, unscaleLeaf);
}

fn lessThanWord(_: void, lhs: WeightedWord, rhs: WeightedWord) bool {
    return lhs.weight > rhs.weight;
}

pub fn sortLeaf(_: void, leaf: std.ArrayList(WeightedWord)) void {
    std.mem.sort(WeightedWord, leaf.items, {}, lessThanWord);
}

pub fn loadWords(node: *CompiledTrie, subset: LettersSubset, words: WordList) Allocator.Error!void {
    var it = words.iterator();
    while (it.next()) |entry| {
        try contractAddWord(node, subset, entry.value_ptr.*);
    }
    normalise(node);
    node.deepForEach({}, null, sortLeaf);
}
