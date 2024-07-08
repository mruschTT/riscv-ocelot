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
    input [XLEN-1:0] vi_a [vl-1:0],
    input [XLEN-1:0] vi_b [vl-1:0],
    input [XLEN-1:0] vi_c [vl-1:0],
    output [XLEN-1:0] vo_c [vl-1:0]
    );
    integer i, j;
    reg [XLEN-1:0] reg_c [vl-1:0][ml-1:0];
   
    always @(posedge clk) begin
        if (en_c) begin
            vo_c <= reg_c[ml-1];
            for(i=1; i<vl; i++) begin
                reg_c[j] <= reg_c[j-1];
            end
            reg_c[0] <= vi_c;
        end
        else if (en_ab) begin        
            for(i=0; i<vl; i++) begin
                for(j=0; i<vl; j++) begin
                    reg_c[i][j] <= ({{issng_a && b_vi[i][XLEN-1]}, vi_b[i]} 
                                    * {{issng_b && a[j][XLEN-1]}, vi_a[j]})
                                    + {{(issng_a | issng_b)}, reg_c[i][j]};
                end
            end
        end
    end

endmodule

