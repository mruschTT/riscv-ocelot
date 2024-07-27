// See LICENSE.TT for license details.
// Open Vector Interface wrapper module for Ocelot
module tt_vpu_ovi #(parameter VLEN = 256)
(                 input  logic clk, reset_n,

                  input  logic [31:0] issue_inst,
                  input  logic [4:0]  issue_sb_id,
                  input  logic [63:0] issue_scalar_opnd,
                  input  logic [39:0] issue_vcsr,
                  input  logic        issue_vcsr_lmulb2, // Added 1 more bit for vlmul
                  input  logic        issue_valid,
                  output logic        issue_credit,

                  input  logic [4:0]  dispatch_sb_id,
                  input  logic        dispatch_next_senior,
                  input  logic        dispatch_kill,

                  output logic        completed_valid,
                  output logic [4:0]  completed_sb_id,
                  output logic [4:0]  completed_fflags,
                  output logic [63:0] completed_dest_reg,
                  output logic        completed_vxsat,
                  output logic [13:0] completed_vstart,
                  output logic        completed_illegal,

                  output logic         store_valid,
                  output logic [511:0] store_data,
                  input  logic         store_credit,

                  input  logic [33:0]  load_seq_id,
                  input  logic [511:0] load_data,
                  input  logic         load_valid,
                  input  logic [63:0]  load_mask,
                  input  logic         load_mask_valid,

                  output logic         memop_sync_start,
                  input  logic         memop_sync_end,
                  input  logic [4:0]   memop_sb_id,

                  input  logic         mask_idx_credit,
                  output logic [64:0]  mask_idx_item,
                  output logic         mask_idx_valid,
                  output logic         mask_idx_last_idx,

                  // Debug signals for cosim checker
                  output logic              debug_wb_vec_valid,
                  output logic [VLEN*8-1:0] debug_wb_vec_wdata,
                  output logic [7:0]        debug_wb_vec_wmask
);
                  // TODO: Add the signals for memory operations...

  localparam LOCAL_MEM_BYTE_ADDR_WIDTH = 12;
  localparam INCL_VEC = 1;
