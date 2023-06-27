//
// Copyright (C) Palash Bauri
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const PObj = @import("object.zig").PObj;
const value_zig = @import("value.zig");
const PValue = value_zig.PValue;
const PValueType = value_zig.PValueType;
const table = @import("table.zig");
const utils = @import("utils.zig");
const flags = @import("flags.zig");
const ansicolors = @import("ansicolors.zig");


pub const Gc = struct {
    internal_al : Allocator,
    al : Allocator,
    objects : ?*PObj,
    strings : table.StringTable(),
    globals : table.GlobalsTable(),
    openUps : ?*PObj.OUpValue,
    alocAmount : usize,

    const Self = @This();

    pub fn new(al : Allocator) !*Gc{
        const newgc = try al.create(Self);
        newgc.* = .{
            .internal_al = al,
            .al = undefined,
            .strings = table.StringTable(){},
            .globals = table.GlobalsTable(){},
            .objects = null,
            .openUps = null,
            .alocAmount = 0,
        };

        return newgc;
        
    }

    pub fn boot(self : *Self ) void {
        //std.debug.print("allocator -> {any}\n" , .{self.getAlc()});
        self.al = self.allocator();
    }

    pub inline fn allocator(self : *Self) Allocator {
            return .{
                .ptr = self,
                .vtable = comptime &Allocator.VTable {
                    .alloc = allocImpl,
                    .free = freeImpl,
                    .resize = resizeImpl,
                }
            };
        }

     pub fn allocImpl(ptr: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Gc = @ptrCast(@alignCast(ptr));
        const bts = self.internal_al.rawAlloc(len, ptr_align, ret_addr);
        self.alocAmount += len;
        self.collect() catch return bts;
        //std.debug.print("ALOC SIZE ->{d}bytes\n" , .{len});
        return bts;
    }

    pub fn freeImpl(ptr : *anyopaque , buf : []u8 , bufalign : u8 , ret_addr : usize) void{
        const self: *Gc = @ptrCast(@alignCast(ptr));
        self.alocAmount -= buf.len;
        self.internal_al.rawFree(buf, bufalign, ret_addr);
    }

    pub fn resizeImpl(ptr : *anyopaque , buf : []u8 , bufalign : u8 , newlen : usize , ret_addr : usize ) bool {

        const self: *Gc = @ptrCast(@alignCast(ptr));
        if (buf.len > newlen) {
            self.alocAmount = (self.alocAmount - buf.len) + newlen;
        } else if (buf.len < newlen) {
            self.alocAmount = (self.alocAmount - buf.len) + newlen;
        } 
        return self.internal_al.rawResize(buf, bufalign, newlen, ret_addr);

    }


    


    pub fn getIntAlc(self : *Self) Allocator{
        return self.inernal_al;
    }

    pub fn getAlc(self : *Self) Allocator{
        return self.al;
    }

    pub fn newObj(self : *Self , otype : PObj.OType , comptime ParentType : type) !*ParentType{
        
        const ptr = try self.al.create(ParentType);
        ptr.parent().objtype =  otype;
        ptr.parent().isMarked = false;
        ptr.parent().next = self.objects;
        self.objects = ptr.parent();
        
        if (flags.DEBUG_GC) {
            ansicolors.TermColor('b');
            std.debug.print("[GC] (0x{x}) New Object: {s}" , 
                .{ @intFromPtr(ptr) , 
                    ptr.parent().objtype.toString()}); 

            ansicolors.ResetColor();
            std.debug.print("\n" , .{});
        }

        return ptr;
    }

    pub fn newString(self : *Self , chars : []u32 , len : u32) !*PObj.OString{
        var ptr = try self.newObj(.Ot_String , PObj.OString);
        ptr.chars = chars;
        ptr.len = len;
        ptr.obj.isMarked = true;
        ptr.hash = try utils.hashU32(chars);

        try self.strings.put(self.getAlc(), chars , ptr);

        return ptr;
    }

    pub fn copyString(self : *Gc, chars : []const u32, len : u32) !*PObj.OString{

        if (self.strings.get(chars)) |interned| {
            return interned;
        }
    
        const mem_chars = try self.al.alloc(u32, len);
        @memcpy(mem_chars, chars);

        return self.newString(mem_chars, len);

    }

    pub fn freeSingleObject(self : *Self , obj : *PObj) void {
        if (flags.DEBUG_GC) {
            ansicolors.TermColor('p');
            std.debug.print("[GC] (0x{x}) Free Object: {s} : " , .{@intFromPtr(obj) , obj.objtype.toString()});

        }
        switch (obj.objtype) {
            .Ot_String => {
                const str_obj = obj.child(PObj.OString);
                if (flags.DEBUG_GC) {
                    str_obj.print();
                    std.debug.print("{s}\n" , .{ansicolors.ANSI_COLOR_RESET});
                }

                str_obj.free(self);
            },

            .Ot_Function => {
                const fnObj = obj.child(PObj.OFunction);
                fnObj.free(self);
            },

            .Ot_NativeFunc => {
                const nfObj = obj.asNativeFun();
                nfObj.free(self);
            },

            .Ot_Closure => {
                const cl = obj.asClosure();
                cl.free(self);
            },

            .Ot_UpValue => {
                obj.asUpvalue().free(self);
            },
        }

        return;
    }

    pub fn freeObjects(self : *Self) void{
        var object = self.objects;

        while (object) |obj| {
            const next = obj.next;
            self.freeSingleObject(obj);
            object = next;
        }
    }

    pub fn free(self : *Self) void{
        if (flags.DEBUG and flags.DEBUG_GC) {
            std.debug.print("TOTAL BYTES ALLOCATED-> {d}bytes\n" , .{self.alocAmount});
        }
        self.freeObjects();
        self.strings.deinit(self.al);
        self.globals.deinit(self.al);
        self.getAlc().destroy(self);
    }

    
    pub fn collect(self : *Self) !void{
        _ = self;
        //try self.markRoots();
        //try self.sweep();
    }

    pub fn markRoots(self : *Self) !void{
        try self.markGlobals();
    }

    pub fn markObject(self : *Self , obj : *PObj) !void{
        _ = self;
        if (obj.isMarked) { return;}
        obj.isMarked = true;
        
    }

    pub fn markValue(self : *Self , value : PValue) !void{
        if (value.isObj()) {
            try self.markObject(value.asObj());
        }

        return;
    }
    pub fn markGlobals(self : *Self) !void {
        for (self.globals.values()) |v| {
            try self.markValue(v);
        }

        for (self.globals.keys()) |k| {
            try self.markObject(k.parent());
        }
    }

    pub fn sweep(self : *Self) !void{
        var prev : ?*PObj = null;
        var object : ?*PObj = self.objects;

        while (object) |obj| {
            if (obj.isMarked) {
                obj.isMarked = false;
                prev = obj;
                object = obj.next;
            } else {
                const x = obj;
                object = obj.next;

                if (prev) |p| {
                    p.next = object;
                }else {
                    self.objects = object;
                }

                self.freeSingleObject(x);
            }
        }
    }

};
