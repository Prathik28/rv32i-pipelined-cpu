// Load-use hazard detection.
// A load in EX produces its data only at the end of MEM, so a dependent
// instruction in ID must wait one cycle (then the value is forwarded from WB).
module hazard_unit (
    input        idex_mem_read,
    input  [4:0] idex_rd,
    input  [4:0] id_rs1,   // 0 when the instruction does not use rs1
    input  [4:0] id_rs2,   // 0 when the instruction does not use rs2
    output       stall
);
    assign stall = idex_mem_read && idex_rd != 0 &&
                   (idex_rd == id_rs1 || idex_rd == id_rs2);
endmodule
