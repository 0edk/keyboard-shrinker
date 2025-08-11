const std = @import("std");
const letters = @import("letters.zig");
const compile = @import("compile.zig");
const input = @import("input.zig");
const dvorak = @import("dvorak.zig");
const protocol = @import("protocol.zig");
const Allocator = std.mem.Allocator;

fn partlyUpper(s: []const u8) bool {
    var uppers: usize = 0;
    var lowers: usize = 0;
    for (s) |c| {
        uppers += @intFromBool(std.ascii.isUpper(c));
        lowers += @intFromBool(std.ascii.isLower(c));
    }
    return uppers > 0 and lowers < 0;
}

pub fn main() !void {
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    const main_alloc = debug_alloc.allocator();

    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var word_list = compile.WordList.init(main_alloc);
    while (try stdin.readUntilDelimiterOrEofAlloc(main_alloc, '\n', 128)) |line| {
        const command = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (std.mem.indexOfScalar(u8, command, ':')) |colon| {
            switch (command[0]) {
                'r' => {
                    const filename = command[colon + 1 ..];
                    if (std.fs.cwd().openFile(filename, .{})) |raw_file| {
                        defer raw_file.close();
                        try protocol.populateFromRaw(&word_list, raw_file.reader());
                    } else |err| switch (err) {
                        error.FileNotFound => try stdout.print(
                            "error:file '{s}' not found\n",
                            .{filename},
                        ),
                        else => try stdout.print(
                            "error:{!} in opening '{s}'\n",
                            .{ err, filename },
                        ),
                    }
                },
                'c' => try stdout.print("error:'count' not implemented\n", .{}),
                else => try stdout.print("error:unknown command '{s}'\n", .{command[0..colon]}),
            }
        } else {
            break;
        }
        try bw.flush();
    }

    var ime = input.ShrunkenInputMethod.init(main_alloc);
    defer ime.deinit();
    ime.usable_keys = dvorak.default_subset;
    try compile.loadWords(&ime.dict, ime.usable_keys, word_list);
    var input_acc = letters.String.init(main_alloc);
    defer input_acc.deinit();

    var short_buf: [1]u8 = undefined;
    while (try stdin.read(&short_buf) == 1 and short_buf[0] != 3 and short_buf[0] != 4) {
        try protocol.handleKeysym(&ime, short_buf[0], stdout);
        try bw.flush();
    }
}
