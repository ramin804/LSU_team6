// Simulation-only testbench. This file is not hardware for the processor.
`timescale 1ns/1ps
module tb_omar;
    reg [31:0] mem_rdata;
    reg [31:0] addr;
    reg [2:0] funct3;
    wire [31:0] load_data;
    wire misaligned;
    integer checks;
    integer offset;
    integer value;
    integer code;
    integer base_index;
    reg [31:0] base_addr;
    reg [31:0] pattern;
    reg [31:0] expected;
    reg expected_alignment;
    reg [15:0] half_value;

    load_extract loads (
        .mem_rdata(mem_rdata), .byte_offset(addr[1:0]),
        .funct3(funct3), .load_data(load_data)
    );
    alignment_check alignment (
        .addr(addr), .funct3(funct3), .misaligned(misaligned)
    );

    // Apply one load and compare its result with an independently supplied answer.
    task check_load;
        input [31:0] word_value;
        input [31:0] address_value;
        input [2:0] instruction;
        input [31:0] expected_value;
        begin
            mem_rdata = word_value;
            addr = address_value;
            funct3 = instruction;
            #1; // Allow combinational signals to settle in the simulator.
            checks = checks + 1;
            if (load_data !== expected_value || misaligned !== 1'b0) begin
                $display("FAIL load: word=%h addr=%h funct3=%b got=%h expected=%h misaligned=%b",
                         mem_rdata, addr, funct3, load_data, expected_value, misaligned);
                $fatal(1, "Load check failed");
            end
        end
    endtask

    initial begin
        checks = 0;
        mem_rdata = 0;
        addr = 0;
        funct3 = 0;
        $dumpfile("omar_tests.vcd");
        $dumpvars(0, tb_omar);

        // Easy-to-follow examples: bytes in address order are 01, 7F, FF, 80.
        check_load(32'h80FF7F01, 32'h1000, 3'b000, 32'h00000001);
        check_load(32'h80FF7F01, 32'h1001, 3'b000, 32'h0000007F);
        check_load(32'h80FF7F01, 32'h1002, 3'b000, 32'hFFFFFFFF);
        check_load(32'h80FF7F01, 32'h1003, 3'b000, 32'hFFFFFF80);
        check_load(32'h80FF7F01, 32'h1002, 3'b100, 32'h000000FF);
        check_load(32'h80FF7F01, 32'h1003, 3'b100, 32'h00000080);
        check_load(32'h80FF7F01, 32'h1000, 3'b001, 32'h00007F01);
        check_load(32'h80FF7F01, 32'h1002, 3'b001, 32'hFFFF80FF);
        check_load(32'h80FF7F01, 32'h1002, 3'b101, 32'h000080FF);
        check_load(32'h80FF7F01, 32'h1000, 3'b010, 32'h80FF7F01);
        check_load(32'h00000000, 32'h1000, 3'b010, 32'h00000000);
        check_load(32'hFFFFFFFF, 32'h1000, 3'b010, 32'hFFFFFFFF);

        // Every possible byte, in every lane, both signed and unsigned.
        // Other lanes contain unrelated bits to expose incorrect selection.
        for (offset = 0; offset < 4; offset = offset + 1) begin
            for (value = 0; value < 256; value = value + 1) begin
                pattern = (32'hA55AC33C & ~(32'hFF << (offset * 8)))
                          | (value << (offset * 8));
                expected = (value < 128) ? value : (32'hFFFFFF00 + value);
                check_load(pattern, 32'h1000 + offset, 3'b000, expected);
                check_load(pattern, 32'h1000 + offset, 3'b100, value);
            end
        end

        // Halfword boundary values at both valid offsets.
        for (value = 0; value < 8; value = value + 1) begin
            case (value)
                0: half_value = 16'h0000;
                1: half_value = 16'h0001;
                2: half_value = 16'h007F;
                3: half_value = 16'h00FF;
                4: half_value = 16'h7FFF;
                5: half_value = 16'h8000;
                6: half_value = 16'h80FF;
                7: half_value = 16'hFFFF;
            endcase
            expected = (half_value < 32768) ? {16'b0, half_value}
                                           : (32'hFFFF0000 + half_value);
            check_load({16'h1234, half_value}, 32'h1000, 3'b001, expected);
            check_load({half_value, 16'h5678}, 32'h1002, 3'b001, expected);
            check_load({16'h1234, half_value}, 32'h1000, 3'b101, {16'b0, half_value});
            check_load({half_value, 16'h5678}, 32'h1002, 3'b101, {16'b0, half_value});
        end

        // All size codes and all offsets, at low, ordinary, and high addresses.
        // Modulo arithmetic is an independent reference for the bit checks.
        for (base_index = 0; base_index < 3; base_index = base_index + 1) begin
            case (base_index)
                0: base_addr = 32'h00000000;
                1: base_addr = 32'h00001000;
                2: base_addr = 32'hFFFFFFFC;
            endcase
            for (code = 0; code < 8; code = code + 1) begin
                for (offset = 0; offset < 4; offset = offset + 1) begin
                    addr = base_addr + offset;
                    funct3 = code;
                    case (code)
                        1, 5: expected_alignment = ((addr % 2) != 0);
                        2: expected_alignment = ((addr % 4) != 0);
                        default: expected_alignment = 1'b0;
                    endcase
                    #1;
                    checks = checks + 1;
                    if (misaligned !== expected_alignment) begin
                        $display("FAIL alignment: addr=%h funct3=%b got=%b expected=%b",
                                 addr, funct3, misaligned, expected_alignment);
                        $fatal(1, "Alignment check failed");
                    end
                end
            end
        end

        // Reserved funct3 values give the documented zero fallback.
        check_load(32'hFFFFFFFF, 32'h1000, 3'b011, 32'b0);
        check_load(32'hFFFFFFFF, 32'h1000, 3'b110, 32'b0);
        check_load(32'hFFFFFFFF, 32'h1000, 3'b111, 32'b0);
        $display("PASS: %0d checks completed.", checks);
        $finish;
    end
endmodule
