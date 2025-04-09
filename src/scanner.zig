pub const Scanner = struct {
    last: [*]const u8,
    start: [*]const u8,
    current: [*]const u8,
    line: u32,

    pub fn init(source: []const u8) Scanner {
        return .{
            .last = source.ptr + source.len,
            .start = source.ptr,
            .current = source.ptr,
            .line = 1,
        };
    }

    fn isAtEnd(scanner: *Scanner) bool {
        return @intFromPtr(scanner.current) >= @intFromPtr(scanner.last);
    }

    fn advance(scanner: *Scanner) u8 {
        const c = scanner.current[0];
        scanner.current += 1;

        return c;
    }

    fn peek(scanner: *Scanner) u8 {
        return scanner.current[0];
    }

    fn peekNext(scanner: *Scanner) u8 {
        if (scanner.isAtEnd()) return 0;

        return scanner.current[1];
    }

    fn match(scanner: *Scanner, expected: u8) bool {
        if (scanner.isAtEnd()) return false;
        if (scanner.current[0] != expected) return false;
        scanner.current += 1;

        return true;
    }

    fn makeToken(scanner: *Scanner, token_type: TokenType) Token {
        return .{
            .type = token_type,
            .start = scanner.start,
            .length = @intCast(@intFromPtr(scanner.current) - @intFromPtr(scanner.start)),
            .line = scanner.line,
        };
    }

    fn errorToken(scanner: *Scanner, message: []const u8) Token {
        return .{
            .type = .token_error,
            .start = message.ptr,
            .length = @intCast(message.len),
            .line = scanner.line,
        };
    }

    fn skipWhitespace(scanner: *Scanner) void {
        while (true) {
            const c = scanner.peek();
            switch (c) {
                ' ',
                '\r',
                '\t',
                => {
                    _ = scanner.advance();
                },
                '\n' => {
                    scanner.line += 1;
                    _ = scanner.advance();
                },
                '/' => {
                    if (scanner.peekNext() == '/') {
                        while (scanner.peek() != '\n' and !scanner.isAtEnd()) {
                            _ = scanner.advance();
                        }
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    fn string(scanner: *Scanner) Token {
        while (scanner.peek() != '"' and !scanner.isAtEnd()) {
            if (scanner.peek() == '\n') scanner.line += 1;
            _ = scanner.advance();
        }

        if (scanner.isAtEnd()) return scanner.errorToken("Unterminated string.");

        _ = scanner.advance();

        return scanner.makeToken(.token_string);
    }

    fn number(scanner: *Scanner) Token {
        while (isDigit(scanner.peek())) _ = scanner.advance();

        if (scanner.peek() == '.' and isDigit(scanner.peekNext())) {
            _ = scanner.advance();

            while (isDigit(scanner.peek())) _ = scanner.advance();
        }

        return scanner.makeToken(.token_number);
    }

    fn checkKeyword(scanner: *Scanner, start: u32, rest: []const u8, token_type: TokenType) TokenType {
        if (@intFromPtr(scanner.current) - @intFromPtr(scanner.start) == start + rest.len and
            mem.eql(u8, scanner.start[start..][0..rest.len], rest))
        {
            return token_type;
        }
        return .token_identifier;
    }

    fn identifierType(scanner: *Scanner) TokenType {
        switch (scanner.start[0]) {
            'a' => return scanner.checkKeyword(1, "nd", .token_and),
            'c' => return scanner.checkKeyword(1, "lass", .token_class),
            'e' => return scanner.checkKeyword(1, "lse", .token_else),
            'f' => {
                if (@intFromPtr(scanner.current) - @intFromPtr(scanner.start) > 1) {
                    switch (scanner.start[1]) {
                        'a' => return scanner.checkKeyword(2, "lse", .token_false),
                        'o' => return scanner.checkKeyword(2, "r", .token_for),
                        'u' => return scanner.checkKeyword(2, "n", .token_fun),

                        else => return .token_identifier,
                    }
                } else {
                    return .token_identifier;
                }
            },
            'i' => return scanner.checkKeyword(1, "f", .token_if),
            'n' => return scanner.checkKeyword(1, "il", .token_nil),
            'o' => return scanner.checkKeyword(1, "r", .token_or),
            'p' => return scanner.checkKeyword(1, "rint", .token_print),
            'r' => return scanner.checkKeyword(1, "eturn", .token_return),
            's' => return scanner.checkKeyword(1, "uper", .token_super),
            't' => {
                if (@intFromPtr(scanner.current) - @intFromPtr(scanner.start) > 1) {
                    switch (scanner.start[1]) {
                        'h' => return scanner.checkKeyword(2, "is", .token_this),
                        'r' => return scanner.checkKeyword(2, "ue", .token_true),

                        else => return .token_identifier,
                    }
                } else {
                    return .token_identifier;
                }
            },
            'v' => return scanner.checkKeyword(1, "ar", .token_var),
            'w' => return scanner.checkKeyword(1, "hile", .token_while),

            else => return .token_identifier,
        }
    }

    fn identifier(scanner: *Scanner) Token {
        while (isAlpha(scanner.peek()) or isDigit(scanner.peek())) _ = scanner.advance();

        return scanner.makeToken(scanner.identifierType());
    }

    pub fn scanToken(scanner: *Scanner) Token {
        scanner.skipWhitespace();
        scanner.start = scanner.current;

        if (scanner.isAtEnd()) return scanner.makeToken(.token_eof);

        const c = scanner.advance();
        if (isAlpha(c)) return scanner.identifier();
        if (isDigit(c)) return scanner.number();

        switch (c) {
            '(' => return scanner.makeToken(.token_left_paren),
            ')' => return scanner.makeToken(.token_right_paren),
            '{' => return scanner.makeToken(.token_left_brace),
            '}' => return scanner.makeToken(.token_right_brace),
            ';' => return scanner.makeToken(.token_semicolon),
            ',' => return scanner.makeToken(.token_comma),
            '.' => return scanner.makeToken(.token_dot),
            '-' => return scanner.makeToken(.token_minus),
            '+' => return scanner.makeToken(.token_plus),
            '/' => return scanner.makeToken(.token_slash),
            '*' => return scanner.makeToken(.token_star),
            '!' => return scanner.makeToken(if (scanner.match('=')) .token_bang_equal else .token_bang),
            '=' => return scanner.makeToken(if (scanner.match('=')) .token_equal_equal else .token_equal),
            '<' => return scanner.makeToken(if (scanner.match('=')) .token_less_equal else .token_less),
            '>' => return scanner.makeToken(if (scanner.match('=')) .token_greater_equal else .token_greater),
            '"' => return scanner.string(),

            else => return scanner.errorToken("Unexpected character."),
        }
    }
};

pub const Token = struct {
    type: TokenType,
    start: [*]const u8,
    length: u32,
    line: u32,

    pub fn eql(a: *Token, b: *Token) bool {
        if (a.length != b.length) return false;

        return mem.eql(u8, a.start[0..a.length], b.start[0..b.length]);
    }
};

pub const TokenType = enum {
    // Single-character tokens.
    token_left_paren,
    token_right_paren,
    token_left_brace,
    token_right_brace,
    token_comma,
    token_dot,
    token_minus,
    token_plus,
    token_semicolon,
    token_slash,
    token_star,

    // One or two character tokens.
    token_bang,
    token_bang_equal,
    token_equal,
    token_equal_equal,
    token_greater,
    token_greater_equal,
    token_less,
    token_less_equal,

    // Literals.
    token_identifier,
    token_string,
    token_number,

    // Keywords.
    token_and,
    token_class,
    token_else,
    token_false,
    token_for,
    token_fun,
    token_if,
    token_nil,
    token_or,
    token_print,
    token_return,
    token_super,
    token_this,
    token_true,
    token_var,
    token_while,

    token_error,
    token_eof,

    pub inline fn @"u8"(self: TokenType) u8 {
        return @intFromEnum(self);
    }

    pub fn toString(self: TokenType) []const u8 {
        return switch (self) {
            .token_left_paren => "TOKEN_LEFT_PAREN",
            .token_right_paren => "TOKEN_RIGHT_PAREN",
            .token_left_brace => "TOKEN_LEFT_BRACE",
            .token_right_brace => "TOKEN_RIGHT_BRACE",
            .token_comma => "TOKEN_COMMA",
            .token_dot => "TOKEN_DOT",
            .token_minus => "TOKEN_MINUS",
            .token_plus => "TOKEN_PLUS",
            .token_semicolon => "TOKEN_SEMICOLON",
            .token_slash => "TOKEN_SLASH",
            .token_star => "TOKEN_STAR",

            .token_bang => "TOKEN_BANG",
            .token_bang_equal => "TOKEN_BANG_EQUAL",
            .token_equal => "TOKEN_EQUAL",
            .token_equal_equal => "TOKEN_EQUAL_EQUAL",
            .token_greater => "TOKEN_GREATER",
            .token_greater_equal => "TOKEN_GREATER_EQUAL",
            .token_less => "TOKEN_LESS",
            .token_less_equal => "TOKEN_LESS_EQUAL",

            .token_identifier => "TOKEN_IDENTIFIER",
            .token_string => "TOKEN_STRING",
            .token_number => "TOKEN_NUMBER",

            .token_and => "TOKEN_AND",
            .token_class => "TOKEN_CLASS",
            .token_else => "TOKEN_ELSE",
            .token_false => "TOKEN_FALSE",
            .token_for => "TOKEN_FOR",
            .token_fun => "TOKEN_FUN",
            .token_if => "TOKEN_IF",
            .token_nil => "TOKEN_NIL",
            .token_or => "TOKEN_OR",
            .token_print => "TOKEN_PRINT",
            .token_return => "TOKEN_RETURN",
            .token_super => "TOKEN_SUPER",
            .token_this => "TOKEN_THIS",
            .token_true => "TOKEN_TRUE",
            .token_var => "TOKEN_VAR",
            .token_while => "TOKEN_WHILE",

            .token_error => "TOKEN_ERROR",
            .token_eof => "TOKEN_EOF",
        };
    }
};

fn isDigit(c: u8) bool {
    switch (c) {
        '0'...'9' => return true,
        else => return false,
    }
}

fn isAlpha(c: u8) bool {
    switch (c) {
        'a'...'z', 'A'...'Z', '_' => return true,
        else => return false,
    }
}

const mem = @import("std").mem;
