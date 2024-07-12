// `define assert(condition, message) \
//         if (~condition) begin \
//             $display(message); \
//             $finish; \
//         end

module opacc_tb();

    parameter nregs = 2;
    parameter XLEN = 8;
    parameter VLEN = 32;
    parameter MLEN = 32;
    parameter vl = VLEN/XLEN;
    parameter ml = MLEN/XLEN;

    logic clk;
    logic reset;
    logic ab_valid;
    logic ci_valid;

    logic [$clog2(nregs)-1:0] cld_addr;
    logic [$clog2(nregs)-1:0] cst_addr;
    logic [$clog2(nregs)-1:0] ab_addr;

    logic [ml-1:0][XLEN-1:0] ai;
    logic [vl-1:0][XLEN-1:0] bj;
    logic [vl-1:0][XLEN-1:0] ci;
    logic [vl-1:0][XLEN-1:0] co;

    integer ii, i, j, k;
    // integer c_next;
    // integer c_reg;
        
    opacc #(.nregs(nregs), .vl(vl), .ml(ml), .XLEN(XLEN)) opacc_inst (
        .clk(clk),
        .reset(reset),
        .ab_valid(ab_valid),
        .ci_valid(ci_valid),
        .cld_addr(cld_addr),
        .cst_addr(cst_addr),
        .ab_addr(ab_addr),
        .ai(ai),
        .bj(bj),
        .ci(ci),
        .co(co)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10 time units clock period
    end

    // Test sequence
    initial begin
        $fsdbDumpfile("opacc_tb.fsdb");
        $fsdbDumpvars (0, opacc_tb);
        
        // assert property ( @(posedge clk) ci_valid |-> c_in == ##1 opacc_inst.cio[0])
        //     else $display("C REG state incorrect");
        
        // Initialize inputs
        reset = 1;
        ci_valid = 0;
        ab_valid = 0;
        ai = 0;
        bj = 0;
        ci = 0;

        // Apply reset
        #10;
        #10;
        reset = 0;
        
        // start c in
        #10;
        ci_valid = 1;
        // Apply c inputs 
        #10
        $display("ml=%d", ml);
        for (i=0; i<ml+1; i++) begin
            $display("t=%d: i=%d",$time, i);
            for (j=0; j<vl; j++) begin
                ci[j] = i*j;
            end
            
            for (ii=0; ii<ml; ii++) begin
                for (j=0; j<vl; j++) 
                    $display("t=%d: regC[%d][%d]=%h",  $time, ii, j, opacc_inst.cio[ii][j]);
            end
            $display("t=%d: ci=%h",$time, ci);
            #10;
            
            assert(opacc_inst.cio[0] == ci)
                else begin
                    $display("t=%d: regC[%d]=%h =/= ", $time, i, opacc_inst.cio[i]);
                    $finish;
                end            
        end 

        for (i=0; i<ml; i++) begin
            for (j=0; j<vl; j++) begin
                assert(opacc_inst.cio[i][j] == (ml-i)*(j))
                    else begin
                        $display("regC[%d][%d]=%h =/= %h", i, j, opacc_inst.cio[i][j], (ml-i)*j);
                        $finish;
                    end
            end
        end
        // start a b in
        ci_valid = 0;
        #10
        ab_valid = 1;
        for (k = 0; k < 4; k++) begin
            for (i = 0; i < ml; i++) ai[i] = i*k;
            for (j = 0; j < vl; j++) bj[j] = j*k;
            #10
            
            $display("time %d: va:%h",  $time, opacc_inst.ai);
            $display("time %d: vb:%h",  $time, opacc_inst.bj);
            // for (i=0; i<ml; i++) 
            //     $display("time %d: C_reg[%d]:%h ", $time, i, opacc_inst.cio[i]);
            // for (i=0; i<ml; i++) 
            //     $display("time %d: C_opacc_ab[%d]:%h ", $time, i,  opacc_inst.c_opacc_ab[i]);
            
            
            // for (i=0; i<ml; i++) begin
            //     for (j=0; j<vl; j++) begin
            //         c_next = opacc_inst.gen_i[i].gen_j[j].macc_inst.c_macc_ab;
            //         // c_reg = opacc_inst.gen_i[i].gen_j[j].macc_inst.creg[ab_addr]
            //         c_reg = opacc_inst.cio[i][j];
            //         assert(c_next == (c_reg+ai[i]*bj[j]))
            //             else begin 
            //                 $display("time %d: C_next[i=%d][j=%d][reg=%d]=%h =/= %h + %h*%h", $time, i, j, 
            //                     opacc_inst.gen_i[i].gen_j[j].macc_inst.ab_addr, 
            //                     opacc_inst.gen_i[i].gen_j[j].macc_inst.c_macc_ab, 
            //                     opacc_inst.gen_i[i].gen_j[j].macc_inst.creg[ab_addr], 
            //                     opacc_inst.cio[i][j], ai[i], bj[j]);
            //                 $finish;
            //             end
            //     end
            // end
        end
        $finish;
    end
endmodule