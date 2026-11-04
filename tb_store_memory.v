// =============================================================================
// Testbench: tb_store_memory
// Project:   IEEE SSCS RV32IM CPU - Team 6 Load/Store Subsystem (LSU)
// Owner:     Ramin
//
// Tests store_align + data_memory together:
//   1. Byte writes (SB) to each of the four lanes.
//   2. Halfword writes (SH) to both valid positions.
//   3. Full-word writes (SW).
//   4. Unselected bytes stay unchanged after SB / SH.
//   5. No write when mem_write = 0 or when the address is misaligned.
//
// The `misaligned` signal normally comes from Omar's alignment_check module.
// So this testbench can run on its own, it drives `misaligned` directly
// using the same rules (halfword: addr[0] = 0, word: addr[1:0] = 00).
// During integration, lsu_top.v will connect the real module instead.
//
// Run:
//   iverilog -o tb_store_memory store_align.v data_memory.v tb_store_memory.v
//   vvp tb_store_memory
//   gtkwave tb_store_memory.vcd
// =============================================================================

`timescale 1ns/1ps

module tb_store_memory;

    localparam [2:0] F3_SB = 3'b000;
    localparam [2:0] F3_SH = 3'b001;
    localparam [2:0] F3_SW = 3'b010;

    // ---------------- Signals ----------------
    reg         clk;
    reg  [31:0] addr;
    reg  [31:0] store_data;
    reg  [2:0]  funct3;
    reg         mem_write;
    reg         mem_read;
    reg         misaligned;

    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;

    integer pass_count = 0;
    integer fail_count = 0;

    // ---------------- Devices under test ----------------
    store_align u_store_align (
        .store_data  (store_data),
        .byte_offset (addr[1:0]),
        .funct3      (funct3),
        .mem_write   (mem_write),
        .misaligned  (misaligned),
        .mem_wdata   (mem_wdata),
        .mem_wstrb   (mem_wstrb)
    );

    data_memory u_data_memory (
        .clk       (clk),
        .addr      (addr),
        .mem_read  (mem_read),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata)
    );

    // 10 ns clock period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Stand-in for Omar's alignment_check (same rules as the shared doc).
    always @(*) begin
        case (funct3)
            F3_SH, 3'b101: misaligned = addr[0];
            F3_SW:         misaligned = (addr[1:0] != 2'b00);
            default:       misaligned = 1'b0;
        endcase
    end

    // ---------------- Helper tasks ----------------

    // Issue one store: set up inputs, check store_align outputs,
    // then let one rising clock edge perform the write.
    task do_store(input [2:0] f3, input [31:0] a, input [31:0] data, input we,
                  input [31:0] exp_wdata, input [3:0] exp_wstrb, input [8*40-1:0] name);
        begin
            @(negedge clk);
            funct3 = f3; addr = a; store_data = data; mem_write = we; mem_read = 1'b0;
            #1;
            if (mem_wstrb !== exp_wstrb || (exp_wstrb != 4'b0000 && mem_wdata !== exp_wdata)) begin
                $display("FAIL  %0s : wdata=%h wstrb=%b (expected wdata=%h wstrb=%b)",
                         name, mem_wdata, mem_wstrb, exp_wdata, exp_wstrb);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS  %0s : wdata=%h wstrb=%b", name, mem_wdata, mem_wstrb);
                pass_count = pass_count + 1;
            end
            @(posedge clk);   // write happens here
            @(negedge clk);
            mem_write = 1'b0;
        end
    endtask

    // Read the word at address `a` and compare with the expected value.
    task check_word(input [31:0] a, input [31:0] expected, input [8*40-1:0] name);
        begin
            @(negedge clk);
            mem_write = 1'b0; mem_read = 1'b1; funct3 = F3_SW; addr = a;
            #1;
            if (mem_rdata !== expected) begin
                $display("FAIL  %0s : mem[%h]=%h (expected %h)", name, a, mem_rdata, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS  %0s : mem[%h]=%h", name, a, mem_rdata);
                pass_count = pass_count + 1;
            end
            mem_read = 1'b0;
        end
    endtask

    // ---------------- Test sequence ----------------
    initial begin
        $dumpfile("tb_store_memory.vcd");
        $dumpvars(0, tb_store_memory);

        addr = 0; store_data = 0; funct3 = 0; mem_write = 0; mem_read = 0;

        $display("\n--- 1. SW: full-word write ---");
        do_store(F3_SW, 32'h0000_0000, 32'hDEAD_BEEF, 1, 32'hDEAD_BEEF, 4'b1111, "SW  addr 0x00");
        check_word(32'h0000_0000, 32'hDEAD_BEEF, "SW  readback");

        $display("\n--- 2. SB: byte writes to each lane (other bytes unchanged) ---");
        // Pre-fill word at 0x10 with a known pattern so we can see untouched bytes.
        do_store(F3_SW, 32'h0000_0010, 32'h4433_2211, 1, 32'h4433_2211, 4'b1111, "SW  prefill 0x10");
        do_store(F3_SB, 32'h0000_0010, 32'hFFFF_FFAA, 1, 32'h0000_00AA, 4'b0001, "SB  lane 0 (0x10)");
        check_word(32'h0000_0010, 32'h4433_22AA, "SB  lane 0 readback");
        do_store(F3_SB, 32'h0000_0011, 32'hFFFF_FFBB, 1, 32'h0000_BB00, 4'b0010, "SB  lane 1 (0x11)");
        check_word(32'h0000_0010, 32'h4433_BBAA, "SB  lane 1 readback");
        do_store(F3_SB, 32'h0000_0012, 32'hFFFF_FFCC, 1, 32'h00CC_0000, 4'b0100, "SB  lane 2 (0x12)");
        check_word(32'h0000_0010, 32'h44CC_BBAA, "SB  lane 2 readback");
        do_store(F3_SB, 32'h0000_0013, 32'hFFFF_FFDD, 1, 32'hDD00_0000, 4'b1000, "SB  lane 3 (0x13)");
        check_word(32'h0000_0010, 32'hDDCC_BBAA, "SB  lane 3 readback");

        $display("\n--- 3. SH: halfword writes to valid positions ---");
        do_store(F3_SW, 32'h0000_0020, 32'h4433_2211, 1, 32'h4433_2211, 4'b1111, "SW  prefill 0x20");
        do_store(F3_SH, 32'h0000_0020, 32'hFFFF_BEEF, 1, 32'h0000_BEEF, 4'b0011, "SH  lower (0x20)");
        check_word(32'h0000_0020, 32'h4433_BEEF, "SH  lower readback");
        do_store(F3_SH, 32'h0000_0022, 32'hFFFF_CAFE, 1, 32'hCAFE_0000, 4'b1100, "SH  upper (0x22)");
        check_word(32'h0000_0020, 32'hCAFE_BEEF, "SH  upper readback");

        $display("\n--- 4. Blocked writes: memory must not change ---");
        do_store(F3_SW, 32'h0000_0030, 32'h1234_5678, 1, 32'h1234_5678, 4'b1111, "SW  prefill 0x30");
        do_store(F3_SW, 32'h0000_0030, 32'hFFFF_FFFF, 0, 32'h0,         4'b0000, "SW  mem_write=0");
        check_word(32'h0000_0030, 32'h1234_5678, "mem_write=0 no change");
        do_store(F3_SH, 32'h0000_0031, 32'hFFFF_FFFF, 1, 32'h0,         4'b0000, "SH  misaligned 0x31");
        do_store(F3_SH, 32'h0000_0033, 32'hFFFF_FFFF, 1, 32'h0,         4'b0000, "SH  misaligned 0x33");
        do_store(F3_SW, 32'h0000_0032, 32'hFFFF_FFFF, 1, 32'h0,         4'b0000, "SW  misaligned 0x32");
        do_store(F3_SW, 32'h0000_0031, 32'hFFFF_FFFF, 1, 32'h0,         4'b0000, "SW  misaligned 0x31");
        check_word(32'h0000_0030, 32'h1234_5678, "misaligned no change");

        $display("\n--- 5. mem_read = 0 returns zero ---");
        @(negedge clk); mem_read = 1'b0; addr = 32'h0000_0000; #1;
        if (mem_rdata === 32'b0) begin
            $display("PASS  mem_read=0 : mem_rdata=%h", mem_rdata); pass_count = pass_count + 1;
        end else begin
            $display("FAIL  mem_read=0 : mem_rdata=%h", mem_rdata); fail_count = fail_count + 1;
        end

        $display("\n=========================================");
        $display(" RESULTS: %0d passed, %0d failed", pass_count, fail_count);
        $display("=========================================\n");
        $finish;
    end

endmodule
