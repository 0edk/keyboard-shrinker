const std = @import("std");
const Allocator = std.mem.Allocator;
const String = std.ArrayList(u8);

fn default(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .int => 0,
        .optional => null,
        .@"struct" => T.init(undefined),
        else => unreachable,
    };
}

fn nonzero(comptime T: type, x: T) bool {
    return switch (@typeInfo(T)) {
        .int => x > 0,
        .optional => if (x) |_| true else false,
        .@"struct" => x.items.len > 0,
        else => unreachable,
    };
}

pub fn Trie(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const N = 1 << @typeInfo(K).int.bits;
        leaf: V = default(V),
        children: [N]?*Self = [_]?*Self{null} ** N,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        fn deinitBf(_: void, self: *Self) void {
            self.allocator.destroy(self);
        }

        fn deinitLf(_: void, leaf: V) void {
            switch (@typeInfo(V)) {
                .@"struct" => leaf.deinit(),
                else => {},
            }
        }

        pub fn deinit(self: *Self) void {
            self.deepForEach({}, Self.deinitBf, Self.deinitLf);
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

        pub fn deepForEach(self: *Self, context: anytype, bf: ?fn (@TypeOf(context), *Self) void, lf: ?fn (@TypeOf(context), V) void) void {
            if (lf) |f| {
                if (nonzero(V, self.leaf)) {
                    f(context, self.leaf);
                }
            }
            for (self.children) |maybe_child| {
                if (maybe_child) |child| {
                    child.deepForEach(context, bf, lf);
                    if (bf) |f| {
                        f(context, child);
                    }
                }
            }
        }

        pub fn iterator(self: *Self) Allocator.Error!Iterator(K, V) {
            var stack = std.ArrayList(IteratorLayer(K, V)).init(self.allocator);
            try stack.append(.{ .start = 0, .node = self });
            return .{ .stack = stack };
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

fn Entry(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        key: []K,
        value: V,
        node: *Trie(K, V),
        allocator: Allocator,

        pub fn deinit(self: Self) void {
            self.allocator.free(self.key);
        }
    };
}

fn IteratorLayer(comptime K: type, comptime V: type) type {
    return struct { start: K, node: *Trie(K, V) };
}

fn Iterator(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        stack: std.ArrayList(IteratorLayer(K, V)),

        pub fn next(self: *Self) Allocator.Error!?Entry(K, V) {
            while (self.stack.getLastOrNull()) |top| {
                for (top.start..top.node.children.len) |i| {
                    if (top.node.children[i]) |child| {
                        self.stack.items[self.stack.items.len - 1].start = @intCast(i + 1);
                        try self.stack.append(.{ .start = 0, .node = child });
                        if (nonzero(V, child.leaf)) {
                            const n = self.stack.items.len;
                            var s = try top.node.allocator.alloc(K, n - 1);
                            for (0..(n - 1)) |j| {
                                s[j] = self.stack.items[j].start - 1;
                            }
                            return .{
                                .key = s,
                                .value = child.leaf,
                                .node = child,
                                .allocator = top.node.allocator,
                            };
                        }
                        break;
                    }
                } else {
                    const root = self.stack.pop().?.node;
                    if (self.stack.items.len == 0 and nonzero(V, root.leaf)) {
                        return .{
                            .key = &[_]K{},
                            .value = root.leaf,
                            .node = root,
                            .allocator = root.allocator,
                        };
                    }
                }
            }
            self.stack.deinit();
            return null;
        }
    };
}

pub const Letter = u5;
pub const WordTrie = Trie(Letter, u32);

test "trie on string" {
    var trie = Trie(u8, u8).init(std.testing.allocator);
    defer trie.deinit();
    const words = [_][]const u8{ "a", "to", "tea", "ted", "ten", "i", "in", "inn" };
    for (words) |word| {
        const branch = try trie.get(word);
        branch.leaf += 1;
    }
    for (words) |word| {
        try std.testing.expectEqual(1, (try trie.get(word)).leaf);
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
