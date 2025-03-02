const std = @import("std");

pub fn getStdoutWriter() std.fs.File.Writer {
    return std.io.getStdOut().writer();
}

pub fn getStderrWriter() std.fs.File.Writer {
    return std.io.getStdErr().writer();
}
