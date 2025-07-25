const std = @import("std");
const Allocator = std.mem.Allocator;
const String = std.ArrayList(u8);

pub fn Trie(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        leaf: V = 0,
        children: std.AutoHashMap(K, *Self),
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .children = std.AutoHashMap(K, *Self).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var vit = self.children.valueIterator();
            while (vit.next()) |child| {
                child.*.deinit();
                self.allocator.destroy(child.*);
            }
            self.children.deinit();
        }

        pub fn get(self: *Self, key: []const K) Allocator.Error!*Self {
            if (key.len == 0) {
                return self;
            } else {
                if (self.children.get(key[0])) |child| {
                    return child.get(key[1..]);
                } else {
                    const child = try self.allocator.create(Self);
                    child.* = Self.init(self.allocator);
                    try self.children.put(key[0], child);
                    return self.children.get(key[0]).?.get(key[1..]);
                }
            }
        }

        pub fn show(self: *const Self, writer: anytype, depth: usize) !void {
            var it = self.children.iterator();
            while (it.next()) |child| {
                try writer.writeByteNTimes(' ', 2 * depth);
                try writer.print("{c}{s}\n", .{ child.key_ptr.*, if (child.value_ptr.*.leaf != 0) "$" else "" });
                try child.value_ptr.*.show(writer, depth + 1);
            }
        }
    };
}

const WordTrie = Trie(u8, u32);

const MatchIterator = struct {
    root: WordTrie,
    branch_iters: std.ArrayList(std.AutoHashMap(u8, *WordTrie).Iterator),
    subset: []const u8,
    query: []u8,
    index: usize = 0,
    prefix: String,

    // very broken
    fn next(self: *MatchIterator) Allocator.Error!?[]const u8 {
        if (self.branch_iters.pop()) |it_old| {
            var it = it_old;
            if (it.next()) |n| {
                std.debug.print("n is of type {any}\n", .{@TypeOf(n)});
                const letter = n.key_ptr.*;
                const child = n.value_ptr.*;
                std.debug.print("found child '{u}': {any}\n", .{ letter, child });
                if (self.query.len > self.index and letter == self.query[self.index]) {
                    std.debug.print("which matches query at {d}\n", .{self.index});
                    self.index += 1;
                    try self.prefix.append(letter);
                    try self.branch_iters.append(it);
                    try self.branch_iters.append(child.children.iterator());
                    return if (child.leaf > 0) self.prefix.items else self.next();
                } else {
                    for (self.subset) |c| {
                        if (letter == c) {
                            std.debug.print("which is in subset\n", .{});
                            try self.branch_iters.append(it);
                            return self.next();
                        }
                    } else {
                        std.debug.print("which is outside subset\n", .{});
                        try self.prefix.append(letter);
                        try self.branch_iters.append(it);
                        try self.branch_iters.append(child.children.iterator());
                        return if (child.leaf > 0) self.prefix.items else self.next();
                    }
                }
            }
            std.debug.print("out of children\n", .{});
            _ = self.prefix.pop();
            return self.next();
        }
        std.debug.print("done with root\n", .{});
        return null;
    }
};

pub fn expandInput(subset: []const u8, trie: WordTrie, query: []u8) Allocator.Error!MatchIterator {
    const alloc = trie.allocator;
    var branches = std.ArrayList(std.AutoHashMap(u8, *WordTrie).Iterator).init(alloc);
    try branches.append(trie.children.iterator());
    return MatchIterator{
        .root = trie,
        .branch_iters = branches,
        .subset = subset,
        .query = query,
        .prefix = String.init(alloc),
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
    var dict_trie = WordTrie.init(main_alloc);
    defer dict_trie.deinit();
    var i: u32 = 0;
    var buf: [128]u8 = undefined;
    while (try wlr.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        i += 1;
        (try dict_trie.get(line)).leaf = 1000 / i;
    }
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();
    try dict_trie.show(stdout, 0);
    try bw.flush();
    while (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var it = try expandInput("etao", dict_trie, line);
        _ = &it;
        //while (try it.next()) |match| {
        //    try stdout.print("{s}\n", .{match});
        //    try bw.flush();
        //}
    }
}

test "trie on string" {
    var trie = WordTrie.init(std.testing.allocator);
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
