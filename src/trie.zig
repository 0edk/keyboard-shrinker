const std = @import("std");
const letters = @import("letters.zig");
const Allocator = std.mem.Allocator;

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
        leaf: ?V = null,
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
                .optional => if (leaf) |l| Self.deinitLf({}, l),
                .@"struct" => if (@hasDecl(V, "deinit")) {
                    leaf.deinit();
                },
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

        pub fn deepForEach(
            self: *Self,
            context: anytype,
            bf: ?fn (@TypeOf(context), *Self) void,
            lf: ?fn (@TypeOf(context), V) void,
        ) void {
            for (self.children) |maybe_child| {
                if (maybe_child) |child| {
                    child.deepForEach(context, bf, lf);
                    if (bf) |f| {
                        f(context, child);
                    }
                }
            }
            if (lf) |f| {
                if (self.leaf) |l| {
                    f(context, l);
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

pub fn IteratorLayer(comptime K: type, comptime V: type) type {
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
                        if (child.leaf) |l| {
                            const n = self.stack.items.len;
                            var s = try top.node.allocator.alloc(K, n - 1);
                            for (0..(n - 1)) |j| {
                                s[j] = self.stack.items[j].start - 1;
                            }
                            return .{
                                .key = s,
                                .value = l,
                                .node = child,
                                .allocator = top.node.allocator,
                            };
                        }
                        break;
                    }
                } else {
                    const root = self.stack.pop().?.node;
                    if (self.stack.items.len == 0) {
                        if (root.leaf) |l| {
                            return .{
                                .key = &[_]K{},
                                .value = l,
                                .node = root,
                                .allocator = root.allocator,
                            };
                        }
                    }
                }
            }
            self.stack.deinit();
            return null;
        }
    };
}

pub const WordTrie = Trie(letters.Letter, u32);

test "trie on string" {
    var trie = Trie(u8, u8).init(std.testing.allocator);
    defer trie.deinit();
    const words = [_][]const u8{ "a", "to", "tea", "ted", "ten", "i", "in", "inn" };
    for (words) |word| {
        const branch = try trie.get(word);
        branch.leaf = 1;
    }
    for (words) |word| {
        try std.testing.expectEqual(1, (try trie.get(word)).leaf);
    }
    try trie.show(void, 0);
}
