const std = @import("std");

pub fn getStdoutWriter() std.fs.File.Writer {
    return std.io.getStdOut().writer();
}
