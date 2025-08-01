const std = @import("std");
const letters = @import("letters.zig");
const compile = @import("compile.zig");
const trie = @import("trie.zig");
const Allocator = std.mem.Allocator;

const Choices = std.ArrayList(compile.WeightedWord);
const Casing = enum { all_caps, title, lower };
const InputMode = enum { insert, normal };
const Action = union(enum) {
    letter: letters.Letter,
    symbol: u8,
    special: enum {
        backspace,
        finish_partial,
        next,
        previous,
        deter,
        to_insert,
        to_normal,
    },
};
const InputResult = Allocator.Error!?[]u8;

fn applyCase(allocator: Allocator, word: []const u8, casing: Casing) Allocator.Error![]u8 {
    return switch (casing) {
        .all_caps => std.ascii.allocUpperString(allocator, word),
        .title => allocator.dupe(u8, word),
        .lower => std.ascii.allocLowerString(allocator, word),
    };
}

pub const ShrunkenInputMethod = struct {
    const Self = @This();
    usable_keys: compile.LettersSubset = compile.LettersSubset.initEmpty(),
    dict: compile.CompiledTrie,
    mode: InputMode = .normal,
    casing: Casing = .title,
    literal: letters.String,
    query: std.ArrayList(trie.IteratorLayer(letters.Letter, Choices)),
    choice: usize = 0,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .dict = compile.CompiledTrie.init(allocator),
            .literal = letters.String.init(allocator),
            .query = std.ArrayList(trie.IteratorLayer(letters.Letter, Choices)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.dict.deinit();
        self.literal.deinit();
        self.query.deinit();
    }

    pub fn finishWord(self: *Self, next: ?u8) InputResult {
        const sn = if (self.query.getLastOrNull()) |top| top.node else if (self.choice > 0) blk: {
            self.choice -= 1;
            break :blk &self.dict;
        } else null;
        if (sn) |node| {
            if (node.leaf) |choice_list| {
                const raw_word = choice_list.items[@min(self.choice, choice_list.items.len - 1)];
                try self.literal.appendSlice(try applyCase(
                    self.dict.allocator,
                    raw_word.word,
                    self.casing,
                ));
            }
        }
        self.mode = .normal;
        self.casing = .title;
        self.query.clearRetainingCapacity();
        self.choice = 0;
        if (next) |c| try self.literal.append(c);
        const word = self.literal.items;
        self.literal.clearRetainingCapacity();
        return word;
    }

    pub fn handleAction(self: *Self, insert: Action, normal: Action) InputResult {
        switch (self.mode) {
            .insert => switch (insert) {
                .letter => |l| try self.literal.append(letters.letterToChar(l) orelse return null),
                .symbol => |c| return self.finishWord(c),
                .special => |a| switch (a) {
                    // TODO
                    else => return null,
                },
            },
            .normal => switch (normal) {
                .letter => |l| if (self.usable_keys.isSet(l)) {
                    const last_child = if (self.query.getLastOrNull()) |top| top.node else &self.dict;
                    if (last_child.children[l]) |next_child| {
                        try self.query.append(.{ .start = l, .node = next_child });
                    }
                    // TODO
                },
                .symbol => |c| return self.finishWord(c),
                .special => |a| switch (a) {
                    // TODO
                    else => return null,
                },
            },
        }
        return null;
    }
};

test "input basics" {
    const word_list_file = try std.fs.cwd().openFile("dicts/google_100", .{});
    const wlr = word_list_file.reader();
    var ime = ShrunkenInputMethod.init(std.testing.allocator);
    defer ime.deinit();
    defer ime.dict.deepForEach(ime.dict.allocator, null, compile.freeWords);
    ime.usable_keys = compile.charsToSubset("acdeinorst");
    var i: usize = 0;
    while (try wlr.readUntilDelimiterOrEofAlloc(std.testing.allocator, '\n', 128)) |line| {
        i += 1;
        try compile.contractAddWord(
            &ime.dict,
            ime.usable_keys,
            .{ .word = line, .weight = 1 / @as(f64, @floatFromInt(i)) },
        );
    }
    compile.normalise(&ime.dict);
    ime.dict.deepForEach({}, null, compile.sortLeaf);
    const test_actions = [_]Action{
        .{ .letter = 4 },
        .{ .letter = 19 },
        .{ .symbol = ' ' },
    };
    const test_results = [_]?[]const u8{
        null,
        null,
        "get ",
    };
    for (test_actions, test_results) |a, dr| {
        const fr = try ime.handleAction(.{ .letter = 0 }, a);
        if (fr) |frs| {
            try std.testing.expectEqualStrings(dr.?, frs);
        } else {
            try std.testing.expectEqual(dr, null);
        }
    }
}
