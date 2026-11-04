`timescale 1ns/1ps
// Omar - Load extraction for a 32-bit, little-endian memory interface.
// mem_rdata: complete aligned memory word containing the requested byte.
// byte_offset: addr[1:0], the byte's position within that word.
// funct3: load instruction code; load_data: formatted 32-bit result.
// Combinational hardware: no clock or stored state is needed here.
// The caller must reject misaligned accesses and illegal instructions.
module load_extract (
    input  wire [31:0] mem_rdata,
    input  wire [1:0]  byte_offset,
    input  wire [2:0]  funct3,
    output reg  [31:0] load_data
);
    reg [7:0] selected_byte;
    reg [15:0] selected_halfword;

    always @(*) begin
        // In little-endian order, offset zero selects the lowest eight bits.
        case (byte_offset)
            2'b00: selected_byte = mem_rdata[7:0];
            2'b01: selected_byte = mem_rdata[15:8];
            2'b10: selected_byte = mem_rdata[23:16];
            2'b11: selected_byte = mem_rdata[31:24];
            default: selected_byte = 8'b0;
        endcase

        // Aligned halfwords start only at offset 0 or 2.
        // Bit 1 chooses the lower or upper half of the returned word.
        selected_halfword = byte_offset[1] ? mem_rdata[31:16]
                                                : mem_rdata[15:0];

        // Assign every output on every path so no memory (latch) is inferred.
        load_data = 32'b0;
        case (funct3)
            // LB: copy the sign bit into the extra 24 positions.
            3'b000: load_data = {{24{selected_byte[7]}}, selected_byte};
            // LH: copy the sign bit into the extra 16 positions.
            3'b001: load_data = {{16{selected_halfword[15]}}, selected_halfword};
            // LW: the entire word is already 32 bits wide.
            3'b010: load_data = mem_rdata;
            // LBU and LHU: fill the extra positions with zeros.
            3'b100: load_data = {24'b0, selected_byte};
            3'b101: load_data = {16'b0, selected_halfword};
            // Deterministic fallback, not an illegal-instruction detector.
            default: load_data = 32'b0;
        endcase
    end
endmodule
