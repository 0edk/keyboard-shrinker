const std = @import("std");
const letters = @import("letters.zig");
const compile = @import("compile.zig");
const trie = @import("trie.zig");
const Allocator = std.mem.Allocator;

const Choices = std.ArrayList(compile.WeightedWord);
const Casing = enum { all_caps, title, lower, unchanged };
const InputMode = enum { insert, normal };
pub const Action = union(enum) {
    char: u8,
    backspace,
    finish_partial,
    next,
    previous,
    deter,
    to_insert,
    to_normal,
};
const InputResult = union(enum) { silent, text: []const u8, pass };
const Completion = struct { node: *compile.CompiledTrie, suffix: []const letters.Letter };

fn compareCompletion(_: void, a: Completion, b: Completion) std.math.Order {
    if (a.node.leaf) |al| {
        return if (b.node.leaf) |bl| std.math.order(bl.items[0].weight, al.items[0].weight) else .lt;
    } else {
        return if (b.node.leaf != null) .gt else .eq;
    }
}

fn applyCase(allocator: Allocator, word: []const u8, casing: Casing) Allocator.Error![]u8 {
    return switch (casing) {
        .all_caps => std.ascii.allocUpperString(allocator, word),
        .title => for (word) |c| {
            if (std.ascii.isUpper(c)) {
                break allocator.dupe(u8, word);
            }
        } else blk: {
            if (word.len == 0) {
                break :blk allocator.alloc(u8, 0);
            } else {
                var copy = try allocator.dupe(u8, word);
                copy[0] = std.ascii.toUpper(copy[0]);
                break :blk copy;
            }
        },
        .lower => std.ascii.allocLowerString(allocator, word),
        .unchanged => allocator.dupe(u8, word),
    };
}

