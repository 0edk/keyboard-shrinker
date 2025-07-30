const std = @import("std");
const compile = @import("compile.zig");
const Allocator = std.mem.Allocator;

fn badnessLeaf(leaf: []const compile.WeightedWord) compile.Weight {
    var total: compile.Weight = 0;
    for (leaf[1..]) |ww| {
        total += ww.weight;
    }
    return total * @as(f64, @floatFromInt(leaf.len));
}

pub fn badnessLeaves(node: *const compile.CompiledTrie) compile.Weight {
    var total = if (node.leaf.items.len > 0) badnessLeaf(node.leaf.items) else 0;
    for (node.children) |maybe_child| {
        if (maybe_child) |child| {
            total += badnessLeaves(child);
        }
    }
    return total;
}

fn freeWords(allocator: Allocator, leaf: std.ArrayList(compile.WeightedWord)) void {
    for (leaf.items) |ww| {
        allocator.free(ww.word);
    }
}

// TODO: result looks wrong
test "score google100" {
    const word_list_file = try std.fs.cwd().openFile("dicts/google_100", .{});
    const wlr = word_list_file.reader();
    var dict_trie = compile.CompiledTrie.init(std.testing.allocator);
    defer dict_trie.deinit();
    var i: usize = 0;
    const subset = compile.charsToSubset("etao");
    while (try wlr.readUntilDelimiterOrEofAlloc(std.testing.allocator, '\n', 128)) |line| {
        i += 1;
        try compile.contractAddWord(&dict_trie, subset, .{ .word = line, .weight = 1 / @as(f64, @floatFromInt(i)) });
    }
    compile.normalise(&dict_trie);
    std.debug.print("badness {d}\n", .{badnessLeaves(&dict_trie)});
    dict_trie.deepForEach(dict_trie.allocator, null, freeWords);
}
