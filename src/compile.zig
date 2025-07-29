const std = @import("std");
const trie = @import("trie.zig");
const Allocator = std.mem.Allocator;

const available_letters = 1 << @typeInfo(trie.Letter).int.bits;
const LettersSubset = [available_letters]bool;
pub const Weight = f64;
const WeightedWord = struct { word: []const u8, weight: Weight };
pub const CompiledTrie = trie.Trie(trie.Letter, std.ArrayList(WeightedWord));

fn contractOutput(subset: LettersSubset, alloc: Allocator, word: []const u8) Allocator.Error!std.ArrayList(trie.Letter) {
    var subword = std.ArrayList(trie.Letter).init(alloc);
    for (word) |c| {
        if (trie.charToLetter(c)) |l| {
            if (subset[l]) {
                try subword.append(l);
            }
        }
    }
    return subword;
}

pub fn charsToSubset(str: []const u8) LettersSubset {
    var set: LettersSubset = [_]bool{false} ** available_letters;
    for (str) |c| {
        if (trie.charToLetter(c)) |l| {
            set[l] = true;
        }
    }
    return set;
}

fn lessThanWord(_: void, lhs: WeightedWord, rhs: WeightedWord) bool {
    return lhs.weight > rhs.weight;
}

pub fn contractAddWord(node: *CompiledTrie, subset: LettersSubset, ww: WeightedWord) Allocator.Error!void {
    const contracted = try contractOutput(subset, node.allocator, ww.word);
    defer contracted.deinit();
    var child: *CompiledTrie = try node.get(contracted.items);
    if (child.leaf.items.len > 0) {
        try (&child.leaf).append(ww);
        std.mem.sort(WeightedWord, child.leaf.items, {}, lessThanWord);
    } else {
        child.leaf = std.ArrayList(WeightedWord).init(child.allocator);
        try child.leaf.append(ww);
    }
}

test "compile google100" {
    const word_list_file = try std.fs.cwd().openFile("dicts/google_100", .{});
    const wlr = word_list_file.reader();
    var dict_trie = CompiledTrie.init(std.testing.allocator);
    defer dict_trie.deinit();
    var i: Weight = 0;
    const subset = charsToSubset("etao");
    while (try wlr.readUntilDelimiterOrEofAlloc(std.testing.allocator, '\n', 128)) |line| {
        i += 1;
        try contractAddWord(&dict_trie, subset, .{ .word = line, .weight = i });
    }
    var it = try dict_trie.iterator();
    var found: usize = 0;
    while (try it.next()) |entry| {
        defer entry.deinit();
        const s = try trie.lettersToChars(std.testing.allocator, entry.key);
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
    var total = if (node.leaf.items.len > 0) sumLeaf(node.leaf.items) else 0;
    for (node.children) |maybe_child| {
        if (maybe_child) |child| {
            total += sumLeaves(child);
        }
    }
    return total;
}

fn unscaleLeaf(leaf: []WeightedWord, divisor: Weight) void {
    for (0..leaf.len) |i| {
        leaf[i].weight /= divisor;
    }
}

pub fn unscaleLeaves(node: *CompiledTrie, divisor: Weight) void {
    if (node.leaf.items.len > 0) {
        unscaleLeaf(node.leaf.items, divisor);
    }
    for (node.children) |maybe_child| {
        if (maybe_child) |child| {
            unscaleLeaves(child, divisor);
        }
    }
}

pub fn normalise(node: *CompiledTrie) void {
    const total_weight = sumLeaves(node);
    unscaleLeaves(node, total_weight);
}
