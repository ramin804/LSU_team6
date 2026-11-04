# LSU_team6

Load/Store Unit (MEM stage) for the IEEE SSCS RV32IM five-stage pipelined RISC-V CPU.
Team 6: Omar & Ramin.

## Files

| File | Owner | Purpose |
|---|---|---|
| `alignment_check.v` | Omar | Flags halfword/word accesses that are not aligned |
| `load_extract.v` | Omar | Selects the byte/halfword from the read word and sign/zero-extends it |
| `store_align.v` | Ramin | Shifts store data into byte lanes and builds the byte-enable mask |
| `data_memory.v` | Ramin | Simulation memory: combinational read, clocked byte-masked write |
| `lsu_top.v` | Shared | Wrapper connecting the four modules |
| `tb_omar.v` | Omar | Tests for load extraction and alignment |
| `tb_store_memory.v` | Ramin | Tests for stores and memory |
| `tb_lsu_top.v` | Shared | Integrated store → load round-trip tests |

## How the modules connect

```
EX/MEM → addr, store_data, funct3, mem_read, mem_write
           │
           ├─► alignment_check ─► misaligned ─┐
           │                                  ▼
           ├─────────────────────────────► store_align ─► mem_wdata, mem_wstrb
           │                                                     │
           └─────────────────────────────► data_memory ◄─────────┘
                                                │ mem_rdata
                                                ▼
                                           load_extract ─► load_data → MEM/WB
```

## Conventions

- 32-bit addresses and data, little-endian, four 8-bit byte lanes per word.
- `addr[1:0]` is the byte offset.
- `funct3`: `000` LB/SB, `001` LH/SH, `010` LW/SW, `100` LBU, `101` LHU.
- Misaligned accesses are flagged; misaligned stores are blocked (`mem_wstrb = 0000`).

## Running the tests

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/).

```sh
# Integrated test (all four modules)
iverilog -o tb_lsu_top alignment_check.v load_extract.v store_align.v data_memory.v lsu_top.v tb_lsu_top.v
vvp tb_lsu_top

# Store/memory tests
iverilog -o tb_store_memory store_align.v data_memory.v tb_store_memory.v
vvp tb_store_memory

# Load/alignment tests
iverilog -o tb_omar alignment_check.v load_extract.v tb_omar.v
vvp tb_omar
```

Each run writes a `.vcd` waveform file that can be opened in GTKWave or the WaveTrace VS Code extension.

Current status: integrated 30/30, store/memory 25/25, load/alignment 2191 checks passing.

## Open questions for the project lead

- Should memory reads be combinational (current model) or clocked?
- Is `mem_wstrb = 0000` acceptable as "no write", or is a separate write-enable wanted?
- Data memory size (currently 1024 words / 4 KB, set by the `ADDR_WIDTH` parameter).
- How should the CPU respond when `misaligned = 1` (trap/exception)? The LSU only reports it.
