const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const version = @import("version.zig");
const debug = @import("debug.zig");
const zloc = @import("zloc.zig");
const Chunk = zloc.Chunk;
const OpCode = zloc.OpCode;
const VM = zloc.VM;
const gpa = @import("common_allocator.zig").gpa;

fn repl() void {
    var buf: [1024]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var vm = VM.init(gpa);
    defer vm.deinit();

    while (true) {
        stdout.print("> ", .{}) catch unreachable;

        var line = stdin.readUntilDelimiter(&buf, '\n') catch |err| switch (err) {
            error.StreamTooLong => {
                stderr.print("Line too long\n", .{}) catch unreachable;
                continue;
            },
            error.EndOfStream => {
                break;
            },
            else => {
                stderr.print("Unexpected error: {!}\n", .{err}) catch unreachable;
                std.process.exit(1);
            },
        };

        if (line.len > 0 and line[line.len - 1] == '\r') {
            line[line.len - 1] = 0;
            line = line[0 .. line.len - 1];
        }
        if (line.len == 0) continue;

        if (mem.eql(u8, line, "quit")) {
            break;
        } else if (mem.eql(u8, line, "clear")) {
            stdout.print("\x1b[H\x1b[2J", .{}) catch unreachable;
            continue;
        }

        _ = vm.interpret(line);
    }
}

fn runFile(path: []const u8) void {
    const source = readFile(path);
    defer gpa.free(source);

    var vm = VM.init(gpa);
    defer vm.deinit();
    switch (vm.interpret(source)) {
        .ok => {},
        .compile_error => {
            std.process.exit(65);
        },
        .runtime_error => {
            std.process.exit(70);
        },
    }
}

fn readFile(path: []const u8) []u8 {
    const stderr = std.io.getStdErr().writer();

    var file = fs.cwd().openFile(path, .{ .mode = .read_only }) catch {
        stderr.print("Could not open file \"{s}\".\n", .{path}) catch unreachable;
        std.process.exit(74);
    };
    defer file.close();

    file.seekFromEnd(0) catch unreachable;
    const filesize = file.getEndPos() catch unreachable;

    const buf = gpa.alloc(u8, filesize) catch {
        stderr.print("Not enough memory to read \"{s}\".\n", .{path}) catch unreachable;
        std.process.exit(74);
    };
    file.seekTo(0) catch unreachable;
    _ = file.readAll(buf) catch {
        stderr.print("Could not read file \"{s}\".\n", .{path}) catch unreachable;
        std.process.exit(74);
    };

    return buf;
}

pub fn main() !void {
    defer @import("common_allocator.zig").deinit();

    const argv = try std.process.argsAlloc(gpa);
    const argc = argv.len;
    defer std.process.argsFree(gpa, argv);

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    if (argc == 1) {
        repl();
    } else if (argc == 2) {
        if (mem.eql(u8, argv[1], "--help")) {
            stdout.print("Usage: zloc <file>\n", .{}) catch unreachable;
        } else if (mem.eql(u8, argv[1], "--version")) {
            stdout.print("{s}\n", .{version.VERSION}) catch unreachable;
        } else {
            runFile(argv[1]);
        }
    } else {
        stderr.print("Usage: zloc <file>\n", .{}) catch unreachable;
    }
}
