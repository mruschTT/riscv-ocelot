// See LICENSE.TT for license details.
module tt_vec_opacc #(parameter
   VLEN=256,
   MLEN=256,
   XLEN=64
)
int vl = VLEN/XLEN
int ml = MLEN/XLEN
int i
int j
(
    input clk,      
    input issng_a,
    input issng_b,
    input en_ab,
    input en_c,
    input [XLEN-1:0] vi_a [vl-1:0],
    input [XLEN-1:0] vi_b [vl-1:0],
    input [XLEN-1:0] vi_c [vl-1:0],
    output [XLEN-1:0] vo_c [vl-1:0],
    );
   
    logic [XLEN-1:0] opacc [vl-1:0][ml-1:0],
   
    always_ff @(posedge clk) begin
        if (en_c) begin
            vo_c <= opacc[ml-1]
            for(i=1; i<vl;i ++) begin
                opacc[j] <= opacc[j-1]
            end
            opacc[0] <= vi_c
        end
        else if (mulen) begin        
            for(i=0; i<vl;i++) begin
                for(j=0; i<vl;j++) begin
                    opacc[i][j] <= ({{issng_a && b_vi[i][XLEN-1]}, vi_b[i]} 
                                    * {{issng_b && a[j][XLEN-1]}, vi_a[j]})
                                    + {{(issng_a | issng_b)}, opacc[i][j]};
                end
            end
        end
    end
    
    endmodule