pub const ShrunkenInputMethod = struct {
    const Self = @This();
    usable_keys: compile.LettersSubset = compile.LettersSubset.initEmpty(),
    dict: compile.CompiledTrie,
    mode: InputMode = .normal,
    casing: Casing = .unchanged,
    literal: letters.String,
    query: std.ArrayList(letters.Letter),
    completions: std.ArrayList(Completion),
    choice: ?struct { usize, usize } = null,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .dict = compile.CompiledTrie.init(allocator),
            .literal = letters.String.init(allocator),
            .query = std.ArrayList(letters.Letter).init(allocator),
            .completions = std.ArrayList(Completion).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.dict.deinit();
        self.literal.deinit();
        self.query.deinit();
        for (self.completions.items) |comp| {
            self.dict.allocator.free(comp.suffix);
        }
        self.completions.deinit();
    }

    pub fn getCompletion(self: *const Self) Allocator.Error!?compile.WeightedWord {
        if (self.choice) |inds| {
            return self.completions.items[inds[0]].node.leaf.?.items[inds[1]];
        } else {
            var chars = try letters.lettersToChars(self.dict.allocator, self.query.items);
            return .{ .word = try chars.toOwnedSlice(), .weight = 0 };
        }
    }

    fn adjustChoice(self: *Self) Allocator.Error!bool {
        if (self.choice) |inds| {
            if (inds[0] >= self.completions.items.len) {
                try self.loadCompletions();
                if (inds[0] >= self.completions.items.len) {
                    self.choice = null;
                    return false;
                } else {
                    return true;
                }
            } else if (self.completions.items[inds[0]].node.leaf) |words| {
                if (inds[1] >= words.items.len) {
                    self.choice = if (inds[0] == 0 and self.query.items.len == 0)
                        null
                    else
                        .{ inds[0] + 1, 0 };
                    return true;
                }
            } else {
                self.choice = .{ inds[0] + 1, 0 };
                return true;
            }
        }
        return false;
    }

    fn loadCompletions(self: *Self) Allocator.Error!void {
        if (self.completions.getLastOrNull()) |last| {
            const depth = last.suffix.len;
            var arena = std.heap.ArenaAllocator.init(self.dict.allocator);
            defer arena.deinit();
            const alloc = arena.allocator();
            var candidates = std.PriorityQueue(
                Completion,
                void,
                compareCompletion,
            ).init(alloc, {});
            defer candidates.deinit();
            for (self.completions.items) |comp| {
                if (comp.suffix.len == depth) {
                    for (comp.node.children, 0..) |maybe_child, l| {
                        if (maybe_child) |child| {
                            var suffix = try self.dict.allocator.alloc(letters.Letter, depth + 1);
                            @memcpy(suffix[0..depth], comp.suffix);
                            suffix[depth] = @intCast(l);
                            try candidates.add(.{ .node = child, .suffix = suffix });
                        }
                    }
                }
            }
            while (candidates.removeOrNull()) |comp| {
                try self.completions.append(comp);
            }
        }
    }

    fn resetCompletions(self: *Self) Allocator.Error!void {
        for (self.completions.items) |comp| {
            self.dict.allocator.free(comp.suffix);
        }
        self.completions.clearRetainingCapacity();
        try self.completions.append(.{
            .node = try self.dict.get(self.query.items),
            .suffix = &[0]letters.Letter{},
        });
        try self.loadCompletions();
        self.choice = if (self.query.items.len == 0) null else .{ 0, 0 };
        while (try self.adjustChoice()) {}
    }

    fn literalise(self: *Self) Allocator.Error!void {
        if (self.choice != null or self.query.items.len > 0) {
            const completion = try applyCase(
                self.dict.allocator,
                if (try self.getCompletion()) |comp| comp.word else "?",
                self.casing,
            );
            try self.literal.appendSlice(completion);
            self.dict.allocator.free(completion);
            // TODO: what do we increment here?
            //leaf.items[i].weight *= 2;
            //std.mem.sort(
            //    compile.WeightedWord,
            //    leaf.items[0..i + 1],
            //    {},
            //    compile.lessThanWord,
            //);
            self.query.clearRetainingCapacity();
            try self.resetCompletions();
        }
    }

    pub fn finishWord(self: *Self, next: ?u8) Allocator.Error![]u8 {
        const maybe_new = self.literal.items.len > 0 or
            if (self.dict.getOrNull(self.query.items)) |node| node.leaf == null else true;
        try self.literalise();
        self.mode = .normal;
        self.casing = .unchanged;
        if (maybe_new) {
            const contracted = try compile.contractOutput(
                self.usable_keys,
                self.dict.allocator,
                self.literal.items,
            );
            defer contracted.deinit();
            var node = try self.dict.get(contracted.items);
            if (node.leaf == null) {
                node.leaf = std.ArrayList(compile.WeightedWord).init(self.dict.allocator);
            }
            var leaf = node.leaf.?;
            for (leaf.items) |ww| {
                if (std.mem.eql(u8, ww.word, self.literal.items)) {
                    break;
                }
            } else {
                const precedent = if (leaf.items.len > 0) leaf.items[0].weight else 1;
                try leaf.insert(0, .{
                    .word = try self.dict.allocator.dupe(u8, self.literal.items),
                    .weight = precedent,
                });
            }
        }
        if (next) |c| try self.literal.append(c);
        return self.literal.toOwnedSlice();
    }

    pub fn handleAction(
        self: *Self,
        insert: Action,
        normal: Action,
        modded: bool,
    ) Allocator.Error!InputResult {
        if (modded) {
            return .pass;
        } else if (self.mode == .insert) {
            switch (insert) {
                .char => |c| if (letters.charToLetter(c) == null) {
                    return if (self.finishWord(c)) |t| .{ .text = t } else |e| e;
                } else {
                    try self.literal.append(c);
                },
                .backspace => if (self.literal.pop() == null) {
                    self.mode = .normal;
                    return .pass;
                },
                .to_normal => self.mode = .normal,
                // TODO
                else => return .silent,
            }
        } else {
            switch (normal) {
                .char => |c| if (letters.charToLetter(c)) |l| {
                    if (self.usable_keys.isSet(l)) {
                        if (self.query.items.len == 0) {
                            self.casing = if (std.ascii.isUpper(c)) .title else .unchanged;
                        } else if (self.query.items.len == 1 and self.casing == .title and
                            std.ascii.isUpper(c))
                        {
                            self.casing = .all_caps;
                        } else if (self.casing == .all_caps and std.ascii.isLower(c)) {
                            self.casing = .title;
                        }
                        try self.query.append(l);
                        try self.resetCompletions();
                    }
                } else {
                    return if (self.finishWord(c)) |t| .{ .text = t } else |e| e;
                },
                .backspace => if (self.query.pop() != null) {
                    try self.resetCompletions();
                } else if (self.literal.pop() != null) {
                    self.mode = .insert;
                } else {
                    return .pass;
                },
                .finish_partial => {
                    try self.literalise();
                    self.casing = .unchanged;
                },
                .next => {
                    if (self.choice != null) {
                        self.choice.?[1] += 1;
                    } else if (self.query.items.len == 0) {
                        self.choice = .{ 0, 0 };
                    } else {
                        self.choice = .{ 1, 0 };
                    }
                    while (try self.adjustChoice()) {}
                },
                .previous => {
                    // TODO
                },
                // TODO
                .deter => return .silent,
                .to_insert => {
                    try self.literalise();
                    self.mode = .insert;
                },
                .to_normal => return .silent,
            }
        }
        return .silent;
    }
};

