//
// Copyright (C) Palash Bauri
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");
const PValue = @import("value.zig").PValue;
const Gc = @import("gc.zig").Gc;

pub const OpCode = enum(u8) {
    Op_Return,
    Op_Const,
    Op_Neg,
    Op_Add,
    Op_Sub,
    Op_Mul,
    Op_Div,
    Op_Nil,
    Op_True,
    Op_False,
    Op_Not,
    Op_Eq,
    Op_Neq,
    Op_Gt,
    Op_Gte,
    Op_Lt,
    Op_Lte,
    Op_Show,
    Op_Pop,
    Op_DefGlob,
    Op_SetGlob,
    Op_GetGlob,
    Op_GetLocal,
    Op_SetLocal,
    Op_JumpIfFalse,
    Op_Jump,
    Op_Loop,
    Op_Call,
    Op_Closure,
    Op_GetUp,
    Op_SetUp,
    Op_ClsUp,
    Op_Import,
    Op_SetModProp,
    Op_GetModProp,
    Op_EndMod,
    Op_Err,
    Op_Array,
    Op_Hmap,
    Op_Index,
    Op_SubAssign,

    const Self = @This();
    pub fn toString(self: *const Self) []const u8 {
        return switch (self.*) {
            .Op_Return => "OP_RETURN",
            .Op_Const => "OP_CONST",
            .Op_Neg => "OP_NEG",
            .Op_Add => "OP_ADD",
            .Op_Sub => "OP_SUB",
            .Op_Mul => "OP_MUL",
            .Op_Div => "OP_DIV",
            .Op_Nil => "OP_NIL",
            .Op_True => "OP_TRUE",
            .Op_False => "OP_FALSE",
            .Op_Not => "OP_NOT",
            .Op_Eq => "OP_EQ",
            .Op_Neq => "OP_NEQ",
            .Op_Gt => "OP_GT",
            .Op_Gte => "OP_GTE",
            .Op_Lt => "OP_LT",
            .Op_Lte => "OP_LTE",
            .Op_Show => "OP_SHOW",
            .Op_Pop => "OP_POP",
            .Op_DefGlob => "OP_DEF_GLOB",
            .Op_SetGlob => "OP_SET_GLOB",
            .Op_GetGlob => "OP_GET_GLOB",
            .Op_GetLocal => "OP_GET_LOCAL",
            .Op_SetLocal => "OP_SET_LOCAL",
            .Op_JumpIfFalse => "OP_JUMP_IF_FALSE",
            .Op_Jump => "OP_JUMP",
            .Op_Loop => "OP_LOOP",
            .Op_Call => "OP_CALL",
            .Op_Closure => "OP_CLOSURE",
            .Op_GetUp => "OP_GET_UP",
            .Op_SetUp => "OP_SET_UP",
            .Op_ClsUp => "OP_CLOSE_UP",
            .Op_Import => "OP_IMPORT",
            .Op_SetModProp => "OP_GET_MOD_PROP",
            .Op_GetModProp => "OP_SET_MOD_PROP",
            .Op_EndMod => "OP_END_MOD",
            .Op_Err => "OP_ERR",
            .Op_Array => "OP_ARRAY",
            .Op_Hmap => "OP_HMAP",
            .Op_Index => "OP_INDEX",
            .Op_SubAssign => "OP_SUB_ASSIGN",
            //else => {"OP_UNKNOWN"; }
        };
    }
};

pub const InstPos = struct {
    virtual: bool,
    colpos: u32,
    line: u32,
    length: u32,

    pub fn dummy() InstPos {
        return InstPos{
            .virtual = true,
            .colpos = 0,
            .line = 0,
            .length = 0,
        };
    }

    pub fn line(l : u32) InstPos {
        return InstPos{
            .virtual = true,
            .colpos = 0,
            .line = l,
            .length = 0,
        };
    }
};

