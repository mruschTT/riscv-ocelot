// `define assert(condition, message) \
//         if (~condition) begin \
//             $display(message); \
//             $finish; \
//         end

module opacc_tb();

    parameter NUM_MREGS = 2;    
    parameter XLEN = 8;    
    parameter VLEN = 32;
    parameter MLEN = 32;
    parameter vl = VLEN/XLEN;
    parameter ml = MLEN/XLEN;

    logic clk;
    logic reset;
    logic ab_valid;
    logic c_valid;

    logic [$clog2(NUM_MREGS)-1:0] ci_addr;
    logic [$clog2(NUM_MREGS)-1:0] co_addr;
    logic [$clog2(NUM_MREGS)-1:0] ab_addr;

    logic [vl-1:0][XLEN-1:0] ai;
    logic [vl-1:0][XLEN-1:0] bi;
    logic [vl-1:0][XLEN-1:0] ci;
    logic [vl-1:0][XLEN-1:0] co;

    // Storage for output vectors
    integer ii, i, j, k, n;

    opacc #(.NUM_MREGS(NUM_MREGS), .vl(vl), .ml(ml), .XLEN(XLEN)) opacc_inst (
        .clk(clk),
        .reset(reset),
        .ab_valid(ab_valid),
        .c_valid(c_valid),
        .ci_addr(ci_addr),
        // .co_addr(co_addr),
        .ab_addr(ab_addr),
        .ai(ai),
        .bi(bi),
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
        
        // assert property ( @(posedge clk) c_valid |-> c_in == ##1 opacc_inst.reg_c[ci_addr][0])
        //     else $display("C REG state incorrect");
        
        // Initialize inputs
        reset = 1;
        c_valid = 0;
        ab_valid = 0;
        ci_addr = 0;
        co_addr = 0;
        ab_addr = 0;
        ai = 0;
        bi = 0;
        ci = 0;

        // Apply reset
        #10;
        #10;
        reset = 0;
        
        // start c in
        #10;
        c_valid = 1;
        // Apply c inputs 
        #10
        $display("ml=%d", ml);
        for (i=0; i<ml+1; i++) begin
            $display("t=%d: i=%d",$time, i);
            for (j=0; j<vl; j++) begin
                ci[j] = i*j;
            end
            
            $display("t=%d: ci=%h",$time, ci);
            for (n=0; n<NUM_MREGS; n++) begin
                $display("n=%d", n);
                for (ii=0; ii<ml; ii++) 
                    $display("t=%d: regC[%d]=%h",  $time, ii, opacc_inst.reg_c[n][ii]);
            end
            $display("t=%d: co=%h",$time, co);
            #10;
            
            assert(opacc_inst.reg_c[ci_addr][0] == ci)
                else begin
                    $display("t=%d: regC[%d]=%h =/= ", $time, i, opacc_inst.reg_c[ci_addr][i]);
                    $finish;
                end            
        end 

        for (i=0; i<ml; i++) begin
            for (j=0; j<vl; j++) begin
                assert(opacc_inst.reg_c[ci_addr][i][j] == (ml-i)*(j))
                    else begin
                        $display("regC[%d][%d]=%h =/= %h", i, j, opacc_inst.reg_c[ci_addr][i][j], (ml-i)*j);
                        $finish;
                    end
            end
        end
        // start a b in
        c_valid = 0;
        #10
        ci_addr = 1;
        c_valid = 1;
        ab_valid = 1;
        for (k = 0; k < 4; k++) begin
            for (i = 0; i < ml; i++) ai[i] = i*k+1;
            for (j = 0; j < vl; j++) bi[j] = j*k+2;
            for (j = 0; j < vl; j++) ci[j] = k;
            
            $display("time %d: va:%h",  $time, opacc_inst.ai);
            $display("time %d: vb:%h",  $time, opacc_inst.bi);
            for (n=0; n<NUM_MREGS; n++) begin
                $display("n=%d", n);
                for (i=0; i<ml; i++) 
                    $display("time %d: C_reg[%d]:%h ", $time, i, opacc_inst.reg_c[n][i]);
            end
            for (i=0; i<ml; i++) 
                $display("time %d: C_opacc_ab[%d]:%h ", $time, i,  opacc_inst.c_opacc_ab[i]);
            #10
            for (i=0; i<ml; i++) begin
                for (j=0; j<vl; j++) begin
                    assert(opacc_inst.c_opacc_ab[i][j] == (opacc_inst.reg_c[ab_addr][i][j]+ai[i]*bi[j]))
                        else begin 
                            $display("time %d: C_next[%d][%d]=%h =/= %h + %h*%h", $time, i, j, opacc_inst.c_opacc_ab[i][j], opacc_inst.reg_c[ab_addr][i][j], ai[i], bi[j]);
                            $finish;
                        end
                end
            end
        end

        //read out
        c_valid = 0;
        ab_valid = 0;
        #10
        c_valid = 1;
        ci_addr = 1;
        for (i=0; i<ml+1; i++) begin
            $display("t=%d: i=%d",$time, i);
            ci = i;
            for (n=0; n<NUM_MREGS; n++) begin
                $display("n=%d", n);
                for (ii=0; ii<ml; ii++) 
                    $display("t=%d: regC[%d]=%h",  $time, ii, opacc_inst.reg_c[n][ii]);
            end
            $display("t=%d: co=%h",$time, co);
            #10;
            
            assert(opacc_inst.reg_c[ci_addr][ml-1] == co)
                else begin
                    $display("t=%d: regC[%d]=%h =/= ", $time, i, opacc_inst.reg_c[ci_addr][i]);
                    $finish;
                end            
        end 

        $finish;
    end
endmodule