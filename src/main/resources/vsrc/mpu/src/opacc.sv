// See LICENSE.TT for license details.
module opacc #(parameter
   vl=4,
   ml=4,
   XLEN=64)(
    input clk,
    input reset,
    input ab_valid,
    input c_valid,
    input [ml-1:0][XLEN-1:0] vi_a,
    input [vl-1:0][XLEN-1:0] vi_b,
    input [vl-1:0][XLEN-1:0] vi_c,
    output logic [vl-1:0][XLEN-1:0] vo_c
    );
    integer i, j;
    logic [ml-1:0][vl-1:0][XLEN-1:0] reg_c;
    logic [ml-1:0][vl-1:0][XLEN-1:0] c_opacc_ab;
   
    always @(posedge clk) begin
        if (reset) 
            reg_c = 0;
        else if (c_valid) begin
            for(i=1; i<vl; i++) begin
                reg_c[i] <= reg_c[i-1];
            end
            reg_c[0] <= vi_c;
        end
        else if (ab_valid) begin        
            reg_c <= c_opacc_ab;
        end
        else reg_c <= reg_c;
    end

    always @* begin
        vo_c = reg_c[ml-1];
        for(i=0; i<ml; i++) begin
            for(j=0; j<vl; j++) begin
                c_opacc_ab[i][j] =  reg_c[i][j] + vi_a[i]*vi_b[j];
            end
        end
    end

endmodule