//  localparam VLEN = 256;
  localparam ADDRWIDTH = 48;
  localparam LD_DATA_WIDTH_BITS = VLEN;
  localparam ST_DATA_WIDTH_BITS = VLEN;
  localparam LQ_DEPTH=8;
  localparam LQ_DEPTH_LOG2=$clog2(LQ_DEPTH);
  localparam DATA_REQ_ID_WIDTH=INCL_VEC ? (LQ_DEPTH_LOG2+$clog2(VLEN/8)+2) : LQ_DEPTH_LOG2;
  localparam INCL_FP = 1;
  localparam STORE_CREDITS = 4;

  localparam                                          FLEN    = 32;
  localparam                                          FP_RF_RD_PORTS  = 4;
  localparam                                          FP_RF_WR_PORTS  = 2;
  localparam                                          FP_RF_ADDR_WIDTH    = 5;
  localparam                                          EXP_WIDTH   = 8;
  localparam                                          MAN_WIDTH   = 23;
  localparam                                          RS1_IDX = 0;
  localparam                                          RS2_IDX = 1;
  localparam                                          RS3_IDX = 2;

  tt_briscv_pkg::arr_lq_info_s  lq_broadside_info;
  logic [LQ_DEPTH-1:0][31:0]    lq_broadside_data;
  logic [LQ_DEPTH-1:0]          lq_broadside_valid;
  logic [LQ_DEPTH-1:0]          lq_broadside_data_valid;
  logic [VLEN-1:0]              lq_rddata;
  logic [4:0]                   lq_rdexc;

  /////////
  // ID signals
  wire                             id_rtr               ;
  wire [4:0]                       id_type              ;
  wire                             id_rf_wr_flag        ;
  wire [ 4:0]                      id_rf_wraddr         ;
  wire                             id_fp_rf_wr_flag     ;
  wire [ 4:0]                      id_fp_rf_wraddr      ;
  wire [31:0]                      id_immed_op          ;
  wire                             id_ex_rts            ;
  wire                             id_ex_units_rts      ;
  wire [LQ_DEPTH_LOG2-1:0]         id_ex_lqid;
  wire [4:0]                       id_ex_Zb_instr       ;
  wire                             id_ex_vecldst        ;
  wire [VLEN-1:0]                  vmask_rddata        ;
  wire [VLEN-1:0]                  vs2_rddata          ; 
  wire [VLEN-1:0]                  vs3_rddata          ; 
  wire [31:0]                      id_ex_pc             ;
  wire                             id_vex_rts           ;
  wire                             vex_id_rtr           ;
  wire [31:0]                      id_ex_instrn         ;
  wire                             v_vm                 ;
  logic [4:0]                      iterate_addrp0,iterate_addrp1,iterate_addrp2       ;
  logic                            ignore_lmul,ignore_dstincr,ignore_srcincr;
  wire [3:0]                       id_fp_fmt             ;
  tt_briscv_pkg::vec_autogen_s     id_vec_autogen;
  tt_briscv_pkg::vecldst_autogen_s id_ex_vecldst_autogen;
  wire                             id_ex_instdisp       ;
  logic                            id_ex_last;

  logic                     id_replay;              // From id of tt_id.v
  logic [LQ_DEPTH_LOG2-1:0] id_vex_lqid;          // From id of tt_id.v
  logic                     vex_id_incr_addrp2;     // From vecu of tt_vec.v

  // Matrix signals
  logic              mvrf_p0_rden, mvrf_p1_rden, mvrf_p2_rden;
  logic [       4:0] mvrf_p0_rdaddr, mvrf_p1_rdaddr, mvrf_p2_rdaddr;

  // Vector signals
  logic              vrf_p0_rden, vrf_p1_rden, vrf_p2_rden;
  logic [VLEN  -1:0] vrf_vm0_rddata;
  logic [VLEN  -1:0] vrf_p0_rddata, vrf_p1_rddata, vrf_p2_rddata;
  logic [       4:0] vrf_p0_rdaddr, vrf_p1_rdaddr, vrf_p2_rdaddr;
  logic              mem_rf_wr;
  logic [       4:0] mem_rf_wraddr;
  logic [      63:0] mem_rf_wrdata;
  logic              mem_fp_rf_wr;
  logic [       4:0] mem_fp_rf_wraddr;
  logic [      63:0] mem_fp_rf_wrdata;
  logic              mem_vrf_wr;
  logic              mem_vrf_wr_qual; // Can be squashed when vl=0
  logic              mem_vrf_wrmask;
  logic [       4:0] mem_vrf_wraddr;
  logic [VLEN  -1:0] mem_vrf_wrdata;
  logic [VLEN*8-1:0] mem_vrf_wrdata_reg;
  logic [VLEN*8-1:0] mem_vrf_wrdata_nxt;
  logic [       4:0] mem_vrf_wrexc;
  logic [       4:0] mem_vrf_wrexc_reg;
  logic [       4:0] mem_vrf_wrexc_nxt;
  logic [       7:0] mem_vrf_wrmask_reg;
  logic [       7:0] mem_vrf_wrmask_nxt;
  
  logic         vec_store_commit;
  logic         vec_nonstore_commit;

  // LQ signals
  // ID <--> MEM signals
  logic                     mem_fe_lqfull;
  logic [LQ_DEPTH_LOG2-1:0] mem_id_lqnxtid;
  logic [LQ_DEPTH_LOG2-1:0] mem_id_lqnxtid_r;
  logic                     id_mem_lqalloc;
  logic                     id_mem_lq_done;
  tt_briscv_pkg::lq_info_s  id_mem_lqinfo;
  
  // EX --> ID signals
  wire                     ex_dst_vld_1c;
  wire [LQ_DEPTH_LOG2-1:0] ex_dst_lqid_1c;
  wire [31:0]              ex_fwd_data_1c;
    
  wire                     ex_dst_vld_2c;
  wire [LQ_DEPTH_LOG2-1:0] ex_dst_lqid_2c;
  wire [31:0]              ex_fwd_data_2c;
  wire                     ex_id_rtr_raw; // before mask/store fsm stall
  wire                     ex_id_rtr;
  logic                    ex_last; // Indicates this is the last micro-op
  
  // EX --> MEM signals
  tt_briscv_pkg::mem_skidbuf_s ex_mem_payload;
  wire                         ex_mem_vld           ;

  logic                        ex_mem_lqvld_1c;
  logic [31:0]                 ex_mem_lqdata_1c;
  logic [LQ_DEPTH_LOG2-1:0]    ex_mem_lqid_1c;
    
  logic                        ex_mem_lqvld_2c;
  logic [31:0]                 ex_mem_lqdata_2c;
  logic [LQ_DEPTH_LOG2-1:0]    ex_mem_lqid_2c;
    
  // M EX --> MEM signals
  logic                     mvex_lqvld_4c;
  logic [VLEN-1:0]          mvex_lqdata_4c;
  logic [LQ_DEPTH_LOG2-1:0] mvex_lqid_4c;
  tt_briscv_pkg::csr_fp_exc mvex_lqexc_4c;
       
  // VEX --> MEM signals
  logic                     vex_mem_lqvld_1c;
  logic [VLEN-1:0]          vex_mem_lqdata_1c;
  logic [LQ_DEPTH_LOG2-1:0] vex_mem_lqid_1c;
  tt_briscv_pkg::csr_fp_exc vex_mem_lqexc_1c;
                        
  logic                     vex_mem_lqvld_2c;
  logic [VLEN-1:0]          vex_mem_lqdata_2c;
  logic [LQ_DEPTH_LOG2-1:0] vex_mem_lqid_2c;
  tt_briscv_pkg::csr_fp_exc vex_mem_lqexc_2c;
                        
  logic                     vex_mem_lqvld_3c;
  logic [VLEN-1:0]          vex_mem_lqdata_3c;
  logic [LQ_DEPTH_LOG2-1:0] vex_mem_lqid_3c;
  tt_briscv_pkg::csr_fp_exc vex_mem_lqexc_3c;

  logic [63:0]  rf_vex_p0_reg;
  logic [63:0]  rf_vex_p1_reg;
  logic [63:0]  fprf_vex_p0_reg;

  logic [63:0]  rf_vex_p0_sel;
  logic [63:0]  rf_vex_p1_sel;
  logic [63:0]  fprf_vex_p0_sel;

 // stall the ID stage when there is a load/store 
  logic mask_fsm_stall;
  logic store_fsm_stall;
  logic ocelot_read_req;

  logic        read_valid;
  logic [31:0] read_issue_inst;
  logic [4:0]  read_issue_sb_id;
  logic [63:0] read_issue_scalar_opnd;
  logic [39:0] read_issue_vcsr;
  logic        read_issue_vcsr_lmulb2;

  logic [VLEN*8-1:0] ocelot_instrn_commit_data;
  logic [7:0] ocelot_instrn_commit_mask;
  logic [VLEN*8-1:0] sb_debug_commit_data;
  logic [7:0] sb_debug_commit_mask;  
  logic [4:0] ocelot_instrn_commit_fflags;
  logic       ocelot_sat_csr;
  logic       ocelot_instrn_commit_valid;

  // Hack to keep the vector CSRs constant for ocelot
  logic [39:0] vcsr_reg;
  logic        vcsr_lmulb2_reg;
  logic [39:0] vcsr;
  logic        vcsr_lmulb2;
  logic       vecldst_autogen_store;
  logic       vecldst_autogen_load;

  logic [4:0] id_sb_id; // sb_id of the instruction at id stage
  logic [2:0] load_stride_eew;
  logic is_unit_stride;

  logic [7:0][2:0] req_buffer;
  logic [3:0] req_buffer_wptr;
  logic drain_load_buffer;
  logic [2:0] load_buffer_rptr;
  logic [LQ_DEPTH_LOG2-1:0] load_buffer_lqid;

  logic       drain_complete_valid;
  logic [2:0] drain_complete_ldb_idx;

  logic [63:0] scalar_opnd;
  logic [63:0] scalar_opnd_reg;
  logic [511:0] packed_load_data;
  logic [511:0] shifted_load_data;
  logic [63:0]  byte_en;
  logic [4:0]   sb_vd;
  logic [2:0]   sb_ldb_start;
  logic [1:0]   sb_data_size;
  logic [1:0]   sb_index_size;
  logic [2:0]   sb_load_stride_eew;
  logic         sb_drain_load_buffer;
  logic [2:0]   sb_drain_lqid_start;
  logic [2:0]   sb_drain_ldb_start;
  logic [2:0]   sb_ref_count;
  logic         sb_completed_valid;
  logic [4:0]   sb_completed_sb_id;
  logic [63:0]  sb_completed_dest_reg;
  logic [4:0]   sb_completed_fflags;
  logic [4:0]   v_reg;
  logic [10:0]  el_id;
  logic [5:0]   el_off;
  logic [6:0]   el_count;
  logic [4:0]   sb_id;
  // from 0 to 3, 8-bit to 64-bit EEW
  logic [1:0]   index_size;
  logic [1:0]   data_size;
  // this is in bytes
  logic signed [63:0]  load_stride;
  // this is the offset of the first element in the packed load data
  logic [5:0] packed_offset;
  logic [10:0] offset_diff;
  logic [$clog2(VLEN)-1:0] shamt;
  logic [8:0] el_id_lower_bound;
  logic [8:0] el_id_upper_bound;
  logic [7:0][VLEN-1:0] load_buffer;  
  logic       commit_is_load;
  logic       fsm_is_load;
  logic       id_is_whole_memop;
  logic       is_whole_memop;
  logic       id_is_masked_memop;
  logic       is_masked_memop;
  logic       id_is_indexldst;
  logic       id_is_maskldst;


  //////////
  // IF

  logic       ldb_alloc_valid;
  logic       ldb_alloc_ack;
  logic [4:0] ldb_alloc_sb_id;
  logic [3:0] ldb_alloc_size;
  logic [4:0] memop_sync_start_sb_id_nxt;
  logic       memop_sync_start_nxt;

  tt_fifo #(
    .DEPTH(32)
  ) fifo0
  (
    .clk(clk),
    .reset_n(reset_n),

    .issue_inst(issue_inst),
    .issue_sb_id(issue_sb_id),
    .issue_scalar_opnd(issue_scalar_opnd),
    .issue_vcsr(issue_vcsr),
    .issue_vcsr_lmulb2(issue_vcsr_lmulb2),
    .issue_valid(issue_valid),

    .dispatch_sb_id(dispatch_sb_id),
    .dispatch_next_senior(dispatch_next_senior),
    .dispatch_kill(dispatch_kill),

    .memop_sync_start(memop_sync_start_nxt),
    .memop_sync_start_sb_id(memop_sync_start_sb_id_nxt),
    .ldb_alloc_valid(ldb_alloc_valid),
    .ldb_alloc_ack(ldb_alloc_ack),
    .ldb_alloc_sb_id(ldb_alloc_sb_id),
    .ldb_alloc_size(ldb_alloc_size),

    .read_req(ocelot_read_req),
    .read_valid(read_valid),
    .read_issue_inst(read_issue_inst),
    .read_issue_sb_id(read_issue_sb_id),
    .read_issue_scalar_opnd(read_issue_scalar_opnd),
    .read_issue_vcsr(read_issue_vcsr),
    .read_issue_vcsr_lmulb2(read_issue_vcsr_lmulb2)
  );

  assign issue_credit = read_valid && ocelot_read_req;

  always_ff @(posedge clk) begin
    if(!reset_n) begin
      rf_vex_p0_reg   <= '0;
      rf_vex_p1_reg   <= '0;
      fprf_vex_p0_reg <= '0;
    end
    else if (read_valid &&
        ocelot_read_req   ) begin
        rf_vex_p0_reg   <= read_issue_scalar_opnd;
        rf_vex_p1_reg   <= read_issue_scalar_opnd;
        fprf_vex_p0_reg <= read_issue_scalar_opnd;
    end
  end

  assign rf_vex_p0_sel   = (read_valid && ocelot_read_req) ? read_issue_scalar_opnd   : rf_vex_p0_reg;
  assign rf_vex_p1_sel   = (read_valid && ocelot_read_req) ? read_issue_scalar_opnd   : rf_vex_p1_reg;
  assign fprf_vex_p0_sel = (read_valid && ocelot_read_req) ? read_issue_scalar_opnd : fprf_vex_p0_reg;

  tt_briscv_pkg::csr_t csr_de0, csr_ex0;
  assign csr_de0.v_vl    = vcsr[$clog2(VLEN+1)-1+14:14];
  assign csr_de0.v_vsew  = vcsr[38:36];
  assign csr_de0.v_lmul  = {vcsr_lmulb2, vcsr[35:34]};
  assign csr_de0.v_vxrm  = vcsr[30:29];
  assign csr_de0.frm     = vcsr[33:31];

  tt_id
  #(
    .LQ_DEPTH(LQ_DEPTH),
    .LQ_DEPTH_LOG2(LQ_DEPTH_LOG2), 
    .EXP_WIDTH(EXP_WIDTH),
    .MAN_WIDTH(MAN_WIDTH),
    .FLEN(FLEN),
    .VLEN(VLEN),
    .FP_RF_RD_PORTS(FP_RF_RD_PORTS),
    .INCL_VEC(INCL_VEC),
    .INCL_FP(INCL_FP)
  ) id
  (
    .i_clk                                 (clk             ),    
    .i_reset_n                             (reset_n), 

    .i_csr                                 (csr_de0),             
    .o_csr                                 (csr_ex0),             

    .i_if_instrn                           (read_issue_inst),       
    .i_if_pc                               ('0),           
    .i_if_instrn_rts                       (read_valid),    
    .o_id_instrn_rtr                       (ocelot_read_req),    

    .o_id_type                             (id_type),          
    .o_id_immed_op                         (id_immed_op),     

    // Vector Interface
    .o_id_vex_rts                          (id_vex_rts),            
    .i_vex_id_rtr                          (vex_id_rtr),            
    .o_vec_autogen                         (id_vec_autogen),   
    .o_id_vex_lqid                         (id_vex_lqid), 
    .i_vex_id_incr_addrp2                  (vex_id_incr_addrp2),    
    .o_v_vm                                (v_vm              ),    

    // EX Interface
    .o_id_ex_rts                           (id_ex_rts),             
    .i_ex_rtr                              (ex_id_rtr         ),    
    .o_id_ex_pc                            (id_ex_pc),        
    .o_id_ex_instrn                        (id_ex_instrn),    
    .o_id_ex_lqid                          (id_ex_lqid[LQ_DEPTH_LOG2-1:0]), 
    .o_id_ex_vecldst                       (id_ex_vecldst),         
    .o_id_ex_Zb_instr                      (id_ex_Zb_instr[4:0]),   
    .o_id_ex_units_rts                     (id_ex_units_rts),       
    .o_id_ex_instdisp                      (id_ex_instdisp),
    .o_vecldst_autogen                     (id_ex_vecldst_autogen), 
    .o_id_ex_last                          (id_ex_last),  
    .i_ex_dst_vld_1c                       (ex_dst_vld_1c),         
    .i_ex_dst_lqid_1c                      (ex_dst_lqid_1c), 
    .i_ex_fwd_data_1c                      (ex_fwd_data_1c),  
    .i_ex_dst_vld_2c                       (ex_dst_vld_2c),         
    .i_ex_dst_lqid_2c                      (ex_dst_lqid_2c), 
    .i_ex_fwd_data_2c                      (ex_fwd_data_2c),  

    // Integer RegFile Interface  
    .o_rf_wr_flag                          (id_rf_wr_flag     ),    
    .o_rf_wraddr                           (id_rf_wraddr      ),    

    // FP RegFile Interface    
    .o_fp_rf_wr_flag                       (id_fp_rf_wr_flag  ),    
    .o_fp_rf_wraddr                        (id_fp_rf_wraddr   ),    

    // Mem Interface
    .i_lq_broadside_info                   (lq_broadside_info),     
    .o_id_mem_lqinfo                       (id_mem_lqinfo),         
    .o_id_replay                           (id_replay),             
    .o_id_mem_lqalloc                      (id_mem_lqalloc),        
    .o_id_mem_lq_done                      (id_mem_lq_done),        
    .i_mem_dst_vld                         ('0          ), 
    .i_mem_dst_lqid                        ('0         ), 
    .i_mem_fwd_data                        ('0         ), 
    .i_mem_lq_op                           ('0),        
    .i_mem_lq_commit                       ('0),         
    .i_lq_broadside_data                   (lq_broadside_data),     
    .i_lq_broadside_valid                  (lq_broadside_valid), 
    .i_lq_broadside_data_valid             (lq_broadside_data_valid), 

    // Misc
    .i_iterate_addrp0                      (iterate_addrp0),   
    .i_iterate_addrp1                      (iterate_addrp1),   
    .i_iterate_addrp2                      (iterate_addrp2),   
    .i_ignore_lmul                         (ignore_lmul),           
    .i_ignore_dstincr                      (ignore_dstincr),        
    .i_ignore_srcincr                      (ignore_srcincr),        
    .i_mem_fe_lqfull                       (mem_fe_lqfull),         
    .i_mem_fe_lqempty                      ('0),
    .i_mem_fe_skidbuffull                  ('0),    
    .i_mem_id_lqnxtid                      (mem_id_lqnxtid[LQ_DEPTH_LOG2-1:0]),

    .o_is_whole_memop                      (id_is_whole_memop),
    .o_is_masked_memop                      (id_is_masked_memop),
    .o_is_indexldst                        (id_is_indexldst),
    .o_is_maskldst                         (id_is_maskldst),
    .i_if_sb_id                            (read_issue_sb_id),
    .o_id_sb_id                            (id_sb_id)
  );  

  //////////
  // EX
  assign vecldst_autogen_store = id_ex_vecldst_autogen.store;
  assign vecldst_autogen_load = id_ex_vecldst_autogen.load;

  logic squash_id_ex_rts;
  always_comb begin
     squash_id_ex_rts = 1'b0;

     if (id_is_indexldst) begin
        case ({id_ex_instrn[14:12], csr_ex0.v_vsew[1:0]})
           // index : data = 2
           5'b101_00,
           5'b110_01,
           5'b111_10: squash_id_ex_rts = id_ex_rts && id_ex_vecldst_autogen.ldst_iter_cnt[0] != 1'b0;
           // index : data = 4
           5'b110_00,
           5'b111_01: squash_id_ex_rts = id_ex_rts && id_ex_vecldst_autogen.ldst_iter_cnt[1:0] != 2'b00;
           // index : data = 4
           5'b111_00: squash_id_ex_rts = id_ex_rts && id_ex_vecldst_autogen.ldst_iter_cnt[2:0] != 3'b000;
           default  : squash_id_ex_rts = 1'b0;
        endcase
     end
  end
 
  tt_ex
  #(.INCL_VEC(INCL_VEC),
    .VLEN(VLEN),
    .LQ_DEPTH_LOG2(LQ_DEPTH_LOG2)
  ) ex
  (
    .i_clk               (clk             ),
    .i_reset_n           (reset_n),
    .i_sat_csr           ('0),
    .i_csr               (csr_ex0),             
    // From ID
    .i_if_ex_deco        ('0    ),
    .i_if_ex_predicted   ('0    ),
    .i_if_ex_nextinstr   ('0    ),
    .i_exc_fp_ex_update  ('0    ),
    .i_exc_vfp_update    ('0    ),
    
    // From ID
    .i_id_ex_rts         (id_ex_rts && !squash_id_ex_rts),
    .o_ex_id_rtr         (ex_id_rtr_raw     ),
    .i_id_type           (id_type           ),
    .i_id_rf_wr_flag     (id_rf_wr_flag     ),
    .i_id_rf_wraddr      (id_rf_wraddr      ),
    .i_id_fp_rf_wr_flag  (id_fp_rf_wr_flag  ),
    .i_id_fp_rf_wraddr   (id_fp_rf_wraddr   ),
    .i_id_immed_op       (id_immed_op       ),
    .i_id_ex_lqid        (id_ex_lqid        ),
    .i_id_ex_pc          (id_ex_pc          ),
    .i_id_ex_instrn      (id_ex_instrn      ),
    .i_id_ex_vecldst     (id_ex_vecldst     ),
    .i_id_ex_Zb_instr    (id_ex_Zb_instr    ),
    .i_id_ex_units_rts   (id_ex_units_rts   ),
    .i_id_ex_instdisp    (id_ex_instdisp    ),
    .i_id_ex_last        (id_ex_last),
    
    .i_id_ex_vecldst_autogen(id_ex_vecldst_autogen),
    
    // From RF
    .i_rf_p0_reg         (rf_vex_p0_reg),
    .i_rf_p1_reg         (rf_vex_p1_reg),
    .i_fp_rf_p3_reg      ('0),
    
    // From VRF
    .i_vmask_rddata      (vmask_rddata      ),
    .i_vs2_rddata        (vs2_rddata        ),
    .i_vs3_rddata        (vs3_rddata        ),
    
    // From MEM
    .i_mem_ex_rtr        (1'b1        ),
    
    // To ID and IF
    .o_ex_bp_fifo_pop    (),
    .o_ex_is_some_branch (),
    .o_ex_branch_taken   (),
    
    .o_ex_bp_mispredict         (),
    .o_ex_bp_mispredict_not_br  (),
    .o_ex_bp_pc                 (),
    
    .o_ex_dst_vld_1c        (ex_dst_vld_1c        ),
    .o_ex_dst_lqid_1c       (ex_dst_lqid_1c       ),
    .o_ex_fwd_data_1c       (ex_fwd_data_1c       ),
    .o_ex_dst_vld_2c        (ex_dst_vld_2c        ),
    .o_ex_dst_lqid_2c       (ex_dst_lqid_2c       ),
    .o_ex_fwd_data_2c       (ex_fwd_data_2c       ),
    
    // To MEM
    .o_ex_mem_lqvld_1c      (ex_mem_lqvld_1c     ),
    .o_ex_mem_lqid_1c       (ex_mem_lqid_1c      ),
    .o_ex_mem_lqdata_1c     (ex_mem_lqdata_1c    ),
    
    .o_ex_mem_lqvld_2c      (ex_mem_lqvld_2c     ),
    .o_ex_mem_lqid_2c       (ex_mem_lqid_2c      ),
    .o_ex_mem_lqdata_2c     (ex_mem_lqdata_2c    ),
    
    .o_ex_mem_payload       (ex_mem_payload      ),
    .o_ex_mem_vld           (ex_mem_vld          ),
    
    // Debug
    .i_reset_pc             ('0),

    //.i_draining_store_buffer(drain_store_buffer),
    //.i_id_store(vecldst_autogen_store),
    //.i_draining_mask_idx(draining_mask_idx),
    //.i_masked_or_indexed(id_is_masked_memop || id_is_indexldst),
    .o_ex_last(ex_last)
  );

  // Adding stalls from Store/Mask FSM
  assign ex_id_rtr = ex_id_rtr_raw && !store_fsm_stall && !mask_fsm_stall;

  assign vrf_p2_rden    = id_vec_autogen.rf_rden2; // FIXME | csr_ex0.v_lmul[2];
  assign vrf_p1_rden    = id_vec_autogen.rf_rden1;
  assign vrf_p0_rden    = id_vec_autogen.rf_rden0;

  // VRF read data for EX (V-LD/ST)
  assign vmask_rddata  = vrf_vm0_rddata;
  assign vs2_rddata    = vrf_p1_rddata;
  assign vs3_rddata    = vrf_p2_rddata;

  assign vrf_p0_rdaddr = mvrf_p0_rden                   ? mvrf_p0_rdaddr 
                                                        : id_vec_autogen.rf_addrp0;

  assign vrf_p1_rdaddr = mvrf_p1_rden                   ? mvrf_p1_rdaddr
                       : id_vec_autogen.rf_rd_p2_is_rs2 ? id_vec_autogen.rf_addrp2
                                                        : id_vec_autogen.rf_addrp1;
  assign vrf_p2_rdaddr = mvrf_p2_rden                   ? mvrf_p2_rdaddr
                       : id_vec_autogen.rf_rd_p2_is_rs2 ? id_vec_autogen.rf_addrp1
                                                        : id_vec_autogen.rf_addrp2;



  tt_matrix_unit #(.VLEN(VLEN))
  matrix_unit
  (
    // Inputs
    .i_clk               (clk),
    .i_reset_n           (reset_n),
    .i_inst              (issue_inst),
    .i_va                (vrf_p2_rddata),
    .i_vb               (vrf_p1_rddata),
    .i_vc               (vrf_p0_rddata),
    .i_dstmask_0a        (),
    .i_vm0_0a            (vrf_vm0_rddata),
    
    // Outputs
    .o_vrf_rdaddr_0a     ({mvrf_p2_rdaddr, mvrf_p1_rdaddr, mvrf_p0_rdaddr}),
    .o_mvex_lqvld    (mvex_lqvld_4c),      
    .o_mvex_lqdata   (mvex_lqdata_4c), 
    .o_mvex_lqexc    (mvex_lqexc_4c),      
    .o_mvex_lqid     (mvex_lqid_4c), 
// ...
  );

  tt_vec_regfile #(.VLEN(VLEN))
  regfile
  (
    .i_clk               (clk),
    .i_reset_n           (reset_n),
    .i_id_vec_autogen      (id_vec_autogen),        

    // Outputs
    .o_rddata_0a         ({vrf_p2_rddata,vrf_p1_rddata,vrf_p0_rddata}),
    .o_dstmask_0a        (),
    .o_vm0_0a            (vrf_vm0_rddata),
    // Inputs
    .i_rden_0a           ({vrf_p2_rden,vrf_p1_rden,vrf_p0_rden}),
    .i_wren_0a           (mem_vrf_wr_qual),
    .i_rdaddr_0a         ({vrf_p2_rdaddr, vrf_p1_rdaddr, vrf_p0_rdaddr}),
    .i_wraddr_0a         (mem_vrf_wraddr),
    .i_wrdata_0a         (mem_vrf_wrdata)
  );

  tt_vec #(.VLEN(VLEN),
          .XLEN(64  ) )
  vecu
  (
    .i_clk                 (clk),                 
    .i_reset_n             (reset_n), 
    .i_csr                 (csr_ex0),             
    .i_v_vm                (v_vm),                  
    .i_id_vec_autogen      (id_vec_autogen),        
    .o_sat_csr             (ocelot_sat_csr),
    // ID Interface
    .i_id_vex_rts          (id_vex_rts),            
    .o_vex_id_rtr          (vex_id_rtr),            
    .i_id_ex_vecldst       (id_ex_vecldst),         
    .i_id_ex_instrn        (id_ex_instrn),    
    .i_id_replay           (id_replay),             
    .i_id_type             (id_type),          
    .o_vex_id_incr_addrp2  (vex_id_incr_addrp2),    
    .o_iterate_addrp0      (iterate_addrp0),   
    .o_iterate_addrp1      (iterate_addrp1),   
    .o_iterate_addrp2      (iterate_addrp2),   
    .o_ignore_lmul         (ignore_lmul),           
    .o_ignore_dstincr      (ignore_dstincr),        
    .o_ignore_srcincr      (ignore_srcincr),        
    // RegFile Interface
    .i_rf_vex_p0           (rf_vex_p0_sel),       
    .i_fprf_vex_p0         (fprf_vex_p0_sel),
    .i_vrf_p0_rddata       (vrf_p0_rddata),  
    .i_vrf_p1_rddata       (vrf_p1_rddata),  
    .i_vrf_p2_rddata       (vrf_p2_rddata),  
    .i_vrf_vm0_rddata      (vrf_vm0_rddata),
    // Mem Interface
    .o_vex_mem_lqvld_1c    (vex_mem_lqvld_1c),      
    .o_vex_mem_lqdata_1c   (vex_mem_lqdata_1c), 
    .o_vex_mem_lqexc_1c    (vex_mem_lqexc_1c),      
    .o_vex_mem_lqid_1c     (vex_mem_lqid_1c), 
    .o_vex_mem_lqvld_2c    (vex_mem_lqvld_2c),      
    .o_vex_mem_lqdata_2c   (vex_mem_lqdata_2c), 
    .o_vex_mem_lqexc_2c    (vex_mem_lqexc_2c),      
    .o_vex_mem_lqid_2c     (vex_mem_lqid_2c), 
    .o_vex_mem_lqvld_3c    (vex_mem_lqvld_3c),      
    .o_vex_mem_lqdata_3c   (vex_mem_lqdata_3c), 
    .o_vex_mem_lqexc_3c    (vex_mem_lqexc_3c),      
    .o_vex_mem_lqid_3c     (vex_mem_lqid_3c), 
    .i_mem_vrf_wr          (mem_vrf_wr),            
    .i_mem_vrf_wraddr      (mem_vrf_wraddr),   
    .i_mem_vrf_wrdata      (mem_vrf_wrdata), 
    .i_mem_ex_rtr          (1'b1)            
  );    

// *********************** //
// Load Queue              //
// *********************** //

wire           lq_mem_rf_wr_flag;
logic          lq_mem_fp_rf_wr_flag;
wire           lq_mem_vrf_wr_flag;
wire [4:0]     lq_mem_rf_wraddr;
logic [31:0]   lq_mem_pc;
logic [31:0]   lq_sim_ex_mem_instrn;
logic          lq_rden;
logic [2:0]    lq_rdid;

tt_briscv_pkg::lq_info_s        lq_rdinfo;

tt_lq #(.LQ_DEPTH(LQ_DEPTH), 
        .LQ_DEPTH_LOG2(LQ_DEPTH_LOG2), 
        .DATA_REQ_ID_WIDTH(DATA_REQ_ID_WIDTH),
        .LD_DATA_WIDTH_BITS(LD_DATA_WIDTH_BITS),
        .VLEN(VLEN),
        .INCL_VEC(INCL_VEC)) lq_fifo
(
   .i_clk            (clk                    ),
   .i_reset_n        (reset_n                ),

   .i_bypass_disable (1'b0),

   .i_vecld_elem_sent(ex_mem_payload.vecldst_vld & 
                      ex_mem_payload.mem_load    &
                      ex_mem_vld                     ),
   .i_vecld_idx_last (ex_mem_payload.vecldst_idx_last),
   .i_vecld_id       (ex_mem_lqid_1c                 ),
 
   // ID <--> MEM signals
   .o_mem_id_lqnxtid(mem_id_lqnxtid),
   .i_id_mem_lqalloc(id_mem_lqalloc),
   .i_id_mem_lqinfo(id_mem_lqinfo),
 
   // Skid buffer signals
   .i_skidbuf_lqvld_1c(ex_mem_lqvld_1c),
   .i_skidbuf_lqsz_1c(ex_mem_payload.mem_sz[2:0]),
   .i_skidbuf_lqaddr_1c(ex_mem_payload.mem_addr[$clog2(VLEN/8)-1:0]),
   .i_skidbuf_lqmask_1c(ex_mem_payload.vecldst_byte_mask),
   .i_skidbuf_lqvecld128_1c(ex_mem_payload.vecldst_128),
   .i_skidbuf_lqdata_1c(ex_mem_payload.mem_store_data),
   .i_skidbuf_lqid_1c(ex_mem_lqid_1c),

   // EX 2 cycle signals
   .i_ex_mem_lqvld_2c(ex_mem_lqvld_2c),
   .i_ex_mem_lqdata_2c(ex_mem_lqdata_2c),
   .i_ex_mem_lqid_2c(ex_mem_lqid_2c),
 
   // FP EX 2 cycle signals
   .i_fp_ex_mem_lqvld_1c('0),
   .i_fp_ex_mem_lqdata_1c('0),
   .i_fp_ex_mem_lqid_1c('0),
 
   .i_fp_ex_mem_lqvld_2c('0),
   .i_fp_ex_mem_lqdata_2c('0),
   .i_fp_ex_mem_lqid_2c('0),
 
   // VEX 1/2/3 cycle signals
   .i_vex_mem_lqvld_1c(vex_mem_lqvld_1c),
   .i_vex_mem_lqdata_1c(vex_mem_lqdata_1c),
   .i_vex_mem_lqexc_1c(vex_mem_lqexc_1c),
   .i_vex_mem_lqid_1c(vex_mem_lqid_1c),

   .i_vex_mem_lqvld_2c(vex_mem_lqvld_2c),
   .i_vex_mem_lqdata_2c(vex_mem_lqdata_2c),
   .i_vex_mem_lqexc_2c(vex_mem_lqexc_2c),
   .i_vex_mem_lqid_2c(vex_mem_lqid_2c),

   .i_vex_mem_lqvld_3c(vex_mem_lqvld_3c),
   .i_vex_mem_lqdata_3c(vex_mem_lqdata_3c),
   .i_vex_mem_lqexc_3c(vex_mem_lqexc_3c),
   .i_vex_mem_lqid_3c(vex_mem_lqid_3c),

    // matrix unit output
   .i_vex_mem_lqvld_4c(mvex_lqvld_4c),
   .i_vex_mem_lqdata_4c(mvex_lqdata_4c),
   .i_vex_mem_lqexc_4c(mvex_lqexc_4c),
   .i_vex_mem_lqid_4c(mvex_lqid_4c),

   // Load return data
   .i_data_vld_0(drain_load_buffer),
   .i_data_vld_cancel_0('0),
   .i_data_resp_id_0(DATA_REQ_ID_WIDTH'(load_buffer_lqid)),
   .i_data_rddata_0(load_buffer[load_buffer_rptr[2:0]]),
 
   .i_data_vld_1('0),
   .i_data_vld_cancel_1('0),
   .i_data_resp_id_1('0),
   .i_data_rddata_1('0),
 
   .i_data_vld_2('0),
   .i_data_vld_cancel_2('0),
   .i_data_resp_id_2('0),
   .i_data_rddata_2('0),
 
   .lq_full(mem_fe_lqfull),
   .lq_empty(),
   .o_lq_data_ready(lq_rden),
   .o_lq_mem_vec_load(),
   .o_lq_mem_load(),

   // LQ Read signals
   .i_lq_rden(lq_rden),
   .o_lq_rdid(lq_rdid),
   .o_lq_rdinfo(lq_rdinfo),
   .o_lq_rdmemaddr(),
   .o_lq_rdldstsz(),
   .o_lq_rddata(lq_rddata),
   .o_lq_rdexc(lq_rdexc),

   .o_lq_fwdvld(),
   .o_lq_fwdid(),
   .o_lq_fwddata(),

   // Broadside data
   .o_lq_broadside_info(lq_broadside_info),
   .o_lq_broadside_data(lq_broadside_data),
   .o_lq_broadside_valid(lq_broadside_valid),
   .o_lq_broadside_data_valid(lq_broadside_data_valid)
);

assign lq_mem_vrf_wr_flag     =   lq_rdinfo.vrf_wr_flag;        
assign lq_mem_fp_rf_wr_flag   =   lq_rdinfo.fp_rf_wr_flag;       
assign lq_mem_rf_wr_flag      =   lq_rdinfo.rf_wr_flag;          
assign lq_mem_pc              =   lq_rdinfo.pc           [31:0]; 
assign lq_sim_ex_mem_instrn   =   lq_rdinfo.sim_instrn   [31:0]; 
assign lq_mem_rf_wraddr       =   lq_rdinfo.rf_wraddr    [4:0];  

assign vec_store_commit =  lq_rden                 &&
                            !lq_rdinfo.rf_wr_flag    &&
                            !lq_rdinfo.vrf_wr_flag   &&
                            !lq_rdinfo.fp_rf_wr_flag;
   
assign vec_nonstore_commit =  lq_rden                 &&
                             !vec_store_commit       &&
                              lq_rdinfo.vrf_wr_flag;
   

// ************************ //
// Write back to registers  //
// ************************ //
assign mem_rf_wr             = lq_rden & lq_mem_rf_wr_flag;
assign mem_rf_wraddr[4:0]    = lq_mem_rf_wraddr[4:0];
assign mem_rf_wrdata[63:0]   = lq_rddata[63:0]; 

assign mem_vrf_wr            = lq_rden & lq_mem_vrf_wr_flag;   
assign mem_vrf_wr_qual       = lq_rden & lq_mem_vrf_wr_flag & !lq_rdinfo.squash_vec_wr_flag;   
assign mem_vrf_wraddr[4:0]   = lq_mem_rf_wraddr[4:0];    
assign mem_vrf_wrdata[VLEN-1:0] = lq_rddata[VLEN-1:0];
assign mem_vrf_wrexc         = lq_rdinfo.vec_load ? '0 : lq_rdexc;
assign mem_vrf_wrmask        = !lq_rdinfo.vl_is_zero;

//fixme_msalvi asserrt one hot between vrf and rf wr and fp
//Use FP Port0 for now for ex results. Will use port 1 when dual issue is enabled
assign mem_fp_rf_wr           = lq_rden & lq_mem_fp_rf_wr_flag;
assign mem_fp_rf_wraddr[4:0]  = lq_mem_rf_wraddr;
assign mem_fp_rf_wrdata[63:0] = lq_rddata[63:0];

  logic [LQ_DEPTH     -1:0] lq_last;
  logic [LQ_DEPTH_LOG2-1:0] lq_rd_ptr;

  assign ocelot_instrn_commit_valid       =   mem_rf_wr || mem_fp_rf_wr ||
                                        (vec_nonstore_commit && lq_last[lq_rd_ptr]);
  assign ocelot_instrn_commit_data[VLEN*8-1:64] =  {VLEN*8-64{vec_nonstore_commit}} & mem_vrf_wrdata_nxt[VLEN*8-1:64];
  assign ocelot_instrn_commit_data[      63: 0] =        ({64{vec_nonstore_commit}} & mem_vrf_wrdata_nxt[      63: 0]) |
                                                    ({64{mem_rf_wr          }} & mem_rf_wrdata     [      63: 0]) |
                                                    ({64{mem_fp_rf_wr       }} & mem_fp_rf_wrdata  [      63: 0]);
  assign ocelot_instrn_commit_fflags            =        ({ 5{vec_nonstore_commit}} & mem_vrf_wrexc_nxt [       4: 0]);
  assign ocelot_instrn_commit_mask              =                                     mem_vrf_wrmask_nxt;

  always_ff @(posedge clk) begin
    if (!reset_n) begin
        lq_last          <= '0;
        lq_rd_ptr        <= '0;
        mem_id_lqnxtid_r <= '0;
    end else begin
        if (lq_rden) begin
          lq_rd_ptr <= lq_rd_ptr + 1;
        end

        if (id_mem_lqalloc) begin
          lq_last[mem_id_lqnxtid] <= id_mem_lq_done;
          mem_id_lqnxtid_r        <= mem_id_lqnxtid;
        end else
        if (id_mem_lq_done) begin
          lq_last[mem_id_lqnxtid_r] <= 1'b1;
        end
    end
  end


  logic [2:0] lmul_cnt;

  always_ff @(posedge clk) begin
    if (!reset_n) begin
        mem_vrf_wrdata_reg <= '0;
        mem_vrf_wrmask_reg <= '0;
        mem_vrf_wrexc_reg  <= '0;
    end else begin
        if (ocelot_instrn_commit_valid) begin
          mem_vrf_wrdata_reg <= '0;
          mem_vrf_wrmask_reg <= '0;
          mem_vrf_wrexc_reg  <= '0;
        end else
        if (mem_vrf_wr) begin
          mem_vrf_wrdata_reg <= mem_vrf_wrdata_nxt;
          mem_vrf_wrmask_reg <= mem_vrf_wrmask_nxt;
          mem_vrf_wrexc_reg  <= mem_vrf_wrexc_nxt;
        end
    end
  end

  always_comb begin
    mem_vrf_wrdata_nxt = mem_vrf_wrdata_reg;
    mem_vrf_wrmask_nxt = mem_vrf_wrmask_reg;
    mem_vrf_wrexc_nxt  = mem_vrf_wrexc_reg;

    mem_vrf_wrdata_nxt[VLEN*lmul_cnt +: VLEN] =   ;
    mem_vrf_wrmask_nxt[     lmul_cnt        ] = mem_vrf_wrmask;
    mem_vrf_wrexc_nxt                        |= mem_vrf_wrexc;
  end

  always_ff @(posedge clk) begin
    if (!reset_n) begin
        lmul_cnt <= '0;
    end else begin
        if (ocelot_instrn_commit_valid) begin
          lmul_cnt <= '0;
        end else
        if (mem_vrf_wr) begin
          lmul_cnt <= lmul_cnt + 1;
        end
    end
  end

  // This queue should never overflow, so I'm not going to add phase bits
  // to check if it's full or not.
  localparam sbid_queue_depth = 8;
  logic [sbid_queue_depth-1:0][4:0] sbid_queue;
  logic [$clog2(sbid_queue_depth)-1:0] sbid_queue_wptr;
  logic [$clog2(sbid_queue_depth)-1:0] sbid_queue_rptr;
 
  logic completed_valid_nxt;

  always_ff@(posedge clk) begin
    if(!reset_n) begin
      for(int i=0; i<sbid_queue_depth; i=i+1)
        sbid_queue[i] <= 0;
      sbid_queue_wptr <= 0;
      sbid_queue_rptr <= 0;
    end
    else begin
      if(ocelot_read_req && read_valid) begin
        sbid_queue[sbid_queue_wptr] <= read_issue_sb_id;
        sbid_queue_wptr <= sbid_queue_wptr + 1;
      end
      if(completed_valid_nxt) begin
        sbid_queue_rptr <= sbid_queue_rptr + 1;
      end
    end
  end

  tt_scoreboard_ovi scoreboard
                   (.clk(clk),
                    .reset_n(reset_n),
                    .i_issue_valid(issue_valid),
                    .i_issue_sb_id(issue_sb_id),
                    .i_issue_inst(issue_inst),
                    .i_issue_vsew(issue_vcsr[38:36]),
                    .i_issue_scalar_opnd(issue_scalar_opnd),
                    .i_vd(id_ex_instrn[11:7]),
                    .i_rd(ocelot_instrn_commit_data[63:0]),
                    .i_rd_valid(lq_rden),
                    .i_rd_lqid(lq_rdid),
                    .i_fflags(ocelot_instrn_commit_fflags),
                    .i_lqnxtid(mem_id_lqnxtid),
                    .i_data_size(data_size),
                    .i_index_size(index_size),
                    .i_load_stride_eew(load_stride_eew),
                    .i_memop_sync_end(memop_sync_end),
                    .i_memop_sync_end_sb_id(memop_sb_id),
                    .i_id_store(vecldst_autogen_store),
                    .i_id_load(vecldst_autogen_load),
                    .i_id_ex_rts(id_ex_rts),
                    .i_ex_id_rtr(ex_id_rtr),
                    .i_vex_id_rtr(vex_id_rtr),
                    .i_id_vex_rts(id_vex_rts),
                    .i_id_sb_id(id_sb_id),
                    .i_id_mem_lqalloc(id_mem_lqalloc),
                    .i_first_alloc(id_vec_autogen.replay_cnt == 0),
                    .i_last_alloc(id_mem_lq_done),
                    .i_load_sb_id(load_seq_id[33:29]),

                    .i_memop_sync_start(memop_sync_start_nxt),
                    .i_memop_sync_start_sb_id(memop_sync_start_sb_id_nxt),

                    .ldb_alloc_valid(ldb_alloc_valid),
                    .ldb_alloc_ack(ldb_alloc_ack),
                    .ldb_alloc_sb_id(ldb_alloc_sb_id),
                    .ldb_alloc_size(ldb_alloc_size),

                    .o_vd(sb_vd),
                    .o_ldb_start(sb_ldb_start),
                    .o_data_size(sb_data_size),
                    .o_index_size(sb_index_size),
                    .o_load_stride_eew(sb_load_stride_eew),

                    .o_drain_load_buffer(sb_drain_load_buffer),
                    .i_draining_load_buffer(drain_load_buffer),
                    .o_drain_ref_count(sb_ref_count),
                    .o_drain_lqid_start(sb_drain_lqid_start),
                    .o_drain_ldb_start(sb_drain_ldb_start),

                    .i_drain_complete_valid(drain_complete_valid),
                    .i_drain_complete_ldb_idx(drain_complete_ldb_idx),

                    .o_completed_valid(sb_completed_valid),
                    .o_completed_sb_id(sb_completed_sb_id),
                    .o_completed_dest_reg(sb_completed_dest_reg),
                    .o_completed_fflags(sb_completed_fflags),
                    .i_debug_commit_data(ocelot_instrn_commit_data),
                    .i_debug_commit_mask(ocelot_instrn_commit_mask),
                    .o_debug_commit_data(sb_debug_commit_data),
                    .o_debug_commit_mask(sb_debug_commit_mask));

  assign vcsr        = ocelot_read_req && read_valid ? read_issue_vcsr : vcsr_reg;
  assign vcsr_lmulb2 = ocelot_read_req && read_valid ? read_issue_vcsr_lmulb2 : vcsr_lmulb2_reg;

  always_ff@(posedge clk) begin
    if(!reset_n)
      {vcsr_reg, vcsr_lmulb2_reg} <= 0;
    else if(read_valid && ocelot_read_req) begin
      vcsr_reg <= read_issue_vcsr;
      vcsr_lmulb2_reg <= read_issue_vcsr_lmulb2;
    end
  end

  assign v_reg = load_seq_id[4:0];
  assign el_id = load_seq_id[15:5];
  assign el_off = load_seq_id[21:16];
  assign el_count = load_seq_id[28:22];
  assign sb_id = load_seq_id[33:29];

  always_comb begin
    is_unit_stride = id_ex_instrn[27:26] == 2'b00;
    data_size = id_is_indexldst ? csr_ex0.v_vsew[1:0] :
                id_ex_instrn[14:12] == 3'b000 ? 2'd0 : // 8-bit EEW
                id_ex_instrn[14:12] == 3'b101 ? 2'd1 : // 16-bit EEW
                id_ex_instrn[14:12] == 3'b110 ? 2'd2 : 2'd3; // 32-bit, 64-bit EEW
    index_size =  id_ex_instrn[14:12] == 3'b000 ? 2'd0 : // 8-bit EEW
                  id_ex_instrn[14:12] == 3'b101 ? 2'd1 : // 16-bit EEW
                  id_ex_instrn[14:12] == 3'b110 ? 2'd2 : 2'd3; // 32-bit, 64-bit EEW      
    load_stride = !id_is_indexldst ? scalar_opnd : 
                csr_ex0.v_vsew == 3'b000 ? 1 : // 8-bit EEW
                csr_ex0.v_vsew == 3'b101 ? 2 : // 16-bit EEW
                csr_ex0.v_vsew == 3'b110 ? 4 : 8; // 32-bit, 64-bit EEW;                            
    if(is_unit_stride)
        load_stride_eew = 0;
    else if((data_size == 0 && load_stride == 64'd1) ||
            (data_size == 1 && load_stride == 64'd2) || 
            (data_size == 2 && load_stride == 64'd4) || 
            (data_size == 3 && load_stride == 64'd8))
        load_stride_eew = 0;
    else if((data_size == 0 && load_stride == 64'd2) ||
            (data_size == 1 && load_stride == 64'd4) || 
            (data_size == 2 && load_stride == 64'd8) || 
            (data_size == 3 && load_stride == 64'd16))
        load_stride_eew = 1;
    else if((data_size == 0 && load_stride == 64'd4) ||
            (data_size == 1 && load_stride == 64'd8) || 
            (data_size == 2 && load_stride == 64'd16) || 
            (data_size == 3 && load_stride == 64'd32))
        load_stride_eew = 2;
    else if((data_size == 0 && load_stride == -64'd1) ||
            (data_size == 1 && load_stride == -64'd2) || 
            (data_size == 2 && load_stride == -64'd4) || 
            (data_size == 3 && load_stride == -64'd8))
        load_stride_eew = 4;
    else if((data_size == 0 && load_stride == -64'd2) ||
            (data_size == 1 && load_stride == -64'd4) || 
            (data_size == 2 && load_stride == -64'd8) || 
            (data_size == 3 && load_stride == -64'd16))
        load_stride_eew = 5;
    else if((data_size == 0 && load_stride == -64'd4) ||
            (data_size == 1 && load_stride == -64'd8) || 
            (data_size == 2 && load_stride == -64'd16) || 
            (data_size == 3 && load_stride == -64'd32))
        load_stride_eew = 6;
    else
        load_stride_eew = 0;
  end

  always @(posedge clk) begin
    if(!reset_n)
      scalar_opnd_reg <= 0;
    else if(ocelot_read_req && read_valid)
      scalar_opnd_reg <= read_issue_scalar_opnd;
  end
  assign scalar_opnd = (ocelot_read_req && read_valid) ? read_issue_scalar_opnd : scalar_opnd_reg;

  lrm_model lrm
  (
   .clk(clk),
   .reset_n(reset_n),
   .load_valid(load_valid),
   .load_data(load_data),
   .load_seq_id(load_seq_id),
   .stride(sb_load_stride_eew),
   .eew(sb_data_size), 

   .packed_data(shifted_load_data),
   .byte_en(byte_en)
  );

  logic [2:0] load_buffer_drain_cntr;
  always @(posedge clk) begin
    if(!reset_n)
      {drain_load_buffer,load_buffer_drain_cntr} <= 0;
    else begin
      if(!drain_load_buffer && sb_drain_load_buffer)
        drain_load_buffer <= 1;
      else if(load_buffer_drain_cntr == 0)
        drain_load_buffer <= 0;

      if(sb_drain_load_buffer && !drain_load_buffer)
        load_buffer_drain_cntr <= sb_ref_count - 1;
      else if(drain_load_buffer && load_buffer_drain_cntr != 0)
        load_buffer_drain_cntr <= load_buffer_drain_cntr - 1;
    end
  end

  always @(posedge clk) begin
    if(!reset_n) begin
      load_buffer_rptr <= '0;
      load_buffer_lqid <= '0;
    end else begin
      if(!drain_load_buffer && sb_drain_load_buffer) begin
        load_buffer_rptr <= sb_drain_ldb_start;
        load_buffer_lqid <= sb_drain_lqid_start;
      end else if(drain_load_buffer) begin
        load_buffer_rptr <= load_buffer_rptr + 1;
        load_buffer_lqid <= load_buffer_lqid + 1;
      end
    end
  end

  assign drain_complete_valid = drain_load_buffer;
  assign drain_complete_ldb_idx = load_buffer_rptr;

  integer k;
  always @(posedge clk) begin
    if(!reset_n)
      for(k=0; k<8; k=k+1)
        load_buffer[k] <= 0;
    else if(load_valid) begin
      for(k=0; k<VLEN; k=k+8)
        load_buffer[(v_reg-sb_vd+sb_ldb_start)%8][k+:8] <= byte_en[k/8] ? shifted_load_data[k+:8] : load_buffer[(v_reg-sb_vd+sb_ldb_start)%8][k+:8];
    end
  end

  integer r;
  always @(posedge clk) begin
    if(!reset_n) begin
      req_buffer_wptr <= 0;
      for(r=0; r<8; r=r+1)
        req_buffer[r] <= 0;
    end
    else begin
      // Not 100% sure about this, but I'm trying to capture the first request basically.
      // Maybe I should have used `if(ocelot_read_req && read_valid)` ?
      if(vecldst_autogen_load && ex_id_rtr && id_ex_rts && id_mem_lqalloc && id_ex_vecldst_autogen.ldst_iter_cnt == 0) begin
        req_buffer_wptr <= read_issue_inst[9:7] + 1;
        req_buffer[read_issue_inst[9:7]] <= mem_id_lqnxtid;
      end
      else if(id_mem_lqinfo.vec_load && id_mem_lqalloc) begin
        req_buffer[req_buffer_wptr[2:0]] <= mem_id_lqnxtid;
        req_buffer_wptr <= req_buffer_wptr + 1;
      end
    end
  end

  logic         store_valid_nxt;
  logic [511:0] store_data_nxt;

  tt_store_fsm #(.VLEN(VLEN),
                .STORE_CREDITS(STORE_CREDITS))
                store_fsm
               (.i_clk(clk),
                .i_reset_n(reset_n),
                .i_uop_fire(id_ex_units_rts && ex_id_rtr && !id_mem_lqinfo.squash_vec_wr_flag),
                .i_uop_first(id_ex_vecldst_autogen.ldst_iter_cnt == 0),
                .i_uop_last(id_ex_last),
                .i_uop_is_store(vecldst_autogen_store),
                .i_uop_is_vsm(id_is_maskldst),
                .i_uop_is_vsx(id_is_indexldst),
                .i_uop_is_vsr(id_is_whole_memop),
                .i_uop_index_size(index_size),
                .i_uop_data_size(data_size),
                .i_uop_vl(csr_ex0.v_vl),
                .i_uop_nfield(id_ex_instrn[31:29]),
                .i_store_data(vs3_rddata),
                .i_store_credit(store_credit),
                .o_store_valid(store_valid_nxt),
                .o_store_data(store_data_nxt),
                .o_stall(store_fsm_stall)
              );


  tt_mask_fsm #(.VLEN(VLEN),
                .MASK_CREDITS(2))
                mask_fsm
               (.i_clk(clk),
                .i_reset_n(reset_n),
                .i_is_masked_memop(id_is_masked_memop),
                .i_memop_sync_start_next(id_ex_units_rts && ex_id_rtr),
                .i_is_indexed(id_is_indexldst),
                .i_mask_data(vmask_rddata),
                .i_index_data(vs2_rddata),
                .i_index_data_valid(id_ex_units_rts && ex_id_rtr),
                .i_last_index(id_ex_last),
                .o_draining_mask_idx(mask_fsm_stall),
                .i_vl(csr_ex0.v_vl),
                .i_eew(index_size),
                .i_mask_idx_credit(mask_idx_credit),
                .o_mask_idx_item(mask_idx_item),
                .o_mask_idx_valid(mask_idx_valid),
                .o_mask_idx_last_idx(mask_idx_last_idx)
               );

  // OVI Outputs
  always @(posedge clk) begin
    if(!reset_n) begin
      memop_sync_start <= 0;
      store_valid <= 0;
      store_data <= 0;
      completed_valid <= 0;
      completed_sb_id <= 0;
      completed_fflags <= 0;
      completed_dest_reg <= 0;
      completed_vxsat <= 0;
      completed_vstart <= 0;
      completed_illegal <= 0;
    end
    else begin
      memop_sync_start <= memop_sync_start_nxt;
      store_valid <= store_valid_nxt;
      store_data <= store_data_nxt;
      completed_valid <= sb_completed_valid;
      completed_sb_id <= sb_completed_sb_id;
      completed_fflags <= sb_completed_fflags;
      completed_dest_reg <= sb_completed_dest_reg;
      completed_vxsat <= 0;
      completed_vstart <= 0;
      completed_illegal <= 0;
    end
  end

  always_ff @(posedge clk) begin
    if (~reset_n) begin
      debug_wb_vec_valid <= '0;
      debug_wb_vec_wdata <= '0;
      debug_wb_vec_wmask <= '0;
    end 
    else begin
      debug_wb_vec_valid <= sb_completed_valid;
      debug_wb_vec_wdata <= sb_debug_commit_data;
      debug_wb_vec_wmask <= sb_debug_commit_mask;
    end
  end

endmodule
