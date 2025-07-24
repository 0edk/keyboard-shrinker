const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Trie(comptime K: type, comptime V: type) type {
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

        pub fn show(self: *const Self, writer: anytype, depth: usize) !void {
            var it = self.children.iterator();
            while (it.next()) |child| {
                try writer.writeByteNTimes(' ', 2 * depth);
                try writer.print("{c}{s}\n", .{ child.key_ptr.*, if (child.value_ptr.leaf != 0) "$" else "" });
                try child.value_ptr.show(writer, depth + 1);
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
    const word_list_filename = "dicts/google_100";
    const word_list_file = try std.fs.cwd().openFile(word_list_filename, .{});
    const wlr = word_list_file.reader();
    var dict_trie = Trie(u8, u32).init(main_alloc);
    defer dict_trie.deinit();
    var i: u32 = 0;
    while (wlr.readUntilDelimiterAlloc(main_alloc, '\n', 128)) |line| {
        i += 1;
        (try dict_trie.get(line)).leaf = 1000 / i;
    } else |err| {
        if (err != error.EndOfStream) {
            std.debug.print("error: {!}\n", .{err});
        }
    }
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try dict_trie.show(stdout, 0);
    try bw.flush();
}

test "trie on string" {
    var trie = Trie(u8, u32).init(std.testing.allocator);
    defer trie.deinit();
    const words = [_][]const u8{ "a", "to", "tea", "ted", "ten", "i", "in", "inn" };
    for (words) |word| {
        const branch = try trie.get(word);
        branch.leaf += 1;
    }
    for (words) |word| {
        try std.testing.expectEqual(1, (try trie.get(word)).leaf);
    }
}
