const std = @import("std");
const letters = @import("letters.zig");
const trie = @import("trie.zig");
const compile = @import("compile.zig");
const Allocator = std.mem.Allocator;

fn badnessLeaf(leaf: []compile.WeightedWord, depth: compile.Weight) compile.Weight {
    var prob: compile.Weight = 0;
    var total: compile.Weight = 0;
    for (0..leaf.len, leaf) |i, ww| {
        const k: compile.Weight = @floatFromInt(if (depth == 0) i + 1 else i);
        prob += ww.weight;
        total += k * ww.weight;
    }
    return depth * prob + total;
}

pub fn badnessLeaves(node: *const compile.CompiledTrie, depth: compile.Weight) compile.Weight {
    var total = if (node.leaf) |l| badnessLeaf(l.items, depth) else 0;
    for (node.children) |maybe_child| {
        if (maybe_child) |child| {
            total += badnessLeaves(child, depth + 1);
        }
    }
    return total;
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
        try compile.contractAddWord(
            &dict_trie,
            subset,
            .{ .word = line, .weight = 1 / @as(f64, @floatFromInt(i)) },
        );
    }
    std.debug.print("badness {d}\n", .{badnessLeaves(&dict_trie, 0)});
    dict_trie.deepForEach(dict_trie.allocator, null, compile.freeWords);
}

pub fn badnessSubset(
    words: compile.WordList,
    subset: compile.LettersSubset,
) Allocator.Error!compile.Weight {
    var arena = std.heap.ArenaAllocator.init(words.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var dict_trie = compile.CompiledTrie.init(alloc);
    var it = words.iterator();
    while (it.next()) |entry| {
        try compile.contractAddWord(&dict_trie, subset, entry.value_ptr.*);
    }
    const badness = badnessLeaves(&dict_trie, 0);
    return badness;
}

pub fn climbStep(
    words: compile.WordList,
    start: compile.LettersSubset,
    shrink: bool,
) Allocator.Error!?letters.Letter {
    var best: struct { ?letters.Letter, compile.Weight } = .{ null, std.math.inf(compile.Weight) };
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

pub fn climbToLen(
    words: compile.WordList,
    start: compile.LettersSubset,
    target: letters.Letter,
) Allocator.Error!compile.LettersSubset {
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

test "optimise google100" {
    const word_list_file = try std.fs.cwd().openFile("dicts/google_100", .{});
    const wlr = word_list_file.reader();
    var word_list = compile.WordList.init(std.testing.allocator);
    defer word_list.deinit();
    var i: compile.Weight = 0;
    while (try wlr.readUntilDelimiterOrEofAlloc(std.testing.allocator, '\n', 128)) |line| {
        i += 1;
        try word_list.put(line, .{ .word = line, .weight = 1 / i });
    }
    const start_subset = compile.charsToSubset("etao");
    std.debug.print("{any} -> {any}\n", .{ start_subset, climbToLen(word_list, start_subset, 8) });
    var it = word_list.iterator();
    while (it.next()) |entry| {
        std.testing.allocator.free(entry.value_ptr.word);
    }
}
