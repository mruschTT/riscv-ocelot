// See LICENSE.TT for license details.
module opacc #(parameter
   nregs=2,
   vl=4,
   ml=4,
//    kl=4, //TODO: add kl>1
   XLEN=64)(
    input clk,
    input reset,
    input ab_valid,
    input ci_valid,
    input [$clog2(nregs)-1:0] ab_addr,
    input [$clog2(nregs)-1:0] ci_addr,
    input [$clog2(nregs)-1:0] co_addr,
    input [ml-1:0][XLEN-1:0] ai,
    input [vl-1:0][XLEN-1:0] bi,
    input [vl-1:0][XLEN-1:0] ci,
    output logic [vl-1:0][XLEN-1:0] co
    );
    integer i, j;
    logic [nregs-1:0][ml-1:0][XLEN-1:0] reg_a;
    logic [nregs-1:0][vl-1:0][XLEN-1:0] reg_b;
    logic [nregs-1:0][ml-1:0][vl-1:0][XLEN-1:0] reg_c;
    logic [ml-1:0][vl-1:0][XLEN-1:0] c_opacc_ab;
   
    always @(posedge clk) begin
        if (reset) 
            reg_a <= 0;
            reg_b <= 0;
            reg_c <= 0;
        else begin
            reg_a <= reg_a;
            reg_b <= reg_b;
            reg_c <= reg_c;
            if (c_valid) begin
                reg_c[ci_addr][0] <= ci;
                for(i=1; i<ml; i++) begin
                    reg_c[ci_addr][i] <= reg_c[ci_addr][i-1];
                end
            end
            if (op_valid) begin        
                reg_c[ab_addr] <= c_opacc_ab;
            end
        end
    end   

    always @* begin
        co = reg_c[co_addr][ml-1];
        for(i=0; i<ml; i++) begin
            for(j=0; j<vl; j++) begin
                c_opacc_ab[i][j] =  reg_c[ab_addr][i][j] 
                                    + reg_a[ab_addr][i]*reg_b[ab_addr][j];
            end
        end
    end

endmodule

