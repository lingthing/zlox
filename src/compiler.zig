const std = @import("std");
const utils = @import("utils.zig");
const debug = @import("debug.zig");
const zloc = @import("zloc.zig");
const VM = zloc.VM;
const Scanner = zloc.Scanner;
const Token = zloc.Token;
const TokenType = zloc.TokenType;
const Chunk = zloc.Chunk;
const OpCode = zloc.OpCode;
const Value = zloc.Value;

pub const Compiler = struct {
    vm: *VM,
    scanner: Scanner,
    parser: Parser,
    compiling_chunk: *Chunk,

    locals: [std.math.maxInt(u8) + 1]Local,
    local_count: usize,
    scope_depth: usize,

    pub fn init(vm: *VM) Compiler {
        const compiler = Compiler{
            .vm = vm,
            .scanner = undefined,
            .parser = undefined,
            .compiling_chunk = undefined,

            .locals = undefined,
            .local_count = 0,
            .scope_depth = 0,
        };
        return compiler;
    }

    pub fn compile(compiler: *Compiler, source: []const u8, chunk: *Chunk) bool {
        compiler.scanner = Scanner.init(source);
        compiler.compiling_chunk = chunk;
        compiler.parser.had_error = false;
        compiler.parser.panic_mode = false;

        compiler.advance();
        while (!compiler.match(.token_eof)) {
            compiler.declaration();
        }
        compiler.endCompiler();

        return !compiler.parser.had_error;
    }

    fn advance(compiler: *Compiler) void {
        compiler.parser.previous = compiler.parser.current;

        while (true) {
            compiler.parser.current = compiler.scanner.scanToken();
            if (compiler.parser.current.type != .token_error) break;

            compiler.errorAtCurrent(compiler.parser.current.start[0..compiler.parser.current.length]);
        }
    }

    fn consume(compiler: *Compiler, token_type: TokenType, message: []const u8) void {
        if (compiler.parser.current.type == token_type) {
            compiler.advance();
            return;
        }

        compiler.errorAtCurrent(message);
    }

    fn check(compiler: *Compiler, token_type: TokenType) bool {
        return compiler.parser.current.type == token_type;
    }

    fn match(compiler: *Compiler, token_type: TokenType) bool {
        if (!compiler.check(token_type)) return false;
        compiler.advance();

        return true;
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
            if (!compiler.parser.had_error) {
                debug.disassembleChunk(compiler.currentChunk(), "code");
            }
        }
    }

    fn beginScope(compiler: *Compiler) void {
        compiler.scope_depth += 1;
    }

    fn endScope(compiler: *Compiler) void {
        compiler.scope_depth -= 1;
        while (compiler.local_count > 0 and
            compiler.locals[compiler.local_count - 1].depth > compiler.scope_depth)
        {
            compiler.emitByte(OpCode.op_pop.u8());
            compiler.local_count -= 1;
        }
    }

    fn binary(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
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

    fn literal(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        switch (compiler.parser.previous.type) {
            .token_nil => compiler.emitByte(OpCode.op_nil.u8()),
            .token_true => compiler.emitByte(OpCode.op_true.u8()),
            .token_false => compiler.emitByte(OpCode.op_false.u8()),

            else => unreachable,
        }
    }

    fn grouping(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        compiler.expression();
        compiler.consume(.token_right_paren, "Expect ')' after expression.");
    }

    fn number(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const value = std.fmt.parseFloat(
            f64,
            compiler.parser.previous.start[0..compiler.parser.previous.length],
        ) catch unreachable;
        compiler.emitConstant(Value.initNumber(value));
    }

    fn string(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const value = zloc.copyString(
            compiler.vm,
            compiler.parser.previous.start[1 .. compiler.parser.previous.length - 1],
        );
        compiler.emitConstant(Value.initObj(value.?));
    }

    fn namedVariable(compiler: *Compiler, name: Token, can_assign: bool) void {
        var mut_name = name;
        var get_op: u8 = undefined;
        var set_op: u8 = undefined;
        var arg = compiler.resolveLocal(&mut_name);
        if (arg != -1) {
            get_op = OpCode.op_get_local.u8();
            set_op = OpCode.op_set_local.u8();
        } else {
            arg = compiler.identifierConstant(&mut_name);
            get_op = OpCode.op_get_global.u8();
            set_op = OpCode.op_set_global.u8();
        }

        if (can_assign and compiler.match(.token_equal)) {
            compiler.expression();
            compiler.emitBytes(set_op, @as(u8, @intCast(arg)));
        } else {
            compiler.emitBytes(get_op, @as(u8, @intCast(arg)));
        }
    }

    fn variable(compiler: *Compiler, can_assign: bool) void {
        compiler.namedVariable(compiler.parser.previous, can_assign);
    }

    fn unary(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
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

        const can_assign = @intFromEnum(precedence) <= @intFromEnum(Precedence.prec_assignment);
        prefixRule(compiler, can_assign);
        while (@intFromEnum(precedence) <= @intFromEnum(getRule(compiler.parser.current.type).precedence)) {
            compiler.advance();
            const infixRule: ParseFn = getRule(compiler.parser.previous.type).infix orelse unreachable;
            infixRule(compiler, can_assign);
        }

        if (can_assign and compiler.match(.token_equal)) {
            compiler.@"error"("Invalid assignment target.");
        }
    }

    fn identifierConstant(compiler: *Compiler, name: *Token) u8 {
        const value = zloc.copyString(compiler.vm, name.start[0..name.length]);

        return compiler.makeConstant(Value.initObj(value.?));
    }

    fn resolveLocal(compiler: *Compiler, name: *Token) isize {
        var i = compiler.local_count;
        while (i > 0) {
            i -= 1;
            const local = &compiler.locals[i];
            if (name.eql(&local.name)) {
                if (local.depth == -1) {
                    compiler.@"error"("Can't read local variable in its own initializer.");
                }

                return @intCast(i);
            }
        }

        return -1;
    }

    fn addLocal(compiler: *Compiler, name: Token) void {
        if (compiler.local_count == compiler.locals.len) {
            compiler.@"error"("Too many local variables in function.");
            return;
        }

        const local = &compiler.locals[compiler.local_count];
        compiler.local_count += 1;

        local.name = name;
        local.depth = -1; // -1 represent variable uninitialized
    }

    fn declareVariable(compiler: *Compiler) void {
        if (compiler.scope_depth == 0) return;

        const name = &compiler.parser.previous;
        var i = compiler.local_count;
        while (i > 0) {
            i -= 1;
            const local = &compiler.locals[i];
            if (local.depth != -1 and local.depth < compiler.scope_depth) {
                break;
            }

            if (name.eql(&local.name)) {
                compiler.@"error"("Already a variable with this name in this scope.");
            }
        }

        compiler.addLocal(name.*);
    }

    fn parseVariable(compiler: *Compiler, error_message: []const u8) u8 {
        compiler.consume(.token_identifier, error_message);

        compiler.declareVariable();
        if (compiler.scope_depth > 0) {
            return 0;
        }

        return compiler.identifierConstant(&compiler.parser.previous);
    }

    fn markInitialized(compiler: *Compiler) void {
        if (compiler.scope_depth == 0) return;
        compiler.locals[compiler.local_count - 1].depth = @intCast(compiler.scope_depth);
    }

    fn defineVariable(compiler: *Compiler, global: u8) void {
        if (compiler.scope_depth > 0) {
            compiler.markInitialized();
            return;
        }

        compiler.emitBytes(OpCode.op_define_global.u8(), global);
    }

    fn expression(compiler: *Compiler) void {
        compiler.parsePrecedence(.prec_assignment);
    }

    fn block(compiler: *Compiler) void {
        while (!compiler.check(.token_right_brace) and !compiler.check(.token_eof)) {
            compiler.declaration();
        }

        compiler.consume(.token_right_brace, "Expect '}' after block.");
    }

    fn printStatement(compiler: *Compiler) void {
        compiler.expression();
        compiler.consume(.token_semicolon, "Expect ';' after value.");
        compiler.emitByte(OpCode.op_print.u8());
    }

    fn expressionStatement(compiler: *Compiler) void {
        compiler.expression();
        compiler.consume(.token_semicolon, "Expect ';' after expression.");
        compiler.emitByte(OpCode.op_pop.u8());
    }

    fn varDeclaration(compiler: *Compiler) void {
        const global: u8 = compiler.parseVariable("Expect variable name.");

        if (compiler.match(.token_equal)) {
            compiler.expression();
        } else {
            compiler.emitByte(OpCode.op_nil.u8());
        }

        compiler.consume(.token_semicolon, "Expect ';' after variable declaration.");
        compiler.defineVariable(global);
    }

    fn synchronize(compiler: *Compiler) void {
        compiler.parser.panic_mode = false;

        while (compiler.parser.current.type != .token_eof) {
            if (compiler.parser.previous.type == .token_semicolon) return;

            switch (compiler.parser.current.type) {
                .token_class,
                .token_fun,
                .token_var,
                .token_for,
                .token_if,
                .token_while,
                .token_print,
                .token_return,
                => return,

                else => {
                    // Do nothing
                },
            }

            compiler.advance();
        }
    }

    fn declaration(compiler: *Compiler) void {
        if (compiler.match(.token_var)) {
            compiler.varDeclaration();
        } else {
            compiler.statement();
        }

        if (compiler.parser.panic_mode) compiler.synchronize();
    }

    fn statement(compiler: *Compiler) void {
        if (compiler.match(.token_print)) {
            compiler.printStatement();
        } else if (compiler.match(.token_left_brace)) {
            compiler.beginScope();
            compiler.block();
            compiler.endScope();
        } else {
            compiler.expressionStatement();
        }
    }

    fn currentChunk(compiler: *Compiler) *Chunk {
        return compiler.compiling_chunk;
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
        compiler.parser.had_error = true;
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
    had_error: bool,
    panic_mode: bool,
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

const ParseFn = *const fn (*Compiler, bool) void;

const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,
};

const Local = struct {
    name: Token,
    depth: isize,
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
        .prefix = Compiler.variable,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_string.u8()] = .{
        .prefix = Compiler.string,
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

fn getRule(token_type: TokenType) *const ParseRule {
    return &rules[token_type.u8()];
}
