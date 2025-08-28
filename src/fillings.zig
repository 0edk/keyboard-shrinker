const std = @import("std");
const letters = @import("letters.zig");
const compile = @import("compile.zig");
const Allocator = std.mem.Allocator;

const Completion = struct { node: *compile.CompiledTrie, suffix: []const letters.Letter };

fn compareCompletion(_: void, a: Completion, b: Completion) std.math.Order {
    if (a.node.leaf) |al| {
        return if (b.node.leaf) |bl|
            std.math.order(bl.items[0].weight, al.items[0].weight)
        else
            .lt;
    } else {
        return if (b.node.leaf != null) .gt else .eq;
    }
}

pub const Completer = struct {
    const Self = @This();
    completions: std.ArrayList(Completion),
    choice: ?struct { usize, usize },
    slid: bool = false,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .completions = std.ArrayList(Completion).init(allocator),
            .choice = null,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.completions.items) |comp| {
            self.completions.allocator.free(comp.suffix);
        }
        self.completions.deinit();
    }

    pub fn start(
        self: *Self,
        query: []const letters.Letter,
        node: *compile.CompiledTrie,
    ) Allocator.Error!void {
        self.choice = if (query.len == 0) null else .{ 0, 0 };
        try self.completions.append(.{ .node = node, .suffix = &[0]letters.Letter{} });
        while (try self.adjustChoice()) {}
    }

    pub fn getCompletionClass(self: *const Self) ?Completion {
        if (self.choice) |inds| {
            return self.completions.items[inds[0]];
        } else {
            return null;
        }
    }

    pub fn getCompletion(self: *const Self) ?[]const u8 {
        if (self.choice) |inds| {
            return self.getCompletionClass().?.node.leaf.?.items[inds[1]].word;
        } else {
            return null;
        }
    }

    fn adjustChoice(self: *Self) Allocator.Error!bool {
        if (self.choice) |inds| {
            if (inds[0] >= self.completions.items.len) {
                if (try self.extend()) {
                    return true;
                } else {
                    self.choice = null;
                    return false;
                }
            } else if (self.completions.items[inds[0]].node.leaf) |words| {
                if (inds[1] >= words.items.len) {
                    self.choice = .{ inds[0] + 1, 0 };
                    return true;
                }
            } else {
                self.choice = .{ inds[0] + 1, 0 };
                return true;
            }
        }
        return false;
    }

    pub fn inferred(self: *const Self) ?[]const letters.Letter {
        if (self.slid) {
            if (self.choice) |inds| {
                return self.completions.items[inds[0]].suffix;
            }
        }
        return null;
    }

    fn extend(self: *Self) Allocator.Error!bool {
        if (self.completions.getLastOrNull()) |last| {
            const depth = last.suffix.len;
            var arena = std.heap.ArenaAllocator.init(self.completions.allocator);
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
                            var suffix = try self.completions.allocator.alloc(
                                letters.Letter,
                                depth + 1,
                            );
                            @memcpy(suffix[0..depth], comp.suffix);
                            suffix[depth] = @intCast(l);
                            try candidates.add(.{ .node = child, .suffix = suffix });
                        }
                    }
                }
            }
            var extended = false;
            while (candidates.removeOrNull()) |comp| {
                extended = true;
                try self.completions.append(comp);
            }
            return extended;
        }
        return false;
    }

    pub fn advance(self: *Self) Allocator.Error!void {
        if (self.choice == null) {
            self.choice = .{ 0, 0 };
        } else {
            self.choice.?[1] += 1;
        }
        while (try self.adjustChoice()) {}
        self.slid = true;
    }

    pub fn retreat(self: *Self) Allocator.Error!void {
        if (self.choice) |inds| {
            if (inds[1] == 0) {
                if (inds[0] == 0) {
                    self.choice = null;
                } else {
                    var new_ind = inds[0] - 1;
                    while (new_ind > 0) {
                        if (self.completions.items[new_ind].node.leaf) |words| {
                            if (words.items.len > 0) {
                                self.choice = .{ new_ind, words.items.len - 1 };
                                break;
                            }
                        }
                        new_ind -= 1;
                    } else {
                        self.choice = null;
                    }
                }
            } else {
                self.choice = .{ inds[0], inds[1] - 1 };
            }
        }
        self.slid = true;
    }

    pub fn deter(self: *Self) void {
        if (self.getCompletionClass()) |comp| {
            if (comp.node.leaf) |words| {
                std.debug.assert(words.items.len > 0);
                words.items[self.choice.?[1]].weight = 0;
                compile.sortLeaf({}, words);
            }
        }
    }
};
