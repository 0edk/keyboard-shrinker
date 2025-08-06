const std = @import("std");
const letters = @import("letters.zig");
const compile = @import("compile.zig");
const trie = @import("trie.zig");
const fillings = @import("fillings.zig");
const Allocator = std.mem.Allocator;

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
    completions: fillings.Completer,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .dict = compile.CompiledTrie.init(allocator),
            .literal = letters.String.init(allocator),
            .query = std.ArrayList(letters.Letter).init(allocator),
            .completions = fillings.Completer.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.dict.deinit();
        self.literal.deinit();
        self.query.deinit();
        self.completions.deinit();
    }

    fn resetCompletions(self: *Self) Allocator.Error!void {
        self.completions.deinit();
        self.completions = fillings.Completer.init(self.dict.allocator);
        try self.completions.start(self.query.items, try self.dict.get(self.query.items));
    }

    pub fn getCompletion(self: *const Self) Allocator.Error![]u8 {
        const raw = if (try self.completions.getCompletion()) |comp|
            comp
        else if (self.query.items.len > 0) blk: {
            var char_list = try letters.lettersToChars(self.dict.allocator, self.query.items);
            break :blk try char_list.toOwnedSlice();
        } else "";
        return applyCase(self.dict.allocator, raw, self.casing);
    }

    fn literalise(self: *Self) Allocator.Error!void {
        const completion = try self.getCompletion();
        if (completion.len > 0) {
            try self.literal.appendSlice(completion);
            self.dict.allocator.free(completion);
            self.query.clearRetainingCapacity();
            try self.resetCompletions();
        }
    }

    pub fn finishWord(self: *Self, next: ?u8) Allocator.Error![]u8 {
        try self.literalise();
        self.mode = .normal;
        self.casing = .unchanged;
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
        const leaf = node.leaf.?;
        for (leaf.items, 0..) |ww, i| {
            if (std.mem.eql(u8, ww.word, self.literal.items)) {
                if (i > 0) {
                    node.leaf.?.items[i].weight *= 2;
                    std.mem.sort(
                        compile.WeightedWord,
                        node.leaf.?.items[0 .. i + 1],
                        {},
                        compile.lessThanWord,
                    );
                }
                break;
            }
        } else {
            const precedent = if (leaf.items.len > 0) leaf.items[0].weight else 1;
            try node.leaf.?.insert(0, .{
                .word = try self.dict.allocator.dupe(u8, self.literal.items),
                .weight = precedent,
            });
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
                        if (self.completions.inferred()) |s| try self.query.appendSlice(s);
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
                .next => try self.completions.advance(),
                .previous => try self.completions.retreat(),
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
    try testActions(
        &ime,
        "a\x0e\x1bv a.",
        &[_]struct { usize, []const u8 }{
            .{ 4, "av " },
            .{ 6, "av." },
        },
    );
}
