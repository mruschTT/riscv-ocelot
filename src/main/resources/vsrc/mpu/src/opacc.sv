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
    logic [nregs-1:0][ml-1:0][vl-1:0][XLEN-1:0] c_reg;
    logic [ml-1:0][vl-1:0][XLEN-1:0] c_opacc_ab;
   
    always @(posedge clk) begin
        if (reset) 
            c_reg <= 0;
        else begin
            c_reg <= c_reg;
            if (ci_valid) begin
                c_reg[cld_addr][0] <= ci;
                for(i=1; i<vl; i++) begin
                    c_reg[cld_addr][i] <= c_reg[cld_addr][i-1];
                end
            end
            if (co_valid) begin
                for(i=1; i<vl; i++) begin
                    c_reg[cst_addr][i] <= c_reg[cst_addr][i-1];
                end
            end
            if (ab_valid) begin        
                assert((~co_valid) & (~ci_valid));
                c_reg[ab_addr] <= c_opacc_ab;
            end
        end
    end

    always @* begin
        co = c_reg[cst_addr][ml-1];
        for(i=0; i<ml; i++) begin
            for(j=0; j<vl; j++) begin
                c_opacc_ab[i][j] =  c_reg[cab_addr][i][j] + ai[i]*bi[j];
            end
        end
    end

endmodule

