// See LICENSE.TT for license details.
module tt_matrix_unit #(parameter
    LQ_DEPTH_LOG2=3,
    VLEN=256,
    MLEN=256,
    NUM_MREGS=2,
    XLEN=64)(
    input clk,
    input reset,
    input [31:0] inst,
    input [MLEN-1:0]  i_va,
    input [VLEN-1:0]  i_vb,
    input [VLEN-1:0]  i_vc,
    
    output o_vrf_rdaddr_0a,
    
    output o_mvex_lqvld,
    output [VLEN-1:0] o_mvex_lqdata,
    output o_mvex_lqexc,
    output [LQ_DEPTH_LOG2-1:0] o_mvex_lqid
    );
    localparam OPC_MATRIX = 0x0B
    localparam FUNC_OPACC = 0
    localparam FUNC_CIN = 1
    localparam FUNC_COUT = 2

    localparam ml = MLEN/XLEN;
    localparam vl = VLEN/XLEN;
//   localparam kl=4, //TODO: add kl>1

    logic [ml-1:0][XLEN-1:0] au;
    logic [vl-1:0][XLEN-1:0] bu;
    logic [vl-1:0][XLEN-1:0] cu;
    logic [vl-1:0][XLEN-1:0] o_vc;

   always_comb
     for(int i=0; i<vl-1; i++) begin
        au[i]   = i_va[(i+1)*XLEN-1:i*XLEN];
     end
   always_comb
     for(int i=0; i<vl-1; i++) begin
	    bu[i] = i_vb[(i+1)*XLEN-1:i*XLEN];
        cu[i] = i_vc[(i+1)*XLEN-1:i*XLEN];

        o_vc[(i+1)*XLEN-1:i*XLEN] = co[i];
     end
    assign o_mvex_lqdata = o_vc;

    wire [6:0] opcode = inst[6:0];
    wire [4:0] c_addr = inst[11:7];
    wire [4:0] a_addr = inst[19:15];
    wire [4:0] b_addr = inst[24:20];
    wire [2:0] funct3 = inst[14:12];
    // wire       vm     = inst[25]; // Only needed for V-Ext
    
    wire ab_valid = (opcode==OPC_MATRIX) & (funct3==FUNC_OPACC);
    wire ci_valid = (opcode==OPC_MATRIX) & (funct3==FUNC_CIN);
    wire co_valid = (opcode==OPC_MATRIX) & (funct3==FUNC_COUT);
    
    assign o_vrf_rdaddr_0a = {a_addr, b_addr, c_addr};

    always_ff @(posedge clk)
    //  if(vex_en_0a) begin
        o_vex_mem_lqid_1c               <= i_id_vec_autogen.ldqid;

  tt_opacc #(.VLEN(VLEN))
  opacc_i
  (
    .i_clk               (clk),
    .i_reset_n           (reset_n),
    // Outputs
    .o_rddata_0a         ({vrf_p2_rddata,vrf_p1_rddata,vrf_p0_rddata}),
   
    .ab_valid(ab_valid),
    .ci_valid(ci_valid),
    
    .ab_addr(ab_addr),
    .ci_addr(ci_addr),
    .co_addr(co_addr),
    .ai(au),
    .bi(bu),
    .ci(cu),
    .co(co)
  )
endmodule

