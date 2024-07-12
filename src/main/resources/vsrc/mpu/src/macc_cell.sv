// See LICENSE.TT for license details.
module opacc #(parameter
    nregs=2,
    XLEN=64)(
    input clk,
    input reset,
    input ab_valid,
    input ci_valid,
    input [XLEN-1:0] ai,
    input [XLEN-1:0] bj,
    input [$clog2(nregs)-1:0] cld_addr;
    input [$clog2(nregs)-1:0] cst_addr;
    input [$clog2(nregs)-1:0] ab_addr;
    input [XLEN-1:0] ci,
    output logic [XLEN-1:0] co
    );
    logic [nregs-1:0][XLEN-1:0] c_reg;
    logic [XLEN-1:0] c_opacc_ab;
   
    always @(posedge clk) begin
        if (reset) 
            c_reg <= 0;
        else begin
            c_reg <= c_reg;
            if (ci_valid) 
                c_reg[cld_addr] <= ci;
            if (ab_valid) begin
                assert(~ci_valid & ~(cld_addr==ab_addr));
                c_reg[ab_addr] <= c_opacc_ab;
            end
        end
    end

    assign c_macc_ab = ai*bj
    assign co = c_reg[cst_addr];

endmodule