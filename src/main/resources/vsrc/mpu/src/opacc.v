// See LICENSE.TT for license details.
module opacc #(parameter
   vl=4,
   ml=4,
   XLEN=64)(
    input clk,      
    input issng_a,
    input issng_b,
    input en_ab,
    input en_c,
    input [vl-1:0][XLEN-1:0] vi_a,
    input [vl-1:0][XLEN-1:0] vi_b,
    input [vl-1:0][XLEN-1:0] vi_c,
    output [vl-1:0][XLEN-1:0] vo_c
    );
    integer i, j;
    reg [ml-1:0][vl-1:0][XLEN-1:0] reg_c;
   
    always @(posedge clk) begin
        if (en_c) begin
            vo_c <= reg_c[ml-1];
            for(i=1; i<vl; i++) begin
                reg_c[j] <= reg_c[j-1];
            end
            reg_c[0] <= vi_c;
        end
        else if (en_ab) begin        
            for(i=0; i<ml; i++) begin
                for(j=0; j<vl; j++) begin
                    reg_c[i][j] <= vi_b[j] * vi_a[i] + reg_c[i][j];
                end
            end
        end
    end

endmodule

