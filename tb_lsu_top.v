// =============================================================================
// Testbench: tb_lsu_top
// Project:   IEEE SSCS RV32IM CPU - Team 6 Load/Store Subsystem (LSU)
// Owners:    Omar & Ramin (shared)
//
// Integrated test of all four LSU modules through lsu_top:
//   1. Store a value, then load it back with every load type
//      (LW, LB, LBU, LH, LHU) at every legal offset.
//   2. Byte and halfword stores followed by loads of the same location.
//   3. Misaligned stores are flagged and do not change memory.
//   4. Misaligned loads are flagged.
//
// Expected values are written out by hand (not computed from the design)
// so the test checks the hardware against the RISC-V rules independently.
//
// Run:
//   iverilog -o tb_lsu_top alignment_check.v load_extract.v store_align.v data_memory.v lsu_top.v tb_lsu_top.v
//   vvp tb_lsu_top
//   gtkwave tb_lsu_top.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_lsu_top;

    // funct3 encodings from the shared table
    localparam [2:0] F3_B  = 3'b000;  // LB / SB
    localparam [2:0] F3_H  = 3'b001;  // LH / SH
    localparam [2:0] F3_W  = 3'b010;  // LW / SW
    localparam [2:0] F3_BU = 3'b100;  // LBU
    localparam [2:0] F3_HU = 3'b101;  // LHU

    reg         clk;
    reg  [31:0] addr;
    reg  [31:0] store_data;
    reg  [2:0]  funct3;
    reg         mem_read;
    reg         mem_write;
    wire [31:0] load_data;
    wire        misaligned;

    integer pass_count = 0;
    integer fail_count = 0;

    lsu_top dut (
        .clk        (clk),
        .addr       (addr),
        .store_data (store_data),
        .funct3     (funct3),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .load_data  (load_data),
        .misaligned (misaligned)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 10 ns clock

    // Record one check result.
    task report(input ok, input [8*48-1:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (ok) begin
                $display("PASS  %0s : %h", name, got);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL  %0s : got %h, expected %h", name, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Perform one store: drive inputs on the falling edge, write on the
    // following rising edge. Also checks the misaligned flag.
    task store(input [2:0] f3, input [31:0] a, input [31:0] data,
               input exp_misaligned, input [8*48-1:0] name);
        begin
            @(negedge clk);
            funct3 = f3; addr = a; store_data = data;
            mem_write = 1'b1; mem_read = 1'b0;
            #1;
            report(misaligned === exp_misaligned, name, {31'b0, misaligned}, {31'b0, exp_misaligned});
            @(posedge clk);
            @(negedge clk);
            mem_write = 1'b0;
        end
    endtask

    // Perform one load (combinational read) and compare the result.
    task load(input [2:0] f3, input [31:0] a, input [31:0] expected,
              input [8*48-1:0] name);
        begin
            @(negedge clk);
            funct3 = f3; addr = a; mem_read = 1'b1; mem_write = 1'b0;
            #1;
            report(load_data === expected && misaligned === 1'b0, name, load_data, expected);
            mem_read = 1'b0;
        end
    endtask

    // Check only the misaligned flag for a load address.
    task load_misaligned(input [2:0] f3, input [31:0] a, input [8*48-1:0] name);
        begin
            @(negedge clk);
            funct3 = f3; addr = a; mem_read = 1'b1; mem_write = 1'b0;
            #1;
            report(misaligned === 1'b1, name, {31'b0, misaligned}, 32'h1);
            mem_read = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_lsu_top.vcd");
        $dumpvars(0, tb_lsu_top);

        addr = 0; store_data = 0; funct3 = 0; mem_read = 0; mem_write = 0;

        // ---------------------------------------------------------------
        $display("\n--- 1. SW then load back with every load type ---");
        // Memory at 0x40 holds bytes (low->high): EF BE AD DE
        store(F3_W,  32'h40, 32'hDEAD_BEEF, 1'b0, "SW  0xDEADBEEF @0x40");
        load (F3_W,  32'h40, 32'hDEAD_BEEF,       "LW  @0x40");
        load (F3_B,  32'h40, 32'hFFFF_FFEF,       "LB  @0x40 (EF, sign-ext)");
        load (F3_B,  32'h41, 32'hFFFF_FFBE,       "LB  @0x41 (BE, sign-ext)");
        load (F3_B,  32'h42, 32'hFFFF_FFAD,       "LB  @0x42 (AD, sign-ext)");
        load (F3_B,  32'h43, 32'hFFFF_FFDE,       "LB  @0x43 (DE, sign-ext)");
        load (F3_BU, 32'h40, 32'h0000_00EF,       "LBU @0x40 (EF, zero-ext)");
        load (F3_BU, 32'h43, 32'h0000_00DE,       "LBU @0x43 (DE, zero-ext)");
        load (F3_H,  32'h40, 32'hFFFF_BEEF,       "LH  @0x40 (BEEF, sign-ext)");
        load (F3_H,  32'h42, 32'hFFFF_DEAD,       "LH  @0x42 (DEAD, sign-ext)");
        load (F3_HU, 32'h40, 32'h0000_BEEF,       "LHU @0x40 (BEEF, zero-ext)");
        load (F3_HU, 32'h42, 32'h0000_DEAD,       "LHU @0x42 (DEAD, zero-ext)");

        // ---------------------------------------------------------------
        $display("\n--- 2. Positive values: sign extension must add zeros ---");
        store(F3_W,  32'h50, 32'h1234_5678, 1'b0, "SW  0x12345678 @0x50");
        load (F3_B,  32'h50, 32'h0000_0078,       "LB  @0x50 (78, positive)");
        load (F3_H,  32'h52, 32'h0000_1234,       "LH  @0x52 (1234, positive)");

        // ---------------------------------------------------------------
        $display("\n--- 3. SB / SH round trips (neighbours unchanged) ---");
        store(F3_B,  32'h51, 32'h0000_0080, 1'b0, "SB  0x80 @0x51");
        load (F3_B,  32'h51, 32'hFFFF_FF80,       "LB  @0x51 (80, sign-ext)");
        load (F3_BU, 32'h51, 32'h0000_0080,       "LBU @0x51 (80, zero-ext)");
        load (F3_W,  32'h50, 32'h1234_8078,       "LW  @0x50 (only byte 1 changed)");
        store(F3_H,  32'h52, 32'h0000_ABCD, 1'b0, "SH  0xABCD @0x52");
        load (F3_HU, 32'h52, 32'h0000_ABCD,       "LHU @0x52");
        load (F3_W,  32'h50, 32'hABCD_8078,       "LW  @0x50 (upper half changed)");

        // ---------------------------------------------------------------
        $display("\n--- 4. Misaligned stores: flagged, memory unchanged ---");
        store(F3_W,  32'h41, 32'hFFFF_FFFF, 1'b1, "SW  @0x41 flagged");
        store(F3_W,  32'h42, 32'hFFFF_FFFF, 1'b1, "SW  @0x42 flagged");
        store(F3_H,  32'h41, 32'hFFFF_FFFF, 1'b1, "SH  @0x41 flagged");
        store(F3_H,  32'h43, 32'hFFFF_FFFF, 1'b1, "SH  @0x43 flagged");
        load (F3_W,  32'h40, 32'hDEAD_BEEF,       "LW  @0x40 unchanged");

        // ---------------------------------------------------------------
        $display("\n--- 5. Misaligned loads are flagged ---");
        load_misaligned(F3_H,  32'h41, "LH  @0x41 flagged");
        load_misaligned(F3_HU, 32'h43, "LHU @0x43 flagged");
        load_misaligned(F3_W,  32'h42, "LW  @0x42 flagged");

        $display("\n=========================================");
        $display(" RESULTS: %0d passed, %0d failed", pass_count, fail_count);
        $display("=========================================\n");
        $finish;
    end

endmodule
