// `define assert(condition, message) \
//         if (~condition) begin \
//             $display(message); \
//             $finish; \
//         end

module tb_fsm_shift_register();

    parameter XLEN = 64;    
    parameter VLEN = 128;
    parameter MLEN = 128;
    parameter vl = VLEN/XLEN;
    parameter ml = MLEN/XLEN;

    logic clk;
    logic reset;
    logic c_valid;
    logic ab_valid;
    logic en_ab;
    logic en_c;

    reg [vl-1:0][XLEN-1:0] vi_a;
    reg [vl-1:0][XLEN-1:0] vi_b;
    reg [vl-1:0][XLEN-1:0] vi_c;
    logic [vl-1:0][XLEN-1:0] vo_c;

    // Storage for output vectors
    reg [ml-1:0][vl-1:0][XLEN-1:0] reg_c_inst;
    integer i, j, k;

    opacc #(.vl(vl), .ml(ml), .XLEN(XLEN)) opacc_inst (
        .clk(clk),
        .ab_valid(en_ab),
        .c_valid(en_c),
        .vi_a(vi_a),
        .vi_b(vi_b),
        .vi_c(vi_c),
        .vo_c(vo_c)
    );

    // Instantiate the FSM controller module
    shift_fsm #(.ml(ml)) fsm_inst (
        .clk(clk),
        .reset(reset),
        .c_valid(c_valid),
        .ab_valid(ab_valid),
        .en_c(en_c),
        .en_ab(en_ab)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10 time units clock period
    end

    // Test sequence
    initial begin
        // Initialize inputs
        reset = 1;
        c_valid = 0;

        // Apply reset
        #10;
        reset = 0;
        
        // start c in
        #10;
        c_valid = 1;
        // Apply c inputs 
        #10
        c_valid = 0;
        for (i=0; i<ml; i++) begin
            for (j=0; j<vl; j++) begin
                assert(en_c==1 && en_ab==0)
                    else $error("Assertion failed: LOAD C FSM signals incorrect");
                vi_c[j] = i*j;
            end
            #10;
            for (j=0; j<vl; j++) begin
                assert(opacc_inst.reg_c[i][j] == i*j)
                    else $error("Assertion failed: C REG state incorrect");
            end
        end

        // start a b in
        c_valid = 0;
        ab_valid = 1;
        #10;
        for (k = 0; k < 4; k++) begin
            for (i = 0; i < ml; i++) vi_a[i] = i*k;
            for (j = 0; j < vl; j++) vi_b[j] = j*k;
            #10
            for (i=0; i<ml; i++) begin
                for (j=0; j<vl; j++) begin
                    assert(opacc_inst.reg_c[i][j] == reg_c_inst + i*j)
                        else $error("Assertion failed: OP C+=A*B incorrect");
                end
            end
        end

        $finish;
    end
endmodule