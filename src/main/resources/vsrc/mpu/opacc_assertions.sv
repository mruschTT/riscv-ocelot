module opacc_assertions
(
   input logic         clk,
   input logic         reset_n,
   input logic         load_valid,
   input logic [511:0] load_data,
   input logic [ 33:0] load_seq_id,
   input logic [  2:0] stride,     // 0:1, 1:2, 2:4, 3:RSVD, 4:-1, 5:-2, 6:-4, 7:RSVD
   input logic [  1:0] eew,        // 0:1B, 1:2B, 2:4B, 3:8B

   input logic [511:0] packed_data,
   input logic [ 63:0] byte_en
);

   logic [511:0] model_packed_data;
   logic [ 63:0] model_byte_en;
   tt_vec_opacc_dp dut
   (
     .clk(clk),
     .sized_src3_0a(sized_src3_0a),
     .sized_src2_0a(sized_src2_0a),
     .sized_src1_0a(sized_src1_0a),
     .issgn_a(issgn),
     .issgn_b(issgn),
     .mulen_0a(mulen_0a),
   );

   logic [63:0] chk_fail;

   always_comb begin
      for (int i=0; i<64; i++) begin
         chk_fail[i] = (model_byte_en[i] != byte_en[i]) ||
                       (model_byte_en[i] && (model_packed_data[i*8+:8] != packed_data[i*8+:8]));
      end
   end

   default disable iff (!reset_n);
   default clocking @(clk);
   endclocking
   assert property (load_valid |-> ~|chk_fail);
endmodule

bind opacc opacc_assertions i_assertion (.*);
