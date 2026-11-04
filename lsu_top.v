// =============================================================================
// Module:   lsu_top
// Project:  IEEE SSCS RV32IM CPU - Team 6 Load/Store Subsystem (LSU)
// Owners:   Omar & Ramin (shared)
//
// Function:
//   Top-level wrapper for the MEM stage. It contains no logic of its own;
//   it only creates the four LSU modules and wires them together:
//
//     alignment_check (Omar) : is the address legal for this access size?
//     store_align     (Ramin): shift store data into lanes, make byte enables
//     data_memory     (Ramin): the memory itself (comb. read, clocked write)
//     load_extract    (Omar) : pick the byte/halfword out of the read word
//                              and sign/zero-extend it to 32 bits
//
//   Inputs come from the EX/MEM pipeline register; outputs go toward the
//   MEM/WB pipeline register. The pipeline registers are NOT built here.
//
// Inputs (from EX/MEM):
//   clk              : Clock (memory writes happen on the rising edge).
//   addr[31:0]       : Byte address computed by the ALU (rs1 + offset).
//   store_data[31:0] : Value to store (rs2). Ignored for loads.
//   funct3[2:0]      : Access size / signedness (shared encoding table).
//   mem_read         : 1 for load instructions.
//   mem_write        : 1 for store instructions.
//
// Outputs (toward MEM/WB):
//   load_data[31:0]  : Final 32-bit load result for the destination register.
//   misaligned       : 1 if the access is misaligned. Stores are already
//                      blocked internally; how the CPU reacts to a misaligned
//                      access (trap/exception) is still to be confirmed
//                      with the project lead.
// =============================================================================

`timescale 1ns/1ps

module lsu_top (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] store_data,
    input  wire [2:0]  funct3,
    input  wire        mem_read,
    input  wire        mem_write,
    output wire [31:0] load_data,
    output wire        misaligned
);

    // -------------------------------------------------------------------------
    // Internal wires: these carry signals BETWEEN the four modules.
    // -------------------------------------------------------------------------
    wire [31:0] mem_wdata;   // store_align -> data_memory : positioned store data
    wire [3:0]  mem_wstrb;   // store_align -> data_memory : which bytes to write
    wire [31:0] mem_rdata;   // data_memory -> load_extract: full word read

    // The lowest two address bits select the byte inside a 32-bit word.
    wire [1:0]  byte_offset = addr[1:0];

    // -------------------------------------------------------------------------
    // 1. Alignment check (Omar): flag halfword/word accesses that straddle
    //    a word boundary.
    // -------------------------------------------------------------------------
    alignment_check u_alignment_check (
        .addr       (addr),
        .funct3     (funct3),
        .misaligned (misaligned)
    );

    // -------------------------------------------------------------------------
    // 2. Store alignment (Ramin): move store data into the right byte lanes
    //    and build the byte-enable mask. A misaligned store or a non-store
    //    produces mem_wstrb = 0000, so memory cannot change.
    // -------------------------------------------------------------------------
    store_align u_store_align (
        .store_data  (store_data),
        .byte_offset (byte_offset),
        .funct3      (funct3),
        .mem_write   (mem_write),
        .misaligned  (misaligned),
        .mem_wdata   (mem_wdata),
        .mem_wstrb   (mem_wstrb)
    );

    // -------------------------------------------------------------------------
    // 3. Data memory (Ramin): write the enabled bytes on the clock edge and
    //    return the whole addressed word for loads.
    // -------------------------------------------------------------------------
    data_memory u_data_memory (
        .clk       (clk),
        .addr      (addr),
        .mem_read  (mem_read),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata)
    );

    // -------------------------------------------------------------------------
    // 4. Load extraction (Omar): select the requested byte/halfword from the
    //    read word and sign- or zero-extend it to 32 bits.
    // -------------------------------------------------------------------------
    load_extract u_load_extract (
        .mem_rdata   (mem_rdata),
        .byte_offset (byte_offset),
        .funct3      (funct3),
        .load_data   (load_data)
    );

endmodule
