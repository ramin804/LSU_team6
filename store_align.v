// =============================================================================
// Module:   store_align
// Project:  IEEE SSCS RV32IM CPU - Team 6 Load/Store Subsystem (LSU)
// Owner:    Ramin
//
// Function:
//   Prepares register data before it is written into memory. Memory is
//   organized as 32-bit words made of four 8-bit byte lanes (little-endian):
//
//        lane:     3          2          1          0
//        bits:  [31:24]    [23:16]    [15:8]     [7:0]
//        addr:   +3         +2         +1         +0
//
//   A store of a byte (SB) or halfword (SH) only covers part of a word, so
//   this module:
//     1. Shifts the store data into the byte lane(s) selected by the
//        address offset (addr[1:0]).
//     2. Generates a 4-bit byte-enable mask (mem_wstrb) so that the memory
//        writes ONLY the selected lane(s) and leaves the other bytes unchanged.
//     3. Blocks the write (mask = 0000) when the instruction is not a store
//        (mem_write = 0) or when Omar's alignment checker flags the address.
//
//   This module is purely combinational: the outputs change as soon as the
//   inputs change. The actual write happens in data_memory on the clock edge.
//
// Inputs:
//   store_data[31:0] : Register value to store (rs2). SB uses bits [7:0],
//                      SH uses bits [15:0], SW uses all 32 bits.
//   byte_offset[1:0] : Position inside the memory word (= addr[1:0]).
//   funct3[2:0]      : Store size. 000 = SB, 001 = SH, 010 = SW.
//   mem_write        : 1 when the current instruction is a store.
//   misaligned       : 1 when alignment_check reports a misaligned address.
//
// Outputs:
//   mem_wdata[31:0]  : Store data shifted into the correct byte lane(s).
//   mem_wstrb[3:0]   : Byte-enable mask; bit i = 1 means "write byte lane i".
// =============================================================================

`timescale 1ns/1ps

module store_align (
    input  wire [31:0] store_data,
    input  wire [1:0]  byte_offset,
    input  wire [2:0]  funct3,
    input  wire        mem_write,
    input  wire        misaligned,
    output reg  [31:0] mem_wdata,
    output reg  [3:0]  mem_wstrb
);

    // Store-size encodings (must match the shared funct3 table).
    localparam [2:0] F3_SB = 3'b000;
    localparam [2:0] F3_SH = 3'b001;
    localparam [2:0] F3_SW = 3'b010;

    // A write is only allowed for a real store to a correctly aligned address.
    wire write_allowed = mem_write & ~misaligned;

    always @(*) begin
        // Default: no bytes written, data bus driven to zero.
        // Defaults also prevent unintended latches in synthesis.
        mem_wdata = 32'b0;
        mem_wstrb = 4'b0000;

        case (funct3)
            // -----------------------------------------------------------------
            // SB: store one byte.
            // Move the low byte of the register into the lane picked by the
            // address. Each lane is 8 bits wide, so shift left by 8 * offset
            // (byte_offset concatenated with 3'b000 is the same as offset * 8).
            // Enable only that one lane: 0001 shifted left by the offset.
            //   offset 0 -> 0001, 1 -> 0010, 2 -> 0100, 3 -> 1000
            // -----------------------------------------------------------------
            F3_SB: begin
                mem_wdata = {24'b0, store_data[7:0]} << {byte_offset, 3'b000};
                mem_wstrb = 4'b0001 << byte_offset;
            end

            // -----------------------------------------------------------------
            // SH: store one halfword (two bytes).
            // A halfword is aligned only at offset 0 (lanes 0-1) or offset 2
            // (lanes 2-3), so offset[1] picks the lower or upper half of the
            // word. Enable the two lanes that the halfword covers.
            //   offset 0 -> 0011, offset 2 -> 1100
            // Odd offsets are misaligned; those writes are blocked below.
            // -----------------------------------------------------------------
            F3_SH: begin
                mem_wdata = {16'b0, store_data[15:0]} << {byte_offset[1], 4'b0000};
                mem_wstrb = 4'b0011 << {byte_offset[1], 1'b0};
            end

            // -----------------------------------------------------------------
            // SW: store a full word.
            // The word already fills all four lanes, so no shifting is needed.
            // Enable every lane.
            // -----------------------------------------------------------------
            F3_SW: begin
                mem_wdata = store_data;
                mem_wstrb = 4'b1111;
            end

            // Any other funct3 value is not a valid store: write nothing.
            default: begin
                mem_wdata = 32'b0;
                mem_wstrb = 4'b0000;
            end
        endcase

        // Prevent memory writes when this is not a store or when the address
        // is misaligned. Clearing the byte enables means memory stays unchanged.
        if (!write_allowed) begin
            mem_wstrb = 4'b0000;
        end
    end

endmodule
