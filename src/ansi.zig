const std = @import("std");

// https://ziggit.dev/t/how-to-read-arrow-key/7405
pub fn enableRawMode() !std.posix.termios {
    const original = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
    var raw = original;
    raw.iflag.IGNBRK = false;
    raw.iflag.BRKINT = false;
    raw.iflag.PARMRK = false;
    raw.iflag.INLCR = false;
    raw.iflag.IGNCR = false;
    raw.iflag.ICRNL = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.IXON = false;
    raw.oflag.OPOST = false;
    raw.lflag.ECHO = false;
    raw.lflag.ECHONL = false;
    raw.lflag.ICANON = false;
    raw.lflag.IEXTEN = false;
    raw.lflag.ISIG = false;
    raw.cflag.PARENB = false;
    raw.cflag.CSIZE = .CS8;
    //raw.c_cc[c.VMIN] = 1;
    //raw.c_cc[c.VTIME] = 0;
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);
    //std.process.cleanExit(disableRawMode);
    return original;
}

pub fn restoreTerminal(state: std.posix.termios) !void {
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, state);
}

pub fn moveTo(stdout: anytype, row: usize, col: usize) !void {
    return stdout.print("\x1b[{d};{d}H", .{ row, col });
}