pub const Instruction = struct {
    code: std.ArrayListUnmanaged(u8),
    pos: std.ArrayListUnmanaged(InstPos),
    cons : std.ArrayListUnmanaged(PValue),
    gc : *Gc,

    pub fn init(gc : *Gc) Instruction {

        return Instruction{
            .code = std.ArrayListUnmanaged(u8){},
            .pos = std.ArrayListUnmanaged(InstPos){},
            .cons = std.ArrayListUnmanaged(PValue){},
            .gc = gc,
        };
    }

    pub fn free(self: *Instruction) void {
        self.code.deinit(self.gc.getAlc());
        self.pos.deinit(self.gc.getAlc());
        self.cons.deinit(self.gc.getAlc());
    }

    pub fn write_raw(self: *Instruction, bt: u8, pos: InstPos) !void {
        try self.code.append(self.gc.getAlc() , bt);
        try self.pos.append(self.gc.getAlc(), pos);
    }

    pub fn write(self: *Instruction, bt: OpCode, pos: InstPos) !void {
        try self.code.append(self.gc.getAlc() , @enumToInt(bt));
        try self.pos.append(self.gc.getAlc() , pos);
    }

    pub fn addConst(self : *Instruction , value : PValue) !u8 {
        try self.cons.append(self.gc.getAlc() , value);
        return @intCast(u8 , self.cons.items.len - 1);
        // catch return false;
        //return true;
    }

    /// Return OpCode at offset
     fn getOpCode(self: *Instruction, offset: usize) OpCode {
        return @intToEnum(OpCode, self.code.items[offset]);
    }

     /// Return OpCode at offset
     fn getRawOpCode(self: *Instruction, offset: usize) u8 {
        return self.code.items[offset];
    }

    pub fn disasm(self: *Instruction, name: []const u8) void {
        std.debug.print("== {s} | [{any}] ==", .{ name, self.code.items.len });
        std.debug.print("\n", .{});

        var i: usize = 0;
        while (i < self.code.items.len) {
            i = self.disasmInstruction(i);
        }

        std.debug.print("\n", .{});
    }

    fn simpleInstruction(_ : *Instruction , name : []const u8 , offset : usize) usize{
        std.debug.print("{s}\n" , .{name});
        return offset + 1;
    }   

    fn constInstruction(self : *Instruction ,  name : []const u8 , offset : usize) usize {
        const constIndex = self.getRawOpCode(offset+1);
        std.debug.print("{s} {d} '" , .{name , constIndex});
        self.cons.items[constIndex].printVal(); 
        std.debug.print("'\n" , .{});
         
        return offset + 2;


    }

    fn disasmInstruction(self: *Instruction, offset: usize) usize {
        std.debug.print("{:0>4} " , .{offset});
        if (offset > 0 and self.pos.items[offset].line == self.pos.items[offset-1].line){
            std.debug.print("   | ", .{});
        } else {
            std.debug.print("{:>4} " , .{self.pos.items[offset].line});
        }

        const ins = self.getOpCode(offset);

        switch (ins) {
            .Op_Return,
            .Op_Neg, 
            .Op_Add , 
            .Op_Sub, 
            .Op_Mul, 
            .Op_Div, 
            .Op_Nil, 
            .Op_True, 
            .Op_False, 
            .Op_Not, 
            .Op_Eq , 
            .Op_Neq,
            .Op_Lt , 
            .Op_Gt , 
            .Op_Pop, 
            .Op_ClsUp, 
            .Op_Err, 
            .Op_Index, 
            .Op_Show,
            .Op_SubAssign => {
                return self.simpleInstruction(ins.toString(), offset);
            },
            .Op_Const, 
            .Op_Import , 
            .Op_DefGlob, 
            .Op_GetGlob, 
            .Op_SetGlob, => { 
                return self.constInstruction(ins.toString() , offset);
            },
            else => {
                return offset + 1;
            }
        }


    }
};