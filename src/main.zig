const std = @import("std");
const Allocator = std.mem.Allocator;

fn Trie(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        leaf: V = 0,
        children: std.AutoHashMap(K, Self),
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .children = std.AutoHashMap(K, Self).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var vit = self.children.valueIterator();
            while (vit.next()) |child| {
                child.deinit();
            }
            var kit = self.children.keyIterator();
            while (kit.next()) |child| {
                std.debug.assert(self.children.remove(child.*));
            }
            self.children.deinit();
        }

        pub fn get(self: *Self, key: []const K) Allocator.Error!*Self {
            if (key.len == 0) {
                return self;
            } else {
                if (self.children.getPtr(key[0])) |child| {
                    return child.get(key[1..]);
                } else {
                    var child = Self.init(self.allocator);
                    errdefer child.deinit();
                    try self.children.put(key[0], child);
                    return self.children.getPtr(key[0]).?.get(key[1..]);
                }
            }
        }
    };
}

const alphabet = "abcdefghijklmnopqrstuvwxyz";

pub fn main() !void {
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    var arena = std.heap.ArenaAllocator.init(debug_alloc.allocator());
    defer arena.deinit();
    const main_alloc = arena.allocator();
    //const word_list = "dicts/google_100";
    const dict_trie = Trie(u8, u32).init(main_alloc);
    defer dict_trie.deinit();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("Run `zig build test` to run the tests.\n", .{});
    try bw.flush();
}

test "trie on string" {
    var trie = Trie(u8, u32).init(std.testing.allocator);
    defer trie.deinit();
    const words = [_][]const u8{"a", "to", "tea", "ted", "ten", "i", "in", "inn"};
    for (words) |word| {
        const branch = try trie.get(word);
        branch.leaf += 1;
    }
    for (words) |word| {
        try std.testing.expectEqual(1, (try trie.get(word)).leaf);
    }
}
