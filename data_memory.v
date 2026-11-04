// =============================================================================
// Module:   data_memory
// Project:  IEEE SSCS RV32IM CPU - Team 6 Load/Store Subsystem (LSU)
// Owner:    Ramin
//
// Function:
//   Simple simulation data memory for the LSU. It stores 32-bit words, each
//   made of four 8-bit byte lanes (little-endian: lane 0 = bits [7:0] holds
//   the byte at the lowest address).
//
//   - Reads are COMBINATIONAL: the full 32-bit word containing `addr` appears
//     on mem_rdata in the same cycle. Omar's load_extract module then picks
//     out the byte/halfword it needs and sign/zero-extends it.
//   - Writes are CLOCKED: on the rising edge of clk, only the byte lanes
//     whose bit in mem_wstrb is 1 are updated. Lanes with a 0 keep their
//     old value, which is what makes SB and SH work without disturbing the
//     neighbouring bytes.
//
//   NOTE: This is an initial simulation model. Memory size, read timing
//   (combinational vs. clocked) and the final interface still need to be
//   confirmed with the project lead.
//
// Parameters:
//   ADDR_WIDTH : Number of word-address bits. Memory holds 2**ADDR_WIDTH
//                words (default 10 -> 1024 words = 4 KB).
//
// Inputs:
//   clk             : Clock; writes happen on its rising edge.
//   addr[31:0]      : Byte address. addr[1:0] is the byte offset (handled by
//                     store_align / load_extract), so the word index is
//                     addr[ADDR_WIDTH+1:2].
//   mem_read        : 1 when the current instruction is a load.
//   mem_wdata[31:0] : Write data, already shifted into lanes by store_align.
//   mem_wstrb[3:0]  : Byte-enable mask from store_align (0000 = no write).
//
// Output:
//   mem_rdata[31:0] : The 32-bit word at the addressed location (0 when
//                     mem_read is 0).
// =============================================================================

`timescale 1ns/1ps

module data_memory #(
    parameter ADDR_WIDTH = 10
) (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire        mem_read,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output wire [31:0] mem_rdata
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    // Storage: DEPTH words, each 32 bits wide.
    reg [31:0] mem [0:DEPTH-1];

    // Convert the byte address into a word index. The lowest two address
    // bits only choose a byte inside the word, so they are dropped here.
    wire [ADDR_WIDTH-1:0] word_index = addr[ADDR_WIDTH+1:2];

    // Start simulation with every word cleared to zero so reads of
    // never-written locations return a known value instead of X.
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'b0;
    end

    // -------------------------------------------------------------------------
    // Read: combinational. Return the whole word that contains `addr`.
    // Output zero when no load is happening so the bus is never undefined.
    // -------------------------------------------------------------------------
    assign mem_rdata = mem_read ? mem[word_index] : 32'b0;

    // -------------------------------------------------------------------------
    // Write: on the rising clock edge, update only the byte lanes selected by
    // mem_wstrb. Each lane is checked separately, so unselected bytes keep
    // their previous contents.
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (mem_wstrb[0]) mem[word_index][7:0]   <= mem_wdata[7:0];   // byte lane 0 (addr +0)
        if (mem_wstrb[1]) mem[word_index][15:8]  <= mem_wdata[15:8];  // byte lane 1 (addr +1)
        if (mem_wstrb[2]) mem[word_index][23:16] <= mem_wdata[23:16]; // byte lane 2 (addr +2)
        if (mem_wstrb[3]) mem[word_index][31:24] <= mem_wdata[31:24]; // byte lane 3 (addr +3)
    end

endmodule
