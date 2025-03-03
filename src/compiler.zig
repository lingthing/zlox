const std = @import("std");
const utils = @import("utils.zig");
const debug = @import("debug.zig");
const zloc = @import("zloc.zig");
const Scanner = zloc.Scanner;
const Token = zloc.Token;
const TokenType = zloc.TokenType;
const Chunk = zloc.Chunk;
const OpCode = zloc.OpCode;
const Value = zloc.Value;

pub const Compiler = struct {
    scanner: Scanner,
    parser: Parser,
    compilingChunk: *Chunk,

    pub fn init() Compiler {
        return undefined;
    }

    pub fn compile(compiler: *Compiler, source: []const u8, chunk: *Chunk) bool {
        compiler.scanner = Scanner.init(source);
        compiler.compilingChunk = chunk;
        compiler.parser.hadError = false;
        compiler.parser.panicMode = false;

        compiler.advance();
        compiler.expression();
        compiler.consume(.token_eof, "Expect end of expression.");
        compiler.endCompiler();

        return !compiler.parser.hadError;
    }

    fn advance(compiler: *Compiler) void {
        compiler.parser.previous = compiler.parser.current;

        while (true) {
            compiler.parser.current = compiler.scanner.scanToken();
            if (compiler.parser.current.type != .token_error) break;

            compiler.errorAtCurrent(compiler.parser.current.start[0..compiler.parser.current.length]);
        }
    }

    fn consume(compiler: *Compiler, tokenType: TokenType, message: []const u8) void {
        if (compiler.parser.current.type == tokenType) {
            compiler.advance();
            return;
        }

        compiler.errorAtCurrent(message);
    }

    fn emitByte(compiler: *Compiler, byte: u8) void {
        compiler.currentChunk().write(byte, compiler.parser.previous.line);
    }

    fn emitBytes(compiler: *Compiler, byte1: u8, byte2: u8) void {
        compiler.emitByte(byte1);
        compiler.emitByte(byte2);
    }

    fn emitReturn(compiler: *Compiler) void {
        compiler.emitByte(OpCode.op_return.u8());
    }

    fn makeConstant(compiler: *Compiler, value: Value) u8 {
        const constant = compiler.currentChunk().addConstant(value);
        if (constant > std.math.maxInt(u8)) {
            compiler.@"error"("Too many constants in one chunk.");
            return 0;
        }

        return @as(u8, @intCast(constant));
    }

    fn emitConstant(compiler: *Compiler, value: Value) void {
        compiler.emitBytes(OpCode.op_constant.u8(), compiler.makeConstant(value));
    }

    fn endCompiler(compiler: *Compiler) void {
        compiler.emitReturn();

        if (debug.DEBUG_PRINT_CODE) {
            if (!compiler.parser.hadError) {
                debug.disassembleChunk(compiler.currentChunk(), "code");
            }
        }
    }

    fn binary(compiler: *Compiler) void {
        const operatorType = compiler.parser.previous.type;
        const rule = getRule(operatorType);
        compiler.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

        switch (operatorType) {
            .token_bang_equal => compiler.emitBytes(OpCode.op_equal.u8(), OpCode.op_not.u8()),
            .token_equal_equal => compiler.emitByte(OpCode.op_equal.u8()),
            .token_greater => compiler.emitByte(OpCode.op_greater.u8()),
            .token_greater_equal => compiler.emitBytes(OpCode.op_less.u8(), OpCode.op_not.u8()),
            .token_less => compiler.emitByte(OpCode.op_less.u8()),
            .token_less_equal => compiler.emitBytes(OpCode.op_greater.u8(), OpCode.op_not.u8()),

            .token_plus => compiler.emitByte(OpCode.op_add.u8()),
            .token_minus => compiler.emitByte(OpCode.op_subtract.u8()),
            .token_star => compiler.emitByte(OpCode.op_multiply.u8()),
            .token_slash => compiler.emitByte(OpCode.op_divide.u8()),

            else => unreachable,
        }
    }

    fn literal(compiler: *Compiler) void {
        switch (compiler.parser.previous.type) {
            .token_nil => compiler.emitByte(OpCode.op_nil.u8()),
            .token_true => compiler.emitByte(OpCode.op_true.u8()),
            .token_false => compiler.emitByte(OpCode.op_false.u8()),

            else => unreachable,
        }
    }

    fn grouping(compiler: *Compiler) void {
        compiler.expression();
        compiler.consume(.token_right_paren, "Expect ')' after expression.");
    }

    fn number(compiler: *Compiler) void {
        const value = std.fmt.parseFloat(
            f64,
            compiler.parser.previous.start[0..compiler.parser.previous.length],
        ) catch unreachable;
        compiler.emitConstant(Value.initNumber(value));
    }

    fn unary(compiler: *Compiler) void {
        const operatorType = compiler.parser.previous.type;

        compiler.parsePrecedence(.prec_unary);

        switch (operatorType) {
            .token_bang => compiler.emitByte(OpCode.op_not.u8()),
            .token_minus => compiler.emitByte(OpCode.op_negate.u8()),

            else => unreachable,
        }
    }

    fn parsePrecedence(compiler: *Compiler, precedence: Precedence) void {
        compiler.advance();
        const prefixRule: ParseFn = getRule(compiler.parser.previous.type).prefix orelse {
            compiler.@"error"("Expect expression.");
            return;
        };

        prefixRule(compiler);
        while (@intFromEnum(precedence) <= @intFromEnum(getRule(compiler.parser.current.type).precedence)) {
            compiler.advance();
            const infixRule: ParseFn = getRule(compiler.parser.previous.type).infix orelse unreachable;
            infixRule(compiler);
        }
    }

    fn expression(compiler: *Compiler) void {
        compiler.parsePrecedence(.prec_assignment);
    }

    fn currentChunk(compiler: *Compiler) *Chunk {
        return compiler.compilingChunk;
    }

    fn errorAt(compiler: *Compiler, token: *Token, message: []const u8) void {
        const stderr = utils.getStderrWriter();
        stderr.print("[line {d}] Error", .{token.line}) catch unreachable;

        if (token.type == .token_eof) {
            stderr.print(" at end", .{}) catch unreachable;
        } else if (token.type == .token_error) {
            // Nothing.
        } else {
            stderr.print(" at '{s}'", .{token.start[0..token.length]}) catch unreachable;
        }

        stderr.print(": {s}\n", .{message}) catch unreachable;
        compiler.parser.hadError = true;
    }

    fn @"error"(compiler: *Compiler, message: []const u8) void {
        compiler.errorAt(&compiler.parser.previous, message);
    }

    fn errorAtCurrent(compiler: *Compiler, message: []const u8) void {
        compiler.errorAt(&compiler.parser.current, message);
    }
};

