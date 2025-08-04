const std = @import("std");
const letters = @import("letters.zig");
const compile = @import("compile.zig");
const trie = @import("trie.zig");
const Allocator = std.mem.Allocator;

const Choices = std.ArrayList(compile.WeightedWord);
const Casing = enum { all_caps, title, lower };
const InputMode = enum { insert, normal };
const Action = union(enum) {
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
    };
}

pub const ShrunkenInputMethod = struct {
    const Self = @This();
    usable_keys: compile.LettersSubset = compile.LettersSubset.initEmpty(),
    dict: compile.CompiledTrie,
    mode: InputMode = .normal,
    casing: Casing = .title,
    literal: letters.String,
    query: std.ArrayList(letters.Letter),
    choice: usize = 0,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .dict = compile.CompiledTrie.init(allocator),
            .literal = letters.String.init(allocator),
            .query = std.ArrayList(letters.Letter).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.dict.deinit();
        self.literal.deinit();
        self.query.deinit();
    }

    pub fn getCompletion(self: *const Self) Allocator.Error![]const u8 {
        if (self.dict.getOrNull(self.query.items)) |node| {
            if (node.leaf) |words| {
                if (self.query.items.len == 0) {
                    return if (self.choice == 0) "" else words.items[self.choice - 1].word;
                } else {
                    return words.items[self.choice].word;
                }
            } else {
                return "";
            }
            // TODO: extend/autocomplete when you can
        } else {
            return (try letters.lettersToChars(self.dict.allocator, self.query.items)).items;
        }
    }

    fn literalise(self: *Self) Allocator.Error!void {
        const completion = try applyCase(
            self.dict.allocator,
            try self.getCompletion(),
            self.casing,
        );
        try self.literal.appendSlice(completion);
        self.dict.allocator.free(completion);
        self.query.clearRetainingCapacity();
    }

    pub fn finishWord(self: *Self, next: ?u8) Allocator.Error![]u8 {
        try self.literalise();
        self.mode = .normal;
        self.casing = .title;
        self.choice = 0;
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
                .char => |c| if (letters.charToLetter(c)) |_| {
                    try self.literal.append(c);
                } else {
                    return if (self.finishWord(c)) |t| .{ .text = t } else |e| e;
                },
                .backspace => if (self.literal.pop()) |_| {} else {
                    self.mode = .normal;
                    return .pass;
                },
                // TODO
                else => return .silent,
            }
        } else {
            switch (normal) {
                .char => |c| if (letters.charToLetter(c)) |l| {
                    if (self.usable_keys.isSet(l)) {
                        if (self.query.items.len == 0) {
                            self.casing = if (std.ascii.isUpper(c)) .all_caps else .lower;
                        } else if (self.casing == .all_caps and std.ascii.isLower(c) or
                            self.casing == .lower and std.ascii.isUpper(c))
                        {
                            self.casing = .title;
                        }
                        try self.query.append(l);
                    }
                } else {
                    return if (self.finishWord(c)) |t| .{ .text = t } else |e| e;
                },
                .backspace => if (self.query.pop()) |_| {
                    self.choice = 0;
                } else if (self.literal.pop()) |_| {
                    self.mode = .insert;
                } else {
                    return .pass;
                },
                .finish_partial => {
                    try self.literalise();
                    self.casing = .title;
                    self.choice = 0;
                },
                // TODO
                .next => return .silent,
                .previous => return .silent,
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
    compile.normalise(&ime.dict);
    ime.dict.deepForEach({}, null, compile.sortLeaf);
    const test_action_chars = "Et tis: Ro\tae\x0e\x0e\x1b\x08\x08\x08\x08age!\x08.";
    const test_results = [_]struct { usize, InputResult }{
        .{ 2, .{ .text = "Get " } },
        .{ 6, .{ .text = "this:" } },
        .{ 7, .{ .text = " " } },
        .{ 23, .{ .text = "Fromage!" } },
        .{ 25, .{ .text = "." } },
    };
    var result_ind: usize = 0;
    for (test_action_chars, 0..) |ac, j| {
        const a: Action = switch (ac) {
            '\t' => .finish_partial,
            '\x0e' => .next,
            '\x1b' => .to_insert,
            '\x08' => .backspace,
            else => |c| .{ .char = c },
        };
        const fr = try if (ime.mode == .insert) ime.handleAction(a, .{ .char = ' ' }, false) else ime.handleAction(.{ .char = ' ' }, a, false);
        switch (fr) {
            .text => |frs| {
                try std.testing.expectEqual(test_results[result_ind][0], j);
                try std.testing.expectEqualStrings(test_results[result_ind][1].text, frs);
                result_ind += 1;
                std.testing.allocator.free(frs);
            },
            else => std.debug.print("result {any} at index {d}\n", .{ fr, j }),
        }
    }
}
