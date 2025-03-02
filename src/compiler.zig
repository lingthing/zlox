const utils = @import("utils.zig");
const zloc = @import("zloc.zig");
const Scanner = zloc.Scanner;

pub const Compiler = struct {
    pub fn init() Compiler {
        return .{};
    }

    pub fn compile(self: *Compiler, source: []const u8) void {
        _ = self;
        const stdout = utils.getStdoutWriter();
        var scanner = Scanner.init(source);
        var line: u32 = 0;
        while (true) {
            const token = scanner.scanToken();
            if (token.line != line) {
                stdout.print("{d:<4} ", .{token.line}) catch unreachable;
                line = token.line;
            } else {
                stdout.print("{c:<4} ", .{'|'}) catch unreachable;
            }
            stdout.print("{s:<19} '{s}'\n", .{ token.type.toString(), token.start[0..token.length] }) catch unreachable;

            if (token.type == .token_eof) break;
        }
    }
};
