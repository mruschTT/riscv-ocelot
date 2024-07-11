// `define assert(condition, message) \
//         if (~condition) begin \
//             $display(message); \
//             $finish; \
//         end

module opacc_tb();

    parameter XLEN = 8;    
    parameter VLEN = 32;
    parameter MLEN = 32;
    parameter vl = VLEN/XLEN;
    parameter ml = MLEN/XLEN;

    logic clk;
    logic reset;
    logic ab_valid;
    logic c_valid;

    logic [vl-1:0][XLEN-1:0] vi_a;
    logic [vl-1:0][XLEN-1:0] vi_b;
    logic [vl-1:0][XLEN-1:0] vi_c;
    logic [vl-1:0][XLEN-1:0] vo_c;

    // Storage for output vectors
    integer ii, i, j, k;

    opacc #(.vl(vl), .ml(ml), .XLEN(XLEN)) opacc_inst (
        .clk(clk),
        .reset(reset),
        .ab_valid(ab_valid),
        .c_valid(c_valid),
        .vi_a(vi_a),
        .vi_b(vi_b),
        .vi_c(vi_c),
        .vo_c(vo_c)
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
        
        // assert property ( @(posedge clk) c_valid |-> c_in == ##1 opacc_inst.reg_c[0])
        //     else $display("C REG state incorrect");
        
        // Initialize inputs
        reset = 1;
        c_valid = 0;
        ab_valid = 0;
        vi_a = 0;
        vi_b = 0;
        vi_c = 0;

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
                vi_c[j] = i*j;
            end
            
            for (ii=0; ii<ml; ii++) begin
                for (j=0; j<vl; j++) 
                    $display("t=%d: regC[%d][%d]=%h",  $time, ii, j, opacc_inst.reg_c[ii][j]);
            end
            $display("t=%d: vi_c=%h",$time, vi_c);
            #10;
            
            assert(opacc_inst.reg_c[0] == vi_c)
                else begin
                    $display("t=%d: regC[%d]=%h =/= ", $time, i, opacc_inst.reg_c[i]);
                    $finish;
                end            
        end 

        for (i=0; i<ml; i++) begin
            for (j=0; j<vl; j++) begin
                assert(opacc_inst.reg_c[i][j] == (ml-i)*(j))
                    else begin
                        $display("regC[%d][%d]=%h =/= %h", i, j, opacc_inst.reg_c[i][j], (ml-i)*j);
                        $finish;
                    end
            end
        end
        // start a b in
        c_valid = 0;
        #10
        ab_valid = 1;
        for (k = 0; k < 4; k++) begin
            for (i = 0; i < ml; i++) vi_a[i] = i*k;
            for (j = 0; j < vl; j++) vi_b[j] = j*k;
            
            $display("time %d: va:%h",  $time, opacc_inst.vi_a);
            $display("time %d: vb:%h",  $time, opacc_inst.vi_b);
            for (i=0; i<ml; i++) 
                $display("time %d: C_reg[%d]:%h ", $time, i, opacc_inst.reg_c[i]);
            for (i=0; i<ml; i++) 
                $display("time %d: C_opacc_ab[%d]:%h ", $time, i,  opacc_inst.c_opacc_ab[i]);
            #10
            for (i=0; i<ml; i++) begin
                for (j=0; j<vl; j++) begin
                    assert(opacc_inst.c_opacc_ab[i][j] == (opacc_inst.reg_c[i][j]+vi_a[i]*vi_b[j]))
                        else begin 
                            $display("time %d: C_next[%d][%d]=%h =/= %h + %h*%h", $time, i, j, opacc_inst.c_opacc_ab[i][j], opacc_inst.reg_c[i][j], vi_a[i], vi_b[j]);
                            $finish;
                        end
                end
            end
        end

        $finish;
    end
endmodule