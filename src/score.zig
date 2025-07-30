const std = @import("std");
const compile = @import("compile.zig");
const trie = @import("trie.zig");
const Allocator = std.mem.Allocator;

pub const WordList = std.StringHashMap(compile.WeightedWord);

fn badnessLeaf(leaf: []const compile.WeightedWord) compile.Weight {
    var total: compile.Weight = 0;
    var max: compile.Weight = 0;
    for (leaf) |ww| {
        if (ww.weight > max) {
            max = ww.weight;
        }
        total += ww.weight;
    }
    return (total - max) * @as(f64, @floatFromInt(leaf.len));
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

pub fn badnessSubset(words: WordList, subset: compile.LettersSubset) Allocator.Error!compile.Weight {
    var dict_trie = compile.CompiledTrie.init(words.allocator);
    defer dict_trie.deinit();
    var it = words.iterator();
    while (it.next()) |entry| {
        try compile.contractAddWord(&dict_trie, subset, entry.value_ptr.*);
    }
    compile.normalise(&dict_trie);
    return badnessLeaves(&dict_trie);
}

pub fn climbStep(words: WordList, start: compile.LettersSubset, shrink: bool) Allocator.Error!?trie.Letter {
    var best: struct { ?trie.Letter, compile.Weight } = .{ null, std.math.inf(compile.Weight) };
    var trial = start;
    for (0..compile.available_letters) |i| {
        if (shrink == start.isSet(i)) {
            trial.toggle(i);
            const b = try badnessSubset(words, trial);
            if (b < best[1]) {
                best = .{ @intCast(i), b };
            }
            trial.toggle(i);
        }
    }
    return best[0];
}

pub fn climbToLen(words: WordList, start: compile.LettersSubset, target: trie.Letter) Allocator.Error!compile.LettersSubset {
    const source = start.count();
    var climber = start;
    if (source < target) {
        for (source..target) |_| {
            if (try climbStep(words, climber, false)) |l| {
                climber.set(l);
            }
        }
    } else if (source > target) {
        for (target..source) |_| {
            if (try climbStep(words, climber, true)) |l| {
                climber.unset(l);
            }
        }
    }
    std.debug.assert(climber.count() == target);
    return climber;
}