fn testActions(
    ime: *ShrunkenInputMethod,
    action_chars: []const u8,
    results: []const struct { usize, []const u8 },
) !void {
    var result_ind: usize = 0;
    for (action_chars, 0..) |ac, i| {
        const action: Action = switch (ac) {
            '\t' => .finish_partial,
            '\x0e' => .next,
            '\x1b' => .to_insert,
            '\x08' => .backspace,
            else => |c| .{ .char = c },
        };
        const fr = try if (ime.mode == .insert)
            ime.handleAction(action, .{ .char = ' ' }, false)
        else
            ime.handleAction(.{ .char = ' ' }, action, false);
        switch (fr) {
            .text => |frs| {
                try std.testing.expectEqual(results[result_ind][0], i);
                try std.testing.expectEqualStrings(results[result_ind][1], frs);
                result_ind += 1;
                std.testing.allocator.free(frs);
            },
            else => std.debug.print("result {any} at index {d}\n", .{ fr, i }),
        }
    }
}

test "input basics" {
    const word_list_file = try std.fs.cwd().openFile("dicts/google_100", .{});
    const wlr = word_list_file.reader();
    var ime = ShrunkenInputMethod.init(std.testing.allocator);
    defer ime.deinit();
    defer ime.dict.deepForEach(ime.dict.allocator, null, compile.freeWords);
    ime.usable_keys = compile.charsToSubset("acdeilnorstu");
    var i: usize = 0;
    while (try wlr.readUntilDelimiterOrEofAlloc(std.testing.allocator, '\n', 128)) |line| {
        i += 1;
        try compile.contractAddWord(
            &ime.dict,
            ime.usable_keys,
            .{ .word = line, .weight = 1 / @as(f64, @floatFromInt(i)) },
        );
    }
    ime.dict.deepForEach({}, null, compile.sortLeaf);
    try testActions(
        &ime,
        "Et tis: Ro\tae\x0e\x0e\x1b\x08\x08age!\x08.",
        &[_]struct { usize, []const u8 }{
            .{ 2, "Get " },
            .{ 6, "this:" },
            .{ 7, " " },
            .{ 21, "Fromage!" },
            .{ 23, "." },
        },
    );
}

test "new words" {
    var ime = ShrunkenInputMethod.init(std.testing.allocator);
    defer ime.deinit();
    ime.usable_keys = compile.charsToSubset("acdeilnorstu");
    // TODO
}
