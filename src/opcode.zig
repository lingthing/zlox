pub const OpCode = enum(u8) {
    op_constant,
    op_return,

    pub inline fn from(byte: u8) OpCode {
        return @enumFromInt(byte);
    }

    pub inline fn @"u8"(self: OpCode) u8 {
        return @intFromEnum(self);
    }

    pub fn toString(self: OpCode) []const u8 {
        return switch (self) {
            .op_constant => "OP_CONSTANT",
            .op_return => "OP_RETURN",
        };
    }
};
