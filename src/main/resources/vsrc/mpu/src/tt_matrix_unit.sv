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
    
    output o_vrf_rden_0a,
    output o_vrf_rdaddr_0a,
    
    output o_mvex_lqvld,
    output [VLEN-1:0] o_mvex_lqdata,
    output o_mvex_lqexc,
    output [LQ_DEPTH_LOG2-1:0] o_mvex_lqid
    );
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
    wire [6:0] funct7 = inst[31:25];
    wire       vm     = inst[25]; // Only needed for V-Ext
    
    always_comb begin
        if (opcode == 0x0B) begin
        end
        else begin
            a_rden = 0;
            b_rden = 0;
            c_rden = 0;
    end

    assign o_vrf_rden_0a = {a_rden, b_rden, c_rden};
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
   
    .ab_valid,
    .c_valid,
    
    .op_addr,
    .ab_addr,
    .c_addr,
    .au,
    .bu,
    .cu,
    .co
  )
endmodule

