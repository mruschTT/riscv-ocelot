// See LICENSE.TT for license details.
module opacc #(parameter
   nregs=2,
   vl=4,
   ml=4,
   XLEN=64)(
    input clk,
    input reset,
    input ab_valid,
    input c_valid,
    input [$clog2(nregs)-1:0] ci_addr,
    input [$clog2(nregs)-1:0] ab_addr,
    input [ml-1:0][XLEN-1:0] ai,
    input [vl-1:0][XLEN-1:0] bi,
    input [vl-1:0][XLEN-1:0] ci,
    output logic [vl-1:0][XLEN-1:0] co
    );
    integer i, j;
    logic [nregs-1:0][ml-1:0][vl-1:0][XLEN-1:0] reg_c;
    logic [ml-1:0][vl-1:0][XLEN-1:0] c_opacc_ab;
   
    always @(posedge clk) begin
        if (reset) 
            reg_c <= 0;
        else begin
            reg_c <= reg_c;
            if (c_valid) begin
                reg_c[ci_addr][0] <= ci;
                for(i=1; i<ml; i++) begin
                    reg_c[ci_addr][i] <= reg_c[ci_addr][i-1];
                end
            end
            if (ab_valid) begin        
                reg_c[ab_addr] <= c_opacc_ab;
            end
        end
    end

    always @* begin
        co = reg_c[ci_addr][ml-1];
        for(i=0; i<ml; i++) begin
            for(j=0; j<vl; j++) begin
                c_opacc_ab[i][j] =  reg_c[ab_addr][i][j] + ai[i]*bi[j];
            end
        end
    end

endmodule

