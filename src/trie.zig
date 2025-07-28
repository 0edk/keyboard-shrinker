const std = @import("std");
const Allocator = std.mem.Allocator;
const String = std.ArrayList(u8);

pub fn Trie(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const N = 1 << @typeInfo(K).int.bits;
        leaf: V = 0,
        children: [N]?*Self = [_]?*Self{null} ** N,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.children) |maybe_child| {
                if (maybe_child) |child| {
                    child.deinit();
                    self.allocator.destroy(child);
                }
            }
        }

        pub fn get(self: *Self, key: []const K) Allocator.Error!*Self {
            if (key.len == 0) {
                return self;
            } else {
                if (self.children[key[0]]) |child| {
                    return child.get(key[1..]);
                } else {
                    const child = try self.allocator.create(Self);
                    child.* = Self.init(self.allocator);
                    self.children[key[0]] = child;
                    return child.get(key[1..]);
                }
            }
        }

        pub fn show(self: *const Self, writer: anytype, depth: usize) !void {
            for (0..self.children.len) |i| {
                if (self.children[i]) |child| {
                    for (0..depth) |_| {
                        std.debug.print("  ", .{});
                    }
                    std.debug.print("{d}{s}\n", .{ i, if (child.leaf != 0) "$" else "" });
                    try child.show(writer, depth + 1);
                }
            }
        }
    };
}

pub const Letter = u5;
pub const WordTrie = Trie(Letter, u32);

test "trie on string" {
    var trie = WordTrie.init(std.testing.allocator);
    defer trie.deinit();
    const words = [_][]const u8{ "a", "to", "tea", "ted", "ten", "i", "in", "inn" };
    for (words) |word| {
        const letters = try charsToLetters(std.testing.allocator, word);
        const branch = try trie.get(letters.items);
        letters.deinit();
        branch.leaf += 1;
    }
    for (words) |word| {
        const letters = try charsToLetters(std.testing.allocator, word);
        try std.testing.expectEqual(1, (try trie.get(letters.items)).leaf);
        letters.deinit();
    }
    try trie.show(void, 0);
}

pub fn charToLetter(char: u8) ?Letter {
    if (std.ascii.isAlphabetic(char)) {
        return @intCast(std.ascii.toLower(char) - 'a');
    }
    return null;
}

pub fn charsToLetters(allocator: Allocator, str: []const u8) Allocator.Error!std.ArrayList(Letter) {
    var projected = std.ArrayList(Letter).init(allocator);
    for (str) |c| {
        if (charToLetter(c)) |l| {
            try projected.append(l);
        }
    }
    return projected;
}

pub fn lettersToChars(allocator: Allocator, letters: []const Letter) Allocator.Error!std.ArrayList(u8) {
    var s = try String.initCapacity(allocator, letters.len);
    for (letters) |l| {
        const c: u8 = l;
        try s.append(c + 'a');
    }
    return s;
}
