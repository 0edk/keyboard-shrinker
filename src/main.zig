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
            return Self{ .allocator = allocator, };
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

const Letter = u5;

fn charsToLetters(allocator: Allocator, str: []const u8) Allocator.Error!std.ArrayList(Letter) {
    var projected = std.ArrayList(Letter).init(allocator);
    for (str) |c| {
        if (std.ascii.isAlphabetic(c)) {
            try projected.append(@intCast(std.ascii.toLower(c) - 'a'));
        }
    }
    return projected;
}

fn lettersToChars(allocator: Allocator, letters: []const Letter) Allocator.Error!std.ArrayList(Letter) {
    var s = String.initCapacity(allocator, letters.len);
    for (letters) |l| {
        s.append(l + 'a');
    }
    return s;
}

const WordTrie = Trie(Letter, u32);

// TODO
pub fn expandInput(subset: []const Letter, trie: WordTrie, query: []Letter) Allocator.Error!void {
    _ = subset;
    _ = trie;
    _ = query;
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
        (try dict_trie.get((try charsToLetters(main_alloc, line)).items)).leaf = 1000 / i;
    }
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();
    while (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var it = try expandInput("etao", dict_trie, line);
        while (try it.next()) |match| {
            try stdout.print("{s}\n", .{match});
            try bw.flush();
        }
    }
}

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