const Parser = struct {
    current: Token,
    previous: Token,
    hadError: bool,
    panicMode: bool,
};

const Precedence = enum {
    prec_none,
    prec_assignment, // =
    prec_or, // or
    prec_and, // and
    prec_equality, // == !=
    prec_comparison, // < > <= >=
    prec_term, // + -
    prec_factor, // * /
    prec_unary, // - !
    prec_call, // . ()
    prec_primary,
};

const ParseFn = *const fn (*Compiler) void;

const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,
};

const rules = blk: {
    var tmp: [@typeInfo(TokenType).Enum.fields.len]ParseRule = undefined;
    tmp[TokenType.token_left_paren.u8()] = .{
        .prefix = Compiler.grouping,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_right_paren.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_left_brace.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_right_brace.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_comma.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_dot.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_minus.u8()] = .{
        .prefix = Compiler.unary,
        .infix = Compiler.binary,
        .precedence = .prec_term,
    };
    tmp[TokenType.token_plus.u8()] = .{
        .prefix = null,
        .infix = Compiler.binary,
        .precedence = .prec_term,
    };
    tmp[TokenType.token_semicolon.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_slash.u8()] = .{
        .prefix = null,
        .infix = Compiler.binary,
        .precedence = .prec_factor,
    };
    tmp[TokenType.token_star.u8()] = .{
        .prefix = null,
        .infix = Compiler.binary,
        .precedence = .prec_factor,
    };
    tmp[TokenType.token_bang.u8()] = .{
        .prefix = Compiler.unary,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_bang_equal.u8()] = .{
        .prefix = null,
        .infix = Compiler.binary,
        .precedence = .prec_equality,
    };
    tmp[TokenType.token_equal.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_equal_equal.u8()] = .{
        .prefix = null,
        .infix = Compiler.binary,
        .precedence = .prec_comparison,
    };
    tmp[TokenType.token_greater.u8()] = .{
        .prefix = null,
        .infix = Compiler.binary,
        .precedence = .prec_comparison,
    };
    tmp[TokenType.token_greater_equal.u8()] = .{
        .prefix = null,
        .infix = Compiler.binary,
        .precedence = .prec_comparison,
    };
    tmp[TokenType.token_less.u8()] = .{
        .prefix = null,
        .infix = Compiler.binary,
        .precedence = .prec_comparison,
    };
    tmp[TokenType.token_less_equal.u8()] = .{
        .prefix = null,
        .infix = Compiler.binary,
        .precedence = .prec_comparison,
    };

    tmp[TokenType.token_identifier.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_string.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_number.u8()] = .{
        .prefix = Compiler.number,
        .infix = null,
        .precedence = .prec_none,
    };

    tmp[TokenType.token_and.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_class.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_else.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_false.u8()] = .{
        .prefix = Compiler.literal,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_for.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_fun.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_if.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_nil.u8()] = .{
        .prefix = Compiler.literal,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_or.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_print.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_return.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_super.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_this.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_true.u8()] = .{
        .prefix = Compiler.literal,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_var.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_while.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_error.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_eof.u8()] = .{
        .prefix = null,
        .infix = null,
        .precedence = .prec_none,
    };

    break :blk tmp;
};

fn getRule(tokenType: TokenType) *const ParseRule {
    return &rules[tokenType.u8()];
}
