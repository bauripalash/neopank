//
// Copyright (C) Palash Bauri
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");
const openfile = @import("openfile.zig").openfile;
const lexer = @import("lexer/lexer.zig");
const print = std.debug.print;
const utils = @import("utils.zig");
const ins = @import("instruction.zig");
const v = @import("vm.zig");
const Gc = @import("gc.zig").Gc;
const Vm = v.Vm;
const IntrpResult = v.IntrpResult;
const PValue = @import("value.zig").PValue;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ga = gpa.allocator();


    var fileToRun: ?[]u8 = null;

    var args = try std.process.argsAlloc(ga);

    if (args.len == 2) {
        fileToRun = try ga.alloc(u8, args[1].len);
        @memcpy(fileToRun.?, args[1]);
    }
    std.process.argsFree(ga, args);

    var gcGpa = std.heap.GeneralPurposeAllocator(.{}){};
    const GcGa = gcGpa.allocator();
    defer {
        if (fileToRun) |f| {
            ga.free(f);
        }
        _ = gpa.deinit();
        _ = gcGpa.deinit();
    }
    
    if (fileToRun) |f| {
        var gc = try Gc.new(GcGa);
        gc.boot(GcGa);

        const text = try openfile(f, ga);
        const u = try utils.u8tou32(text, ga);
        var myv = try Vm.newVm(gc.getAlc());
        myv.bootVm(gc);
        const result = myv.interpret(u);
        std.debug.print("VM Result : {s}\n" , .{result.toString()});
        myv.freeVm(gc.getAlc());
        ga.free(u);
        ga.free(text);
    } 
}


test "AllTest" {
    std.testing.refAllDecls(@This());
    _ = @import("lexer/lexer.zig");
    _ = @import("instruction.zig");
}
