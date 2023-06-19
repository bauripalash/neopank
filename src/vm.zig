//
// Copyright (C) Palash Bauri
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");
const ins = @import("instruction.zig");
const OpCode = @import("instruction.zig").OpCode;
const Compiler = @import("compiler.zig").Compiler;
const Gc = @import("gc.zig").Gc;
const vl = @import("value.zig");
const PValue = vl.PValue;
const Pobj = @import("object.zig").PObj;
const utils = @import("utils.zig");
const table = @import("table.zig");
const Allocator = std.mem.Allocator;
const flags = @import("flags.zig");

pub const IntrpResult = enum(u8) {
    Ok,
    CompileError,
    RuntimeError,

    pub fn toString(self : IntrpResult) []const u8 {
        switch (self) {
            .Ok => { return "Ok"; },
            .CompileError => { return "CompileError"; },
            .RuntimeError => { return "RuntimeError"; },
        }
    }
};


pub const Vm = struct {
    ins : ins.Instruction,
    compiler : *Compiler,
    ip : u8,
    stack : std.ArrayList(PValue),
    stackTop : usize,
    gc : *Gc,


    const Self = @This();

    pub fn newVm(al : Allocator) !*Vm{
        const v = try al.create(Vm);
        return v;
        
    }

    pub fn bootVm(self : *Self , gc : *Gc) void {
        self.* = .{
            .gc = gc,
            .ins = ins.Instruction.init(gc.getAlc()),
            .stack = std.ArrayList(PValue).init(gc.getAlc()),
            .ip = 0,
            .stackTop = 0,
            .compiler = undefined,
        };
        

        //self.strings = table.StringTable(){};
        
    }

    pub fn freeVm(self : *Self , al : Allocator) void {
        //std.debug.print("{d}\n", .{self.strings.keys().len});
        //_ = table.freeStringTable(self, self.strings); 
        self.compiler.free(self.gc.getAlc());
        self.gc.free();
        self.stack.deinit();
        self.ins.free();
        al.destroy(self);
        
    }

    fn readByte(self : *Self) ins.OpCode{
        self.ip += 1;
        return @intToEnum(ins.OpCode, self.ins.code.items[self.ip - 1]);

    }

    fn readRawByte(self : *Self) u8 {
        self.ip += 1;
        return self.ins.code.items[self.ip - 1];
    }

    fn readConst(self : *Self) PValue {
       return self.ins.cons.items[self.readRawByte()];
    }

    fn resetStack(self : *Self) void {
        self.stackTop = 0;
    }
    
    pub fn push(self : *Self , value : PValue) !void {
        try self.stack.append(value);
        
    }

    pub fn pop(self : *Self) PValue {
        return self.stack.pop();
    }


    fn peek(self : *Self , dist : usize) PValue{
        return self.stack.items[dist];
    }

    fn throwRuntimeError(self : *Self , msg : []const u8) void{
        
        std.debug.print("Runtime Error Occured in line {}", .{self.ins.pos.items[@intCast(usize, self.ip)-1].line});
        std.debug.print("\n{s}\n", .{msg});
    }

    pub fn debugStack(self : *Self) void{
        std.debug.print("==== STACK ====\n" , .{});
        if (self.stack.items.len > 0) {
            for (self.stack.items, 0..) |value, i| {
                const vs = value.toString(self.gc.getAlc()) catch return;
                std.debug.print("[ |{:0>2}| {s:>4}" , .{self.stack.items.len - 1 - i , vs } );
                std.debug.print(" ]\n" , .{});
                self.gc.getAlc().free(vs);

            }
        }
        std.debug.print("===============\n\n" , .{});
    }

    fn doBinaryOpAdd(self : *Self) bool{
        // only works on numbers
        const b = self.pop();
        const a = self.pop();

        if (a.isNumber() and b.isNumber()) {
            self.push(PValue.makeNumber(a.asNumber() + b.asNumber())) catch return false;
            return true;
        }else if (a.isString() and b.isString()) {
            const bs = b.asObj().asString();
            const as = b.asObj().asString();
            
            var temp_chars = self.gc.getAlc().alloc(u32, as.chars.len + bs.chars.len) catch return false;
            var i : usize = 0;

            while (i < as.chars.len) {
                temp_chars[i] = as.chars[i];
                i += 1;
            }

            while (i - as.chars.len < bs.chars.len) {
                temp_chars[i] = bs.chars[i - as.chars.len];
                i += 1;
            }
            

            const s = self.gc.copyString(temp_chars, @intCast(u32 , temp_chars.len)) catch {
                 self.gc.getAlc().free(temp_chars);
                return false;
            };
            self.push(s.obj.asValue()) catch {
                self.gc.getAlc().free(temp_chars);
                return false;
            };
            self.gc.getAlc().free(temp_chars);
            return true;
        } else {
            return false;
        }
        
    }

    fn doBinaryOpSub(self : *Self) bool{
        // only works on numbers
        const b = self.pop();
        const a = self.pop();

        if (a.isNumber() and b.isNumber()) {
            self.push(PValue.makeNumber(a.asNumber() - b.asNumber())) catch return false;
            return true;
        } else {
            return false;
        }
        
    }

    fn doBinaryOpMul(self : *Self) bool{
        // only works on numbers
        const b = self.pop();
        const a = self.pop();

        if (a.isNumber() and b.isNumber()) {
            self.push(PValue.makeNumber(a.asNumber() * b.asNumber())) catch return false;
            return true;
        } else {
            return false;
        }
        
    }

    fn doBinaryOpDiv(self : *Self) bool{
        // only works on numbers
        const b = self.pop();
        const a = self.pop();

        if (a.isNumber() and b.isNumber()) {
            self.push(PValue.makeNumber(a.asNumber() / b.asNumber())) catch return false;
            return true;
        } else {
            return false;
        }
        
    }

    fn run(self : *Self) IntrpResult{
        while (true) {
            if (flags.DEBUG) {
                self.debugStack();
            }
            const op = self.readByte();

            switch (op) {
                .Op_Return => {
                    //self.throwRuntimeError("Return occured");
                    self.pop().printVal();
                    std.debug.print("\n" , .{});
                    return IntrpResult.Ok;
                },

                .Op_Const => {
                   const con : PValue = self.readConst();
                   self.push(con) catch return .RuntimeError;

                },

                .Op_Neg => {
                    var v = self.pop();
                    if (v.isNumber()) {
                        self.push(v.makeNeg()) catch return .RuntimeError;
                    } else {
                        return .RuntimeError;
                    }
                },

                .Op_Add => {
                    if (!self.doBinaryOpAdd()){
                        return .RuntimeError;
                    }
                },

                .Op_Sub => {
                    if (!self.doBinaryOpSub()) { return .RuntimeError; }
                },

                .Op_Mul => { if (!self.doBinaryOpMul()) { return .RuntimeError; } 
                
                },

                .Op_Div => {
                    if (!self.doBinaryOpDiv()) {
                        return .RuntimeError;
                    }
                },

                .Op_True => {
                    self.push(PValue.makeBool(true)) catch {
                        return .RuntimeError;
                    };
                },

                .Op_False => {
                    self.push(PValue.makeBool(false)) catch {
                        return .RuntimeError;
                    };
                },

                .Op_Eq => {
                    const b = self.pop();
                    const a = self.pop();

                    self.push(PValue.makeBool(a.isEqual(b))) catch {
                        return .RuntimeError;  
                    };
                },

                .Op_Neq => {
                    const b = self.pop();
                    const a = self.pop();
                    
                    self.push(PValue.makeBool(!a.isEqual(b))) catch {
                        return .RuntimeError;  
                    };

                },

                .Op_Nil => {
                    self.push(PValue.makeNil()) catch {
                        return .RuntimeError;    
                    };
                },

                .Op_Not => {
                    self.push(PValue.makeBool(self.pop().isFalsy())) catch {
                        return .RuntimeError;
                    };
                },

                else => {
                    return IntrpResult.RuntimeError;
                }
            }
        }
    }

    pub fn interpretRaw(self : *Self , inst : *ins.Instruction) IntrpResult{
        //@memcpy(self.ins.*, inst.);
        self.ip = 0;
        self.ins = inst.*;
        return self.run();
    }

    pub fn interpret(self : *Self , source : []u32) IntrpResult{
        self.ip = 0;
        self.compiler = Compiler.new(source, self.gc) catch return .RuntimeError;
        const result = self.compiler.compile(source, &self.ins) catch false;
        if (result) { 
            return self.interpretRaw(self.compiler.curIns());
        } else { 
            return .CompileError;
        }

    }


};
