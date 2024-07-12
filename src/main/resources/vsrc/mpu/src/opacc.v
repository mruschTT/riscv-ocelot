// See LICENSE.TT for license details.
module opacc #(parameter
    nregs=2;
    ml=4,
    vl=4,
    XLEN=64)(
    input clk,
    input reset,
    input ab_valid,
    input ci_valid,
    input co_valid,
    input [ml-1:0][XLEN-1:0] ai,
    input [vl-1:0][XLEN-1:0] bi,
    input [$clog2(nregs)-1:0] cld_addr;
    input [$clog2(nregs)-1:0] cst_addr;
    input [$clog2(nregs)-1:0] ab_addr;
    input [vl-1:0][XLEN-1:0] ci,
    output logic [vl-1:0][XLEN-1:0] co
    );
    integer i, j;
    logic [nregs-1:0][ml-1:0][vl-1:0][XLEN-1:0] cio;
    logic [ml-1:0][vl-1:0][XLEN-1:0] c_opacc_ab;
   
    assign cio[0] = ci;
    assign co = cio[ml-1];
    genvar i, j;
    generate
        for(i=0; i<ml; i++) begin
            for(j=0; j<vl; j++) begin
                macc_cell  #(.nregs(nregs) .XLEN(XLEN)) macc_inst (
                    .clk(clk),
                    .reset(reset),
                    .ab_valid(ab_valid),
                    .c_valid(c_valid),
                    .cld_addr(cld_addr),
                    .cst_addr(cst_addr),
                    .cab_addr(cab_addr),
                    .ai(ai[i]),
                    .bj(bj[j]),
                    .ci(cio[i]),
                    .co(cio[i+1])
                );
    endgenerate
endmodule

