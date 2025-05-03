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
const ObjFunction = zloc.ObjFunction;

pub const Compiler = struct {
    var scanner: Scanner = undefined;
    var parser: Parser = undefined;
    var scope_depth: usize = 0;
    pub var current: ?*Compiler = null;
    var current_class: ?*ClassCompiler = null;

    const ClassCompiler = struct {
        enclosing: ?*ClassCompiler,
        has_superclass: bool,
    };

    enclosing: ?*Compiler,
    vm: *VM,

    function: *ObjFunction,
    type: FunctionType,

    locals: [std.math.maxInt(u8) + 1]Local,
    local_count: usize,

    upvalues: [std.math.maxInt(u8) + 1]Upvalue,

    pub fn init(vm: *VM, function_type: FunctionType, enclosing: ?*Compiler) Compiler {
        var compiler = Compiler{
            .enclosing = enclosing,
            .vm = vm,

            .function = zloc.newFunction(vm).?,
            .type = function_type,

            .locals = undefined,
            .local_count = 0,

            .upvalues = undefined,
        };

        current = &compiler;

        if (function_type != .type_script) {
            compiler.function.name = zloc.copyString(
                vm,
                parser.previous.start[0..parser.previous.length],
            );
        }

        var local = &compiler.locals[0];
        compiler.local_count += 1;
        local.depth = 0;
        local.is_captured = false;
        if (function_type != .type_function) {
            local.name.start = "this";
            local.name.length = 4;
        } else {
            local.name.start = "";
            local.name.length = 0;
        }

        return compiler;
    }

    pub fn compile(compiler: *Compiler, source: []const u8) ?*ObjFunction {
        scanner = Scanner.init(source);
        parser.had_error = false;
        parser.panic_mode = false;

        compiler.advance();
        while (!compiler.match(.token_eof)) {
            compiler.declaration();
        }
        const function = compiler.endCompiler();

        if (parser.had_error) {
            return null;
        } else {
            return function;
        }
    }

    fn advance(compiler: *Compiler) void {
        parser.previous = parser.current;

        while (true) {
            parser.current = scanner.scanToken();
            if (parser.current.type != .token_error) break;

            compiler.errorAtCurrent(parser.current.start[0..parser.current.length]);
        }
    }

    fn consume(compiler: *Compiler, token_type: TokenType, message: []const u8) void {
        if (parser.current.type == token_type) {
            compiler.advance();
            return;
        }

        compiler.errorAtCurrent(message);
    }

    fn check(compiler: *Compiler, token_type: TokenType) bool {
        _ = compiler;

        return parser.current.type == token_type;
    }

    fn match(compiler: *Compiler, token_type: TokenType) bool {
        if (!compiler.check(token_type)) return false;
        compiler.advance();

        return true;
    }

    fn emitByte(compiler: *Compiler, byte: u8) void {
        compiler.currentChunk().write(byte, parser.previous.line);
    }

    fn emitBytes(compiler: *Compiler, byte1: u8, byte2: u8) void {
        compiler.emitByte(byte1);
        compiler.emitByte(byte2);
    }

    fn emitJump(compiler: *Compiler, instruction: u8) usize {
        compiler.emitByte(instruction);
        compiler.emitByte(0xff);
        compiler.emitByte(0xff);

        return compiler.currentChunk().count() - 2;
    }

    fn emitLoop(compiler: *Compiler, loop_start: usize) void {
        compiler.emitByte(OpCode.op_loop.u8());

        const offset = compiler.currentChunk().count() - loop_start + 2;
        if (offset > std.math.maxInt(u16)) {
            compiler.@"error"("Loop body too large.");
        }

        compiler.emitByte(@as(u8, @truncate(offset >> 8)));
        compiler.emitByte(@as(u8, @truncate(offset)));
    }

    fn emitReturn(compiler: *Compiler) void {
        if (compiler.type == .type_initializer) {
            compiler.emitByte(OpCode.op_get_local.u8());
            compiler.emitShort(0);
        } else {
            compiler.emitByte(OpCode.op_nil.u8());
        }
        compiler.emitByte(OpCode.op_return.u8());
    }

    fn makeConstant(compiler: *Compiler, value: Value) usize {
        const constant = compiler.currentChunk().addConstant(value, compiler.vm);
        if (constant > std.math.maxInt(u16)) {
            compiler.@"error"("Too many constants in one chunk.");
            return 0;
        }

        return constant;
    }

    fn emitConstant(compiler: *Compiler, value: Value) void {
        compiler.emitByte(OpCode.op_constant.u8());
        compiler.emitShort(compiler.makeConstant(value));
    }

    fn emitShort(compiler: *Compiler, num: usize) void {
        compiler.emitBytes(@truncate(num >> 8), @truncate(num));
    }

    fn patchJump(compiler: *Compiler, offset: usize) void {
        const jump = compiler.currentChunk().count() - offset - 2;
        if (jump > std.math.maxInt(u16)) {
            compiler.@"error"("Too much code to jump over.");
        }

        compiler.currentChunk().setByte(offset, @as(u8, @truncate(jump >> 8)));
        compiler.currentChunk().setByte(offset + 1, @as(u8, @truncate(jump)));
    }

    fn endCompiler(compiler: *Compiler) ?*ObjFunction {
        compiler.emitReturn();

        const function = compiler.function;

        if (debug.DEBUG_PRINT_CODE) {
            if (!parser.had_error) {
                debug.disassembleChunk(
                    compiler.currentChunk(),
                    if (function.name) |name| name.chars else "<script>",
                );
            }
        }

        Compiler.current = compiler.enclosing;

        return function;
    }

    fn beginScope(compiler: *Compiler) void {
        _ = compiler;

        scope_depth += 1;
    }

    fn endScope(compiler: *Compiler) void {
        scope_depth -= 1;
        while (compiler.local_count > 0 and
            compiler.locals[compiler.local_count - 1].depth > scope_depth)
        {
            if (compiler.locals[compiler.local_count - 1].is_captured) {
                compiler.emitByte(OpCode.op_close_upvalue.u8());
            } else {
                compiler.emitByte(OpCode.op_pop.u8());
            }
            compiler.local_count -= 1;
        }
    }

    fn binary(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const operatorType = parser.previous.type;
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

    fn argumentList(compiler: *Compiler) u8 {
        var arg_count: u8 = 0;
        if (!compiler.check(.token_right_paren)) {
            while (true) {
                compiler.expression();
                if (arg_count == 255) {
                    compiler.@"error"("Can't have more than 255 arguments.");
                }
                arg_count += 1;

                if (!compiler.match(.token_comma)) break;
            }
        }
        compiler.consume(.token_right_paren, "Expect ')' after arguments.");

        return arg_count;
    }

    fn call(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;

        const arg_count: u8 = compiler.argumentList();
        compiler.emitBytes(OpCode.op_call.u8(), @as(u8, @intCast(arg_count)));
    }

    fn dot(compiler: *Compiler, can_assign: bool) void {
        compiler.consume(.token_identifier, "Expect property name after '.'.");
        const name_constant = compiler.identifierConstant(&parser.previous);

        if (can_assign and compiler.match(.token_equal)) {
            compiler.expression();
            compiler.emitByte(OpCode.op_set_property.u8());
            compiler.emitShort(name_constant);
        } else if (compiler.match(.token_left_paren)) {
            const arg_count = compiler.argumentList();
            compiler.emitByte(OpCode.op_invoke.u8());
            compiler.emitShort(name_constant);
            compiler.emitByte(arg_count);
        } else {
            compiler.emitByte(OpCode.op_get_property.u8());
            compiler.emitShort(name_constant);
        }
    }

    fn literal(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        switch (parser.previous.type) {
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
            parser.previous.start[0..parser.previous.length],
        ) catch unreachable;
        compiler.emitConstant(Value.initNumber(value));
    }

    fn string(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const value = zloc.copyString(
            compiler.vm,
            parser.previous.start[1 .. parser.previous.length - 1],
        );
        compiler.emitConstant(Value.initObj(value.?));
    }

    fn namedVariable(compiler: *Compiler, name: Token, can_assign: bool) void {
        var mut_name = name;
        var get_op: u8 = undefined;
        var set_op: u8 = undefined;
        var arg: isize = compiler.resolveLocal(&mut_name);
        if (arg != -1) {
            get_op = OpCode.op_get_local.u8();
            set_op = OpCode.op_set_local.u8();
        } else {
            arg = compiler.resolveUpvalue(&mut_name);
            if (arg != -1) {
                get_op = OpCode.op_get_upvalue.u8();
                set_op = OpCode.op_set_upvalue.u8();
            } else {
                arg = @as(isize, @intCast(compiler.identifierConstant(&mut_name)));
                get_op = OpCode.op_get_global.u8();
                set_op = OpCode.op_set_global.u8();
            }
        }

        if (can_assign and compiler.match(.token_equal)) {
            compiler.expression();
            compiler.emitByte(set_op);
            // if (set_op == OpCode.op_set_global.u8()) {
            //     compiler.emitShort(@as(usize, @intCast(arg)));
            // } else {
            //     compiler.emitByte(@as(u8, @intCast(arg)));
            // }
            compiler.emitShort(@as(usize, @intCast(arg)));
        } else {
            compiler.emitByte(get_op);
            // if (set_op == OpCode.op_get_global.u8()) {
            //     compiler.emitShort(@as(usize, @intCast(arg)));
            // } else {
            //     compiler.emitByte(@as(u8, @intCast(arg)));
            // }
            compiler.emitShort(@as(usize, @intCast(arg)));
        }
    }

    fn variable(compiler: *Compiler, can_assign: bool) void {
        compiler.namedVariable(parser.previous, can_assign);
    }

    fn super(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        if (current_class == null) {
            compiler.@"error"("Can't use 'super' outside of a class.");
        } else if (!current_class.?.has_superclass) {
            compiler.@"error"("Can't use 'super' in a class with no superclass.");
        }

        compiler.consume(.token_dot, "Expect '.' after 'super'.");
        compiler.consume(.token_identifier, "Expect superclass method name.");
        const name_constant = compiler.identifierConstant(&parser.previous);
        compiler.namedVariable(syntheticToken("this"), false);
        if (compiler.match(.token_left_paren)) {
            const arg_count = compiler.argumentList();
            compiler.namedVariable(syntheticToken("super"), false);
            compiler.emitByte(OpCode.op_super_invoke.u8());
            compiler.emitShort(name_constant);
            compiler.emitByte(arg_count);
        } else {
            compiler.namedVariable(syntheticToken("super"), false);
            compiler.emitByte(OpCode.op_get_super.u8());
            compiler.emitShort(name_constant);
        }
    }

    fn this(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        if (current_class == null) {
            compiler.@"error"("Can't use 'this' outside of a class.");
            return;
        }
        compiler.variable(false);
    }

    fn unary(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const operatorType = parser.previous.type;

        compiler.parsePrecedence(.prec_unary);

        switch (operatorType) {
            .token_bang => compiler.emitByte(OpCode.op_not.u8()),
            .token_minus => compiler.emitByte(OpCode.op_negate.u8()),

            else => unreachable,
        }
    }

    fn parsePrecedence(compiler: *Compiler, precedence: Precedence) void {
        compiler.advance();
        const prefixRule: ParseFn = getRule(parser.previous.type).prefix orelse {
            compiler.@"error"("Expect expression.");
            return;
        };

        const can_assign = @intFromEnum(precedence) <= @intFromEnum(Precedence.prec_assignment);
        prefixRule(compiler, can_assign);
        while (@intFromEnum(precedence) <= @intFromEnum(getRule(parser.current.type).precedence)) {
            compiler.advance();
            const infixRule: ParseFn = getRule(parser.previous.type).infix orelse unreachable;
            infixRule(compiler, can_assign);
        }

        if (can_assign and compiler.match(.token_equal)) {
            compiler.@"error"("Invalid assignment target.");
        }
    }

    fn identifierConstant(compiler: *Compiler, name: *Token) usize {
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

    fn addUpvalue(compiler: *Compiler, index: u8, is_local: bool) isize {
        const upvalue_count = compiler.function.upvalue_count;
        for (0..upvalue_count) |i| {
            const upvalue = &compiler.upvalues[i];
            if (upvalue.index == index and upvalue.is_local == is_local) {
                return @intCast(i);
            }
        }

        if (upvalue_count == compiler.upvalues.len) {
            compiler.@"error"("Too many closure variables in function.");

            return 0;
        }

        compiler.upvalues[upvalue_count].is_local = is_local;
        compiler.upvalues[upvalue_count].index = index;

        compiler.function.upvalue_count += 1;

        return @intCast(upvalue_count);
    }

    fn resolveUpvalue(compiler: *Compiler, name: *Token) isize {
        if (compiler.enclosing) |enclosing| {
            const local = enclosing.resolveLocal(name);
            if (local != -1) {
                enclosing.locals[@as(usize, @intCast(local))].is_captured = true;
                return compiler.addUpvalue(@as(u8, @intCast(local)), true);
            }

            const upvalue = enclosing.resolveUpvalue(name);
            if (upvalue != -1) {
                return compiler.addUpvalue(@as(u8, @intCast(upvalue)), false);
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
        local.is_captured = false;
    }

    fn declareVariable(compiler: *Compiler) void {
        if (scope_depth == 0) return;

        const name = &parser.previous;
        var i = compiler.local_count;
        while (i > 0) {
            i -= 1;
            const local = &compiler.locals[i];
            if (local.depth != -1 and local.depth < scope_depth) {
                break;
            }

            if (name.eql(&local.name)) {
                compiler.@"error"("Already a variable with this name in this scope.");
            }
        }

        compiler.addLocal(name.*);
    }

    fn parseVariable(compiler: *Compiler, error_message: []const u8) usize {
        compiler.consume(.token_identifier, error_message);

        compiler.declareVariable();
        if (scope_depth > 0) {
            return 0;
        }

        return compiler.identifierConstant(&parser.previous);
    }

    fn markInitialized(compiler: *Compiler) void {
        if (scope_depth == 0) return;
        compiler.locals[compiler.local_count - 1].depth = @intCast(scope_depth);
    }

    fn defineVariable(compiler: *Compiler, global: usize) void {
        if (scope_depth > 0) {
            compiler.markInitialized();
            return;
        }

        compiler.emitByte(OpCode.op_define_global.u8());
        compiler.emitShort(global);
    }

    fn and_(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;

        const end_jump = compiler.emitJump(OpCode.op_jump_if_false.u8());

        compiler.emitByte(OpCode.op_pop.u8());
        compiler.parsePrecedence(.prec_and);

        compiler.patchJump(end_jump);
    }

    fn or_(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;

        const else_jump = compiler.emitJump(OpCode.op_jump_if_false.u8());
        const end_jump = compiler.emitJump(OpCode.op_jump.u8());

        compiler.patchJump(else_jump);
        compiler.emitByte(OpCode.op_pop.u8());

        compiler.parsePrecedence(.prec_or);
        compiler.patchJump(end_jump);
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

    fn ifStatement(compiler: *Compiler) void {
        compiler.consume(.token_left_paren, "Expect '(' after 'if'.");
        compiler.expression();
        compiler.consume(.token_right_paren, "Expect ')' after condition.");

        const then_jump = compiler.emitJump(OpCode.op_jump_if_false.u8());
        compiler.emitByte(OpCode.op_pop.u8());
        compiler.statement();

        const else_jump = compiler.emitJump(OpCode.op_jump.u8());

        compiler.patchJump(then_jump);

        compiler.emitByte(OpCode.op_pop.u8());
        if (compiler.match(.token_else)) {
            compiler.statement();
        }

        compiler.patchJump(else_jump);
    }

    fn whileStatement(compiler: *Compiler) void {
        const loop_start = compiler.currentChunk().count();

        compiler.consume(.token_left_paren, "Expect '(' after 'while'.");
        compiler.expression();
        compiler.consume(.token_right_paren, "Expect ')' after condition.");

        const exit_jump = compiler.emitJump(OpCode.op_jump_if_false.u8());
        compiler.emitByte(OpCode.op_pop.u8());
        compiler.statement();

        compiler.emitLoop(loop_start);
        compiler.patchJump(exit_jump);
        compiler.emitByte(OpCode.op_pop.u8());
    }

    fn forStatement(compiler: *Compiler) void {
        compiler.beginScope();

        compiler.consume(.token_left_paren, "Expect '(' after 'for'.");
        if (compiler.match(.token_semicolon)) {
            // No initializer.
        } else if (compiler.match(.token_var)) {
            compiler.varDeclaration();
        } else {
            compiler.expressionStatement();
        }

        var loop_start = compiler.currentChunk().count();
        var exit_jump: isize = -1;
        if (!compiler.match(.token_semicolon)) {
            compiler.expression();
            compiler.consume(.token_semicolon, "Expect ';' after loop condition.");

            exit_jump = @intCast(compiler.emitJump(OpCode.op_jump_if_false.u8()));
            // exit_jump = @as(isize, @intCast(compiler.emitJump(OpCode.op_jump_if_false.u8())));
            compiler.emitByte(OpCode.op_pop.u8()); // Condition
        }

        if (!compiler.match(.token_right_paren)) {
            const body_jump = compiler.emitJump(OpCode.op_jump.u8());
            const increment_start = compiler.currentChunk().count();
            compiler.expression();
            compiler.emitByte(OpCode.op_pop.u8());
            compiler.consume(.token_right_paren, "Expect ')' after for clauses.");

            compiler.emitLoop(loop_start);
            loop_start = increment_start;
            compiler.patchJump(body_jump);
        }

        compiler.statement();
        compiler.emitLoop(loop_start);
        if (exit_jump != -1) {
            compiler.patchJump(@intCast(exit_jump));
            compiler.emitByte(OpCode.op_pop.u8()); // Condition
        }

        compiler.endScope();
    }

    fn returnStatement(compiler: *Compiler) void {
        if (compiler.type == .type_script) {
            compiler.@"error"("Can't return from top-level code.");
        }

        if (compiler.match(.token_semicolon)) {
            compiler.emitReturn();
        } else {
            if (compiler.type == .type_initializer) {
                compiler.@"error"("Can't return a value from an initializer.");
            }

            compiler.expression();
            compiler.consume(.token_semicolon, "Expect ';' after return value.");
            compiler.emitByte(OpCode.op_return.u8());
        }
    }

    fn expressionStatement(compiler: *Compiler) void {
        compiler.expression();
        compiler.consume(.token_semicolon, "Expect ';' after expression.");
        compiler.emitByte(OpCode.op_pop.u8());
    }

    fn method(compiler: *Compiler) void {
        compiler.consume(.token_identifier, "Expect method name.");
        const name_constant = compiler.identifierConstant(&parser.previous);

        var function_type: FunctionType = .type_method;
        if (parser.previous.length == 4 and
            std.mem.eql(u8, parser.previous.start[0..4], "init"))
        {
            function_type = .type_initializer;
        }
        compiler.compileFunction(function_type);

        compiler.emitByte(OpCode.op_method.u8());
        compiler.emitShort(name_constant);
    }

    fn classDeclaration(compiler: *Compiler) void {
        compiler.consume(.token_identifier, "Expect class name.");

        const class_name = parser.previous;
        const name_constant = compiler.identifierConstant(&parser.previous);
        compiler.declareVariable();

        compiler.emitByte(OpCode.op_class.u8());
        compiler.emitShort(name_constant);
        compiler.defineVariable(name_constant);

        var class_compiler = ClassCompiler{
            .enclosing = current_class,
            .has_superclass = false,
        };
        current_class = &class_compiler;

        if (compiler.match(.token_less)) {
            compiler.consume(.token_identifier, "Expect superclass name.");
            compiler.variable(false);
            if (class_name.eql(&parser.previous)) {
                compiler.@"error"("A class can't inherit from itself.");
            }

            compiler.beginScope();
            compiler.addLocal(syntheticToken("super"));
            compiler.defineVariable(0);

            compiler.namedVariable(class_name, false);
            compiler.emitByte(OpCode.op_inherit.u8());
            class_compiler.has_superclass = true;
        }

        compiler.namedVariable(class_name, false);

        compiler.consume(.token_left_brace, "Expect '{' before class body.");

        while (!compiler.check(.token_right_brace) and !compiler.check(.token_eof)) {
            compiler.method();
        }

        compiler.consume(.token_right_brace, "Expect '}' after class body.");
        compiler.emitByte(OpCode.op_pop.u8()); // pop class
        if (class_compiler.has_superclass) {
            compiler.endScope();
        }
        current_class = class_compiler.enclosing;
    }

    fn compileFunction(compiler: *Compiler, function_type: FunctionType) void {
        var fun_compiler = Compiler.init(compiler.vm, function_type, compiler);
        Compiler.current = &fun_compiler;
        fun_compiler.beginScope();

        fun_compiler.consume(.token_left_paren, "Expect '(' after function name.");
        if (!fun_compiler.check(.token_right_paren)) {
            while (true) {
                fun_compiler.function.arity += 1;
                if (fun_compiler.function.arity > 255) {
                    compiler.@"error"("Can't have more than 255 parameters.");
                    break;
                }

                const constant = fun_compiler.parseVariable("Expect parameter name.");
                fun_compiler.defineVariable(constant);

                if (!fun_compiler.match(.token_comma)) break;
            }
        }
        fun_compiler.consume(.token_right_paren, "Expect ')' after parameters.");
        fun_compiler.consume(.token_left_brace, "Expect '{' before function body.");
        fun_compiler.block();

        fun_compiler.endScope();

        const function = fun_compiler.endCompiler();

        if (function == null) {
            compiler.@"error"("Cannot compile function: OOM");
            return;
        }

        compiler.emitByte(OpCode.op_closure.u8());
        compiler.emitShort(compiler.makeConstant(Value.initObj(function.?)));
        for (0..function.?.upvalue_count) |i| {
            compiler.emitByte(@intFromBool(fun_compiler.upvalues[i].is_local));
            compiler.emitByte(fun_compiler.upvalues[i].index);
        }
    }

    fn funDeclaration(compiler: *Compiler) void {
        const global = compiler.parseVariable("Expect function name.");
        compiler.markInitialized();
        compiler.compileFunction(.type_function);
        compiler.defineVariable(global);
    }

    fn varDeclaration(compiler: *Compiler) void {
        const global: usize = compiler.parseVariable("Expect variable name.");

        if (compiler.match(.token_equal)) {
            compiler.expression();
        } else {
            compiler.emitByte(OpCode.op_nil.u8());
        }

        compiler.consume(.token_semicolon, "Expect ';' after variable declaration.");
        compiler.defineVariable(global);
    }

    fn synchronize(compiler: *Compiler) void {
        parser.panic_mode = false;

        while (parser.current.type != .token_eof) {
            if (parser.previous.type == .token_semicolon) return;

            switch (parser.current.type) {
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
        if (compiler.match(.token_class)) {
            compiler.classDeclaration();
        } else if (compiler.match(.token_fun)) {
            compiler.funDeclaration();
        } else if (compiler.match(.token_var)) {
            compiler.varDeclaration();
        } else {
            compiler.statement();
        }

        if (parser.panic_mode) compiler.synchronize();
    }

    fn statement(compiler: *Compiler) void {
        if (compiler.match(.token_print)) {
            compiler.printStatement();
        } else if (compiler.match(.token_if)) {
            compiler.ifStatement();
        } else if (compiler.match(.token_while)) {
            compiler.whileStatement();
        } else if (compiler.match(.token_for)) {
            compiler.forStatement();
        } else if (compiler.match(.token_return)) {
            compiler.returnStatement();
        } else if (compiler.match(.token_left_brace)) {
            compiler.beginScope();
            compiler.block();
            compiler.endScope();
        } else {
            compiler.expressionStatement();
        }
    }

    fn currentChunk(compiler: *Compiler) *Chunk {
        return &compiler.function.chunk;
    }

    fn errorAt(compiler: *Compiler, token: *Token, message: []const u8) void {
        _ = compiler;

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
        parser.had_error = true;
    }

    fn @"error"(compiler: *Compiler, message: []const u8) void {
        compiler.errorAt(&parser.previous, message);
    }

    fn errorAtCurrent(compiler: *Compiler, message: []const u8) void {
        compiler.errorAt(&parser.current, message);
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
    is_captured: bool,
};

const Upvalue = struct {
    index: u8,
    is_local: bool,
};

const FunctionType = enum {
    type_function,
    type_initializer,
    type_method,
    type_script,
};

const rules = blk: {
    var tmp: [@typeInfo(TokenType).@"enum".fields.len]ParseRule = undefined;
    tmp[TokenType.token_left_paren.u8()] = .{
        .prefix = Compiler.grouping,
        .infix = Compiler.call,
        .precedence = .prec_call,
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
        .infix = Compiler.dot,
        .precedence = .prec_call,
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
        .infix = Compiler.and_,
        .precedence = .prec_and,
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
        .infix = Compiler.or_,
        .precedence = .prec_or,
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
        .prefix = Compiler.super,
        .infix = null,
        .precedence = .prec_none,
    };
    tmp[TokenType.token_this.u8()] = .{
        .prefix = Compiler.this,
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

fn syntheticToken(text: []const u8) Token {
    var token: Token = undefined;
    token.start = text.ptr;
    token.length = @as(u32, @truncate(text.len));

    return token;
}
