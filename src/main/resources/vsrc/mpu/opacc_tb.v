`define assert(condition, message) \
        if (~condition) begin \
            $display(message); \
            $finish; \
        end

module tb_fsm_shift_register();

    parameter XLEN = 64;    
    parameter VLEN = 128;
    parameter MLEN = 128;
    integer vl = VLEN/XLEN;
    integer ml = MLEN/XLEN;

    reg clk;
    reg reset;
    reg c_valid;
    reg ab_valid;
    wire en_ab;
    wire en_c;

    reg [XLEN-1:0] vi_a [0:vl-1];
    reg [XLEN-1:0] vi_b [0:vl-1];
    reg [XLEN-1:0] vi_c [0:vl-1];
    wire [XLEN-1:0] vo_c [0:vl-1];

    // Storage for output vectors
    reg [63:0] reg_c_inst [0:vl-1][0:ml-1];
    integer i, j, k;

    // Capture output vectors
    always @(posedge clk) begin
        if (done) begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < M; j = j + 1) begin
                    reg_c_inst[i][j] <= opacc_inst.reg_c[i][j];
                end
            end
        end
    end

    opacc #(.VLEN(VLEN), .MLEN(MLEN), .XLEN(XLEN)) opacc_inst (
        .clk(clk),
        .issng_a(1'b1),
        .issng_b(1'b1),
        .en_ab(en_ab),
        .en_c(en_c),
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
        for (i = 0; i < ml; i++) begin
            for (j = 0; j < M; j++) begin
                `assert(en_c==1 && en_ab==0, "Assertion failed: LOAD C FSM signals incorrect");
                vi_c[j] = i*j;
            end
            #10;
            for (j = 0; j < M; j++) begin
                `assert(opacc_inst.reg_c[i][j] == i*j, "Assertion failed: C REG state incorrect");
            end
        end

        // start a b in
        c_valid = 0;
        ab_valid = 1;
        #10;
        for (k = 0; i < 4; k++) begin
            for (i = 0; i < vl; i++) vi_a[i] = i*k;
            for (j = 0; j < ml; j++) vi_b[j] = j*k;
            #10
            for (i = 0; i < vl; i++) begin
                for (j = 0; j < ml; j++) begin
                    `assert(opacc_inst.reg_c[i][j] == reg_c_inst + i*j, "Assertion failed: OP C+=A*B incorrect");
                end
            end
        end
        // End simulation
        $finish;
    end
endmodule