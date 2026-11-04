`timescale 1ns/1ps
// Omar - Check address alignment for byte, halfword, and word accesses.
// addr: 32-bit byte address; funct3: access-size instruction code.
// misaligned: 1 means the address violates the requested size's alignment.
// The same size encodings serve loads and stores. No clock is required.
module alignment_check (
    input  wire [31:0] addr,
    input  wire [2:0]  funct3,
    output reg        misaligned
);
    always @(*) begin
        misaligned = 1'b0;
        case (funct3)
            // LB/LBU/SB: a single byte can start at any address.
            3'b000, 3'b100: misaligned = 1'b0;
            // LH/LHU/SH: an even address has a last binary digit of zero.
            3'b001, 3'b101: misaligned = addr[0];
            // LW/SW: a multiple of four ends in two binary zeros.
            3'b010: misaligned = (addr[1:0] != 2'b00);
            // Unknown opcodes must be handled by the instruction decoder.
            // This output reports alignment only, not instruction validity.
            default: misaligned = 1'b0;
        endcase
    end
endmodule
