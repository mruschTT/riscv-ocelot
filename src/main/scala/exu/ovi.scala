// See LICENSE.TT for license details.
package boom.exu

import chisel3._
import chisel3.util._
import chisel3.experimental._

import org.chipsalliance.cde.config.Parameters
import freechips.rocketchip.rocket.{VConfig}

import boom.exu.FUConstants._
import boom.common._
import boom.exu._
import boom.util._
import boom.lsu.{LSUExeIO}

import hardfloat._

class CombMemory[T <: Data](size: Int, gen: T) extends Module {
  val io = IO(new Bundle {
    val wrAddr = Input(UInt(log2Ceil(size).W))
    val wrData = Input(gen.cloneType)
    val wrEn   = Input(Bool())
    val rdAddr = Input(UInt(log2Ceil(size).W))
    val rdData = Output(gen.cloneType)
  })

  val mem = RegInit(VecInit(Seq.fill(size)(0.U.asTypeOf(gen))))

  when(io.wrEn) {
    mem(io.wrAddr) := io.wrData
  }

  io.rdData := mem(io.rdAddr)
}

class EnhancedFuncUnitReq(xLen: Int, vLen: Int)(implicit p: Parameters) extends Bundle {
  val vconfig = new VConfig()
  val vxrm = UInt(2.W)
  val fcsr_rm = UInt(3.W)
  val req = new FuncUnitReq(xLen)
}

class OviWrapper(xLen: Int, vLen: Int)(implicit p: Parameters)
    extends BoomModule
    with freechips.rocketchip.rocket.constants.MemoryOpConstants {
  val io = IO(new Bundle {
    val vconfig = Input(new VConfig())
    val vxrm = Input(UInt(2.W))
    val fcsr_rm = Input(UInt(3.W))
    val req = Flipped(new DecoupledIO(new FuncUnitReq(xLen)))
    val resp = new DecoupledIO(new FuncUnitResp(xLen))
    val set_vxsat = Output(Bool())
    val vGenIO = Flipped(new boom.lsu.VGenIO)
    
    val debug_wb_vec_valid = Output(Bool())
    val debug_wb_vec_wdata = Output(UInt((coreParams.vLen * 8).W))
    val debug_wb_vec_wmask = Output(UInt(8.W))
  })

  val reqQueue = Module(new Queue(new EnhancedFuncUnitReq(xLen, vLen), 4))
  val uOpMem = Module(new CombMemory(32, new MicroOp()))
  val vpuModule = Module(new tt_vpu_ovi(vLen))
  val maxIssueCredit = 16
  val issueCreditCnt = RegInit(maxIssueCredit.U(log2Ceil(maxIssueCredit + 1).W))
  issueCreditCnt := issueCreditCnt + vpuModule.io.issue_credit - vpuModule.io.issue_valid

  reqQueue.io.enq.valid := io.req.valid
  reqQueue.io.enq.bits.req := io.req.bits
  reqQueue.io.enq.bits.vconfig := io.vconfig
  reqQueue.io.enq.bits.vxrm := io.vxrm
  reqQueue.io.enq.bits.fcsr_rm := io.fcsr_rm

  val sbId = RegInit(0.U(5.W))
  sbId := sbId + vpuModule.io.issue_valid

  uOpMem.io.wrEn := reqQueue.io.deq.valid
  uOpMem.io.wrAddr := sbId
  uOpMem.io.wrData := reqQueue.io.deq.bits.req.uop
  uOpMem.io.rdAddr := vpuModule.io.completed_sb_id

  val respUop = uOpMem.io.rdData

  io := DontCare
  io.req.ready := reqQueue.io.deq.ready
  io.resp.valid := vpuModule.io.completed_valid
  io.resp.bits.data := vpuModule.io.completed_dest_reg
  io.resp.bits.uop := respUop
  io.resp.bits.uop.dst_rtype := Mux(respUop.dst_rtype === RT_VEC,
                                    RT_X,
                                    respUop.dst_rtype)
  io.resp.bits.uop.uses_stq := 0.B // Trick Rob to acknowledge Vector Store
  io.resp.bits.fflags.valid := vpuModule.io.completed_fflags.orR
  io.resp.bits.fflags.bits.uop.rob_idx := io.resp.bits.uop.rob_idx
  io.resp.bits.fflags.bits.flags := vpuModule.io.completed_fflags

  io.set_vxsat := DontCare
  io.debug_wb_vec_valid := vpuModule.io.debug_wb_vec_valid
  io.debug_wb_vec_wdata := vpuModule.io.debug_wb_vec_wdata
  io.debug_wb_vec_wmask := vpuModule.io.debug_wb_vec_wmask

/*
  faking mem sync start
*/
  //val fakeLoadStart = ShiftRegister (reqQueue.io.deq.valid && reqQueue.io.deq.bits.req.uop.uses_ldq, 200)

   val internalMemSyncStart = vpuModule.io.memop_sync_start
   val tryDeqVLSIQ = RegInit(false.B)
   val internalStoreWrite = vpuModule.io.store_valid
   

/*
  vLSIQ start
*/


  val inMiddle = RegInit(false.B)
  val outStandingReq = RegInit(0.U)
  val vOSud = Cat (vpuModule.io.memop_sync_start, vpuModule.io.memop_sync_end)
  when (vOSud === 1.U) {
    outStandingReq := outStandingReq - 1.U
  }.elsewhen (vOSud === 2.U) {
    outStandingReq := outStandingReq + 1.U 
  }

  val vLSIQueue = Module(new Queue(new EnhancedFuncUnitReq(xLen, vLen), 2))
  val sbIdQueue = Module(new Queue(UInt(5.W), 2))

  // this needs to be changed in the future to include load, just keep it this way for now
  vLSIQueue.io.enq.valid := issueCreditCnt =/= 0.U && reqQueue.io.deq.valid && (reqQueue.io.deq.bits.req.uop.uses_stq || reqQueue.io.deq.bits.req.uop.uses_ldq)
  vLSIQueue.io.enq.bits := reqQueue.io.deq.bits
  vLSIQueue.io.deq.ready := !inMiddle && ((outStandingReq =/= 0.U || internalMemSyncStart) || tryDeqVLSIQ)
  sbIdQueue.io.enq.valid := reqQueue.io.deq.valid && (reqQueue.io.deq.bits.req.uop.uses_stq || reqQueue.io.deq.bits.req.uop.uses_ldq)
  sbIdQueue.io.enq.bits := sbId
  sbIdQueue.io.deq.ready := !inMiddle && ((outStandingReq =/= 0.U || internalMemSyncStart) || tryDeqVLSIQ)
  when (!inMiddle) {
  when (vLSIQueue.io.deq.valid && vLSIQueue.io.deq.ready) {
    inMiddle := true.B 
  }.elsewhen ((outStandingReq =/= 0.U || internalMemSyncStart) && !vLSIQueue.io.deq.valid) {
    tryDeqVLSIQ := true.B 
    inMiddle := true.B 
  }.elsewhen (tryDeqVLSIQ && vLSIQueue.io.deq.valid) {
    tryDeqVLSIQ := false.B
    inMiddle := true.B 
  }
  }.elsewhen (vpuModule.io.memop_sync_end) {
    inMiddle := false.B
  }
  reqQueue.io.deq.ready := issueCreditCnt =/= 0.U && vLSIQueue.io.enq.ready
  val newVGenConfig = vLSIQueue.io.deq.valid && vLSIQueue.io.deq.ready && (vLSIQueue.io.deq.bits.req.uop.uses_stq || vLSIQueue.io.deq.bits.req.uop.uses_ldq)
/*
  vLSIQ end
*/

/*
  VDB start
*/
  val vdb = Module (new VDB(512, 64, 256, 4))
  
  vdb.io.writeValid := false.B 
//  vdb.io.writeData := 0.U 
  vdb.io.pop := false.B 
  vdb.io.last := false.B  
  vdb.io.configValid := false.B  

  vdb.io.writeValid := internalStoreWrite
  vdb.io.writeData := vpuModule.io.store_data
  vdb.io.sliceSize := 8.U 
  vdb.io.vlmul := 0.U

 

/*
   VDB end
*/
/*
   Vid Gen Start
*/
val vIdGen = Module (new VIdGen(32, 8))
 vIdGen.io.configValid := false.B 
 vIdGen.io.startID := DontCare
 vIdGen.io.startVD := DontCare  
 vIdGen.io.pop := false.B
 vIdGen.io.sliceSize := 8.U

val vAGen = Module (new VAgen (64, 65, 4))

  vAGen.io.configValid := false.B 
  vAGen.io.maskData := 0.U 
  vAGen.io.maskValid := false.B 
  vAGen.io.startAddr := DontCare
  vAGen.io.stride := DontCare
  vAGen.io.isStride := false.B 
  vAGen.io.isIndex := false.B 
  vAGen.io.isMask := false.B 
  vAGen.io.vl := 4.U
  vAGen.io.pop := false.B  
  vAGen.io.initialSliceSize := 0.U

  val vwhls = Module (new VWhLSDecoder (256))
  vwhls.io.nf := DontCare
  vwhls.io.wth := DontCare
  /*
      Decode Start
  */

  io.vGenIO.req.valid := false.B 
  io.vGenIO.req.bits := DontCare
  io.vGenIO.reqHelp.valid := false.B
  io.vGenIO.reqHelp.bits := DontCare 

  val vGenEnable  = RegInit(false.B)
  val vGenHold = Reg(new EnhancedFuncUnitReq(xLen, vLen))
  val sbIdHold = RegInit(0.U)
  val vDBcount = RegInit(0.U(3.W))
  val vDBud = Cat (vpuModule.io.store_valid, vdb.io.release)
  when (vDBud === 1.U) {
    vDBcount := vDBcount - 1.U
  }.elsewhen (vDBud === 2.U) {
    vDBcount := vDBcount + 1.U 
  }
  
  assert (vDBcount < 5.U)


  val s0l1 = RegInit(false.B)

  val strideDirHold = RegInit(true.B)

  val sliceSizeHold = RegInit(0.U)


  when (newVGenConfig && !vGenEnable) {
    vGenEnable := true.B 
    vGenHold.req.uop := vLSIQueue.io.deq.bits.req.uop
    sbIdHold := sbIdQueue.io.deq.bits 

    val instElemSize = vLSIQueue.io.deq.bits.req.uop.inst(14, 12)
    val vldDest = vLSIQueue.io.deq.bits.req.uop.inst(11, 7)
    val instNf = vLSIQueue.io.deq.bits.req.uop.inst(31, 29)
    val instMaskEnable = !vLSIQueue.io.deq.bits.req.uop.inst(25)  // 0: enable, 1 disable
    val isWholeStore = vLSIQueue.io.deq.bits.req.uop.inst(6, 0) === 39.U && vLSIQueue.io.deq.bits.req.uop.inst(24, 20) === 8.U && vLSIQueue.io.deq.bits.req.uop.inst(27, 26) === 0.U
    val isWholeLoad = vLSIQueue.io.deq.bits.req.uop.inst(6, 0) === 7.U && vLSIQueue.io.deq.bits.req.uop.inst(24, 20) === 8.U && vLSIQueue.io.deq.bits.req.uop.inst(27, 26) === 0.U
    val isStoreMask = vLSIQueue.io.deq.bits.req.uop.inst(6, 0) === 39.U && vLSIQueue.io.deq.bits.req.uop.inst(24, 20) === 11.U && vLSIQueue.io.deq.bits.req.uop.inst(27, 26) === 0.U
    val isLoadMask = vLSIQueue.io.deq.bits.req.uop.inst(6, 0) === 7.U && vLSIQueue.io.deq.bits.req.uop.inst(24, 20) === 11.U && vLSIQueue.io.deq.bits.req.uop.inst(27, 26) === 0.U
    

    vdb.io.configValid := vLSIQueue.io.deq.bits.req.uop.uses_stq
    vIdGen.io.configValid := vLSIQueue.io.deq.bits.req.uop.uses_ldq
    vIdGen.io.startID := 0.U
    s0l1 := vLSIQueue.io.deq.bits.req.uop.uses_ldq
    vAGen.io.configValid := true.B
    
    vdb.io.vlmul := vLSIQueue.io.deq.bits.vconfig.vtype.vlmul_mag
    vAGen.io.vl := vLSIQueue.io.deq.bits.vconfig.vl
    vAGen.io.startAddr := vLSIQueue.io.deq.bits.req.rs1_data
    vAGen.io.stride := vLSIQueue.io.deq.bits.req.rs2_data 
    vAGen.io.isMask := instMaskEnable
    when (isWholeLoad || isWholeStore) {
    vwhls.io.nf := instNf
    vwhls.io.wth := instElemSize 
    vAGen.io.vl := vwhls.io.overVl 
    vdb.io.vlmul := vwhls.io.overVlmul
    }.elsewhen (isStoreMask || isLoadMask) {
      vAGen.io.vl := (vLSIQueue.io.deq.bits.vconfig.vl + 7.U) >> 3
      vdb.io.vlmul := 0.U
    }
  
    // this is fine for now, change later for index store
    
    vIdGen.io.startVD := vldDest
    
    when (isWholeStore || isStoreMask || isLoadMask) {
      vAGen.io.initialSliceSize := 1.U 
    }.otherwise {
    when (instElemSize === 0.U) {
      vAGen.io.initialSliceSize := 1.U 
    }.elsewhen (instElemSize === 5.U){
      vAGen.io.initialSliceSize := 2.U 
    }.elsewhen (instElemSize === 6.U){
      vAGen.io.initialSliceSize := 4.U 
    }.otherwise{
      vAGen.io.initialSliceSize := 8.U 
    }
    }
  
    strideDirHold := 0.U 
    val instMop = vLSIQueue.io.deq.bits.req.uop.inst(27, 26)
    when (instMop === 0.U) {
      vAGen.io.isStride := false.B 
    }.elsewhen(instMop === 2.U) {
      vAGen.io.isStride := true.B 
      strideDirHold := vLSIQueue.io.deq.bits.req.rs2_data(31)
    }.otherwise {
      vAGen.io.isIndex := true.B
    }
  }

    vdb.io.sliceSize := vAGen.io.sliceSizeOut
    vIdGen.io.sliceSize := vAGen.io.sliceSizeOut
    
  

  io.vGenIO.req.valid := vGenEnable && ((!s0l1 && vDBcount =/= 0.U) || s0l1) && vAGen.io.canPop
  io.vGenIO.req.bits.uop := vGenHold.req.uop
  io.vGenIO.req.bits.data := Mux(s0l1, 0.U, vdb.io.outData) 
  io.vGenIO.req.bits.last := false.B 
  io.vGenIO.req.bits.addr := vAGen.io.outAddr

  io.vGenIO.reqHelp.bits.elemID := vIdGen.io.outID 
  io.vGenIO.reqHelp.bits.vRegID := vIdGen.io.outVD
  io.vGenIO.reqHelp.bits.sbId   := sbIdHold
  io.vGenIO.reqHelp.bits.strideDir := strideDirHold 
  io.vGenIO.reqHelp.bits.isMask := vAGen.io.isMaskOut
  io.vGenIO.reqHelp.bits.Mask := vAGen.io.currentMaskOut
  io.vGenIO.reqHelp.bits.isFake := vAGen.io.isFake

  val MemSyncEnd = io.vGenIO.resp.bits.vectorDone && io.vGenIO.resp.valid && inMiddle 
  val MemSbId = io.vGenIO.resp.bits.sbId
  val MemCredit = vdb.io.release 
  val MemVstart = 0.U

  

   
  
  val MEMLoadValid = WireInit(false.B)
  val MEMLoadData = WireInit(0.U(512.W))
  val MEMSeqId    = WireInit(0.U(34.W))

  val seqSbId = WireInit(0.U(5.W))   // 5
  val seqElCount = WireInit(1.U(7.W))      // 7
  val seqElOff = WireInit(0.U(6.W))        // 6
  val seqElId = WireInit(0.U(11.W)) // 11
  val seqVreg = WireInit(0.U(5.W)) // 5



  MEMSeqId := Cat (seqSbId, seqElCount, seqElOff, seqElId, seqVreg)

  MEMLoadValid := io.vGenIO.resp.valid && io.vGenIO.resp.bits.s0l1 && !io.vGenIO.resp.bits.vectorDone  // needs fixing later if we are overlapping

  val LSUReturnLoadValid = WireInit(false.B)
  
  LSUReturnLoadValid := io.vGenIO.resp.valid && io.vGenIO.resp.bits.s0l1 && !io.vGenIO.resp.bits.vectorDone  // needs fixing later if we are overlapping



  val vReturnData = Module(new VReturnData(512, 64))
  vReturnData.io.memSize := io.vGenIO.resp.bits.memSize
  vReturnData.io.lsuData := io.vGenIO.resp.bits.data
  vReturnData.io.strideDir := io.vGenIO.resp.bits.strideDir

  val fakeLoadReturnQueue = Module(new Queue(UInt(21.W), 8))
  fakeLoadReturnQueue.io.enq.valid := vAGen.io.popForce 
  fakeLoadReturnQueue.io.enq.bits := Cat(sbIdHold, vIdGen.io.outID, vIdGen.io.outVD)
  fakeLoadReturnQueue.io.deq.ready := false.B 
  MEMLoadValid := LSUReturnLoadValid || fakeLoadReturnQueue.io.deq.valid 

  val MEMReturnMaskValid = WireInit(false.B) 
  val MEMReturnMask = WireInit(0.U(64.W))
  val MEMMaskCredit = WireInit(false.B)


  when (LSUReturnLoadValid) {
    MEMLoadData := vReturnData.io.oviData
    seqElId := Cat(0.U(3.W), io.vGenIO.resp.bits.elemID)
    seqSbId := io.vGenIO.resp.bits.sbId
    seqVreg := io.vGenIO.resp.bits.vRegID
    MEMReturnMaskValid := io.vGenIO.resp.bits.isMask
    MEMReturnMask := io.vGenIO.resp.bits.Mask
  }.elsewhen (fakeLoadReturnQueue.io.deq.valid) {
    fakeLoadReturnQueue.io.deq.ready := true.B 
    MEMLoadData := 0.U 
    seqElId := fakeLoadReturnQueue.io.deq.bits (15, 5)
    seqSbId := fakeLoadReturnQueue.io.deq.bits (20, 16)
    seqVreg := fakeLoadReturnQueue.io.deq.bits (4, 0)
    MEMReturnMaskValid := true.B 
    MEMReturnMask := false.B 
  }



  io.vGenIO.req.bits.last := vAGen.io.last 

  when ((io.vGenIO.req.valid && io.vGenIO.req.ready) || vAGen.io.popForce) { 
                                                        
    vdb.io.pop := io.vGenIO.req.bits.uop.uses_stq
    vAGen.io.pop := true.B 
    vIdGen.io.pop := io.vGenIO.req.bits.uop.uses_ldq
    when (vAGen.io.last) {
      vGenEnable := false.B         
      vdb.io.last := io.vGenIO.req.bits.uop.uses_stq
    }
  }

  
  /*
      Decode End
  */

  vpuModule.io := DontCare
  vpuModule.io.clk := clock
  vpuModule.io.reset_n := ~reset.asBool
  vpuModule.io.issue_valid := reqQueue.io.deq.valid && reqQueue.io.deq.ready
  vpuModule.io.issue_inst := reqQueue.io.deq.bits.req.uop.inst
  vpuModule.io.issue_sb_id := sbId
  vpuModule.io.issue_scalar_opnd := Mux( (reqQueue.io.deq.bits.req.uop.lrs1_rtype === RT_FLT), reqQueue.io.deq.bits.req.rs3_data,
                                    Mux( (reqQueue.io.deq.bits.req.uop.uses_ldq ||
                                          reqQueue.io.deq.bits.req.uop.uses_stq             ), reqQueue.io.deq.bits.req.rs2_data,
                                                                                               reqQueue.io.deq.bits.req.rs1_data))
  vpuModule.io.issue_vcsr := Cat(
    0.U(1.W), // vill
    reqQueue.io.deq.bits.vconfig.vtype.vsew, // vsew
    reqQueue.io.deq.bits.vconfig.vtype.vlmul_mag, // vlmul
    reqQueue.io.deq.bits.fcsr_rm, // frm
    reqQueue.io.deq.bits.vxrm, // vxrm
    Cat(0.U((15-log2Ceil(vLen+1)).W),
        reqQueue.io.deq.bits.vconfig.vl), // vl
    0.U(14.W) // vstart
  )
  vpuModule.io.issue_vcsr_lmulb2 := reqQueue.io.deq.bits.vconfig.vtype.vlmul_sign
  vpuModule.io.dispatch_sb_id := sbId
  vpuModule.io.dispatch_next_senior := reqQueue.io.deq.valid && reqQueue.io.deq.ready
  vpuModule.io.dispatch_kill := 0.B
  vpuModule.io.memop_sync_end := MemSyncEnd
  vpuModule.io.store_credit := MemCredit

  vpuModule.io.load_seq_id := MEMSeqId
  vpuModule.io.load_data := MEMLoadData
  vpuModule.io.load_valid := MEMLoadValid
  vpuModule.io.load_mask := MEMReturnMask
  vpuModule.io.load_mask_valid := MEMReturnMaskValid


}

class tt_vpu_ovi (vLen: Int)(implicit p: Parameters) extends BlackBox(Map("VLEN" -> IntParam(vLen))) with HasBlackBoxResource {
  val io = IO(new Bundle {
    val clk = Input(Clock())
    val reset_n = Input(Bool())
    val issue_inst = Input(UInt(32.W))
    val issue_sb_id = Input(UInt(5.W))
    val issue_scalar_opnd = Input(UInt(64.W))
    val issue_vcsr = Input(UInt(40.W))
    val issue_vcsr_lmulb2 = Input(Bool()) // Added 1 more bit for vlmul
    val issue_valid = Input(Bool())
    val issue_credit = Output(Bool())
    val dispatch_sb_id = Input(UInt(5.W))
    val dispatch_next_senior = Input(Bool())
    val dispatch_kill = Input(Bool())
    val completed_valid = Output(Bool())
    val completed_sb_id = Output(UInt(5.W))
    val completed_fflags = Output(UInt(5.W))
    val completed_dest_reg = Output(UInt(64.W))
    val completed_vxsat = Output(Bool())
    val completed_vstart = Output(UInt(14.W))
    val completed_illegal = Output(Bool())
    val store_valid = Output(Bool())
    val store_data = Output(UInt(512.W))
    val store_credit = Input(Bool())
    val memop_sync_end = Input(Bool())
    val memop_sync_start = Output(Bool())
    val debug_wb_vec_valid = Output(Bool())
    val debug_wb_vec_wdata = Output(UInt((vLen * 8).W))
    val debug_wb_vec_wmask = Output(UInt(8.W))
    val load_seq_id = Input(UInt(34.W))
    val load_data = Input(UInt(512.W))
    val load_valid = Input (Bool())
    val load_mask = Input(UInt(64.W))
    val load_mask_valid = Input (Bool())
  })
  addResource("/vsrc/vpu/briscv_defines.h")
  addResource("/vsrc/vpu/tt_briscv_pkg.vh")
  addResource("/vsrc/vpu/autogen_riscv_imabfv.v")
  addResource("/vsrc/vpu/autogen_defines.h")
  addResource("/vsrc/vpu/tt_id.sv")
  addResource("/vsrc/vpu/tt_ex.sv")
  addResource("/vsrc/vpu/tt_lq.sv")
  addResource("/vsrc/vpu/tt_mem.sv")
  addResource("/vsrc/vpu/tt_vec.sv")
  addResource("/vsrc/vpu/tt_vec_iadd.sv")
  addResource("/vsrc/vpu/tt_vec_idp.sv")
  addResource("/vsrc/vpu/tt_vec_imul.sv")
  addResource("/vsrc/vpu/tt_vec_mul_dp.sv")
  addResource("/vsrc/vpu/tt_vec_regfile.sv")
  addResource("/vsrc/vpu/tt_vfp_unit.sv")
  addResource("/vsrc/vpu/tt_vfp_ex_unit.sv")
  addResource("/vsrc/vpu/tt_vfp_lane.sv")
  addResource("/vsrc/vpu/tt_vfp_encoder.sv")
  addResource("/vsrc/vpu/tt_vfp_encoder_lane.sv")
  addResource("/vsrc/vpu/tt_vfp_fma.sv")
  addResource("/vsrc/vpu/tt_vfp_red.sv")
  addResource("/vsrc/vpu/tt_popcnt.sv")
  addResource("/vsrc/vpu/tt_pipe_stage.sv")
  addResource("/vsrc/vpu/tt_rts_rtr_pipe_stage.sv")
  addResource("/vsrc/vpu/tt_cam_buffer.sv")
  addResource("/vsrc/vpu/tt_skid_buffer.sv")
  addResource("/vsrc/vpu/tt_ffs.sv")
  addResource("/vsrc/vpu/tt_ascii_instrn_decode.sv")
  addResource("/vsrc/vpu/tt_compare.sv")
  addResource("/vsrc/vpu/tt_decoded_mux.sv")
  addResource("/vsrc/vpu/tt_decoder.sv")
  addResource("/vsrc/vpu/tt_reshape.sv")
  addResource("/vsrc/vpu/tt_memop_fsm.sv")
  addResource("/vsrc/vpu/lrm_model.sv")
  addResource("/vsrc/vpu/tt_fifo.sv")
  addResource("/vsrc/vpu/tt_vpu_ovi.sv")  
  addResource("/vsrc/vpu/tt_vpu_ovi_assert.sv")  
  addResource("/vsrc/HardFloat/source/RISCV/HardFloat_specialize.v")
  addResource("/vsrc/HardFloat/source/RISCV/HardFloat_specialize.vi")
  addResource("/vsrc/HardFloat/source/HardFloat_consts.vi")
  addResource("/vsrc/HardFloat/source/HardFloat_localFuncs.vi")
  addResource("/vsrc/HardFloat/source/HardFloat_primitives.v")
  addResource("/vsrc/HardFloat/source/HardFloat_rawFN.v")
  addResource("/vsrc/HardFloat/source/addRecFN.v")
  addResource("/vsrc/HardFloat/source/compareRecFN.v")
  addResource("/vsrc/HardFloat/source/fNToRecFN.v")
  addResource("/vsrc/HardFloat/source/iNToRecFN.v")
  addResource("/vsrc/HardFloat/source/isSigNaNRecFN.v")
  addResource("/vsrc/HardFloat/source/mulAddRecFN.v")
  addResource("/vsrc/HardFloat/source/recFNToFN.v")
  addResource("/vsrc/HardFloat/source/recFNToIN.v")
  addResource("/vsrc/HardFloat/source/recFNToRecFN.v")
  
}

// M is not used for now, N is mask interface width (64), Depth is mask buffer width (4)
class VAgen(val M: Int, val N: Int, val Depth: Int)(implicit p: Parameters) extends Module {
  val io = IO(new Bundle {
    // inteface with the VPU
    val maskData = Input(UInt(N.W))
    val maskValid = Input(Bool())
    val release = Output (Bool())
    // interface with VPU decode
//    val sliceSize = Input(UInt(4.W))
    val initialSliceSize = Input(UInt(log2Ceil(M/8 + 1).W))
    val sliceSizeOut = Output(UInt(log2Ceil(M/8 + 1).W))
    val vl = Input(UInt(9.W))
    val configValid = Input(Bool())
    val startAddr = Input(UInt(64.W))
    val stride = Input(UInt(64.W))
    val isStride = Input(Bool())
    val isMask = Input(Bool())
    val isIndex = Input(Bool())
    val pop = Input(Bool())
    val outAddr = Output(UInt(40.W))
    val last = Output(Bool())
    val isFake = Output (Bool())
    val isMaskOut   = Output (Bool())
    val currentMaskOut = Output (UInt(N.W))
    val popForce = Output (Bool())
    val canPop = Output (Bool())

  })

//  val sliceSizeHold = Reg(UInt(4.W))
  val vlHold = Reg(UInt(9.W))

  val currentIndex = Reg(UInt(9.W))
  val currentAddr  = Reg(UInt(64.W))
  val stride  = Reg(UInt(64.W))
  val working = RegInit(false.B)
  val isStride = Reg(Bool())
  val isIndex = Reg(Bool())
  val isMask = Reg(Bool())
  val fakeHold = RegInit(false.B)

  val sliceSizeHold = RegInit(0.U(log2Ceil(M/8 + 1).W))
  io.sliceSizeOut := sliceSizeHold  // this is only for V0

  io.release := false.B 
  io.popForce := false.B 
  io.canPop := false.B 
  io.isMaskOut := isMask
  io.currentMaskOut := false.B 

  
  
  val indexAddr = WireInit(0.U(64.W))

  io.outAddr := Mux(isIndex, indexAddr(39, 0), currentAddr(39, 0))  // leave it for now, as we don't support index yet

  when (io.configValid) {
    sliceSizeHold := io.initialSliceSize
    when (io.vl === 0.U) {
    vlHold := 0.U
    fakeHold := true.B
    }.otherwise {
    vlHold := io.vl - 1.U
    }
    currentIndex := 0.U 
    currentAddr := io.startAddr
    isStride := io.isStride
    isIndex := io.isIndex 
    isMask := io.isMask
    stride := io.stride 
    working := true.B 
  }
  
  val currentMask = WireInit (true.B)
    
  val buffer = RegInit(VecInit(Seq.fill(Depth)(0.U(N.W))))
  val readPtr = RegInit(0.U(log2Ceil(Depth).W))
  val writePtr = RegInit(0.U(log2Ceil(Depth).W))
    

  val currentEntry = buffer(readPtr)

  when(io.maskValid) {
    buffer(writePtr) := io.maskData
    writePtr := WrapInc(writePtr, Depth)
   }
  currentMask := Mux(isIndex, currentEntry(64), currentEntry(currentIndex))

  val vMaskcount = RegInit(0.U(3.W))
    val vMaskud = Cat (io.maskValid, io.release)
    when (vMaskud === 1.U) {
      vMaskcount := vMaskcount - 1.U
    }.elsewhen (vMaskud === 2.U) {
      vMaskcount := vMaskcount + 1.U 
    }
  val hasMask = WireInit(false.B)
    hasMask := vMaskcount =/= 0.U

  indexAddr := currentAddr + currentEntry(63, 0)

  // TODO: disable popForce for last one but mask off

  io.popForce := working && !currentMask && ((isMask || isIndex) && hasMask)  && !io.last 
  val lastFake = working && !currentMask && ((isMask || isIndex) && hasMask)  && io.last 
  io.canPop := working && ((currentMask && ((isMask || isIndex) && hasMask)) || (!isMask && !isIndex) || lastFake)

  io.isFake := fakeHold || lastFake 

  io.last := (currentIndex === vlHold) && working
  when (isIndex) {
       when(io.pop || io.popForce) {
        readPtr := WrapInc(readPtr, Depth)
        io.release := true.B 
       }
    }.otherwise{
     when (io.pop || io.popForce) {
       when (io.last) {
    //     working := false.B 
    //     currentIndex := 0.U
         fakeHold := false.B
         readPtr := WrapInc(readPtr, Depth)
//         currentIndex := 0.U
         io.release := true.B 
       }.otherwise {
    //     currentIndex := currentIndex + 1.U
         when (isStride) {
            currentAddr := currentAddr + stride 
         }.otherwise { 
            currentAddr := currentAddr + io.sliceSizeOut 
         }    
       }
      }
    }
   when (io.pop || io.popForce) {
      when (io.last) {
         working := false.B 
         currentIndex := 0.U
      }.otherwise {
         currentIndex := currentIndex + 1.U
      }
   }


}

// M is max number of byte per VLEN (32), N is max number of byte per memory interface (8) 
class VIdGen(val M: Int, val N: Int)(implicit p: Parameters) extends Module {
  require(isPow2(M), "M must be a power of 2")
  require(isPow2(N), "N must be a power of 2")
  require(M >= N, "M must be greater than or equal to N")
  require(M % 8 == 0, "M must be a multiple of 8")
  require(N % 8 == 0, "N must be a multiple of 8")
  val S = log2Ceil(M + 1)
  val I = log2Ceil(M) + 3
  val K = log2Ceil(M)
  

  val io = IO(new Bundle {
    val configValid = Input(Bool())
    val startID = Input(UInt(I.W))
    val startVD = Input(UInt(5.W))
    val pop = Input(Bool())
    val sliceSize = Input(UInt(S.W))
    val outID = Output(UInt(I.W))
    val outVD = Output(UInt(5.W))
  }) 

  val currentID = RegInit(0.U(I.W))
  val currentVD = RegInit(0.U(5.W))
  val count = RegInit(0.U(S.W))

  when (io.configValid) {
    currentID := io.startID
    currentVD := io.startVD
    count := 0.U  // for now
  }
  io.outID := currentID
  io.outVD := currentVD
  when (io.pop) {
    //currentID := currentID + 1.U 
    when (count + io.sliceSize === M.U) {
      count := 0.U
 //     currentID := 0.U 
      currentVD := currentVD + 1.U
      currentID := 0.U
    }.otherwise{
      count := count + io.sliceSize
      currentID := currentID + 1.U 
    }
  }

}  


class VDB(val M: Int, val N: Int, val Vlen: Int, val Depth: Int)(implicit p: Parameters) extends Module {
  require(isPow2(M), "M must be a power of 2")
  require(isPow2(N), "N must be a power of 2")
  require(isPow2(Vlen), "Vlen must be a power of 2")
  require(M >= N, "M must be greater than or equal to N")
  require(M % 8 == 0, "M must be a multiple of 8")
  require(N % 8 == 0, "N must be a multiple of 8")
  val S = log2Ceil(N / 8 + 1)
  val I = log2Ceil(M / 8 + 1)
  val maxIndex = (M / 8)
  val safeLmul = log2Ceil(M/Vlen)  // 2 in our case, however this needs to be logged (LMUL = 2, but vlmul = 1)
  val preshift = log2Ceil(M/Vlen) // 1 in our case

  val io = IO(new Bundle {
    val configValid = Input(Bool())
    val writeValid = Input(Bool())
    val writeData = Input(UInt(M.W))
    val pop = Input(Bool())
    val last = Input(Bool())
    val vlmul = Input(UInt(3.W))
    val sliceSize = Input(UInt(S.W))
    val release = Output(Bool())
    val outData = Output(UInt(N.W))
  })

  val buffer = RegInit(VecInit(Seq.fill(Depth)(0.U(M.W))))
  val readPtr = RegInit(0.U(log2Ceil(Depth).W))
  val writePtr = RegInit(0.U(log2Ceil(Depth).W))
  val finalJump = RegInit(0.U((log2Ceil(Depth+1)).W))
  val currentIndex = Reg(UInt(I.W))
  val needJump = RegInit(false.B)
  val jumping = RegInit(false.B)
  val miniIndex = RegInit(0.U(log2Ceil(N+1).W))

  when(io.configValid) {
   currentIndex := 0.U
   miniIndex := 0.U
   needJump := false.B 
   when (io.vlmul > safeLmul.U) {
    needJump := false.B 
    finalJump := (1.U << (io.vlmul - preshift.U))
   }
  }

  val currentEntry = buffer(readPtr)

  when(io.writeValid) {
    buffer(writePtr) := io.writeData
    writePtr := WrapInc(writePtr, Depth)
  }

 val paddedEntry = Cat(0.U((N-8).W), currentEntry)
 val slices = VecInit(Seq.tabulate(M/8)(i => paddedEntry(i*8+N-1, i*8)))
 // val slices = VecInit(Seq.tabulate(M/N)(i => paddedEntry(i*64+N-1, i*64)))
  io.outData := slices(currentIndex) 
 
  io.release := false.B 
  when (io.pop) {
    when (io.last) {
      readPtr := WrapInc(readPtr, Depth)
      when(needJump) {
      finalJump := finalJump - 1.U
      }
      currentIndex := 0.U
      io.release := true.B 
      when (finalJump > 1.U) {
        jumping := true.B 
      }
    } .otherwise {
     when (currentIndex + io.sliceSize === maxIndex.U) {
          currentIndex := 0.U
          readPtr := WrapInc(readPtr, Depth)
          io.release := true.B 
          when(needJump) {
            finalJump := finalJump - 1.U
          }
        }.otherwise {
          currentIndex := currentIndex + io.sliceSize
        }
    }
  }
  when (jumping) {
    readPtr := WrapInc(readPtr, Depth)
    finalJump := finalJump - 1.U
    io.release := true.B 
    when (finalJump === 1.U) {
      jumping := false.B 
    }
  }
}

class VWhLSDecoder(val M: Int) extends Module {
  val Mbyte = M/8
  val io = IO(new Bundle {
    val nf = Input(UInt(3.W))
    val wth = Input(UInt(3.W))
    val overVl = Output(UInt(9.W))
    val overVlmul = Output(UInt(3.W))
  })

  val nf_wth = Cat(io.nf, io.wth)

  io.overVl := MuxLookup(nf_wth, 0.U, Array(
    0.U  -> (Mbyte.U),
    5.U  -> (Mbyte.U >> 1),
    6.U  -> (Mbyte.U >> 2),
    7.U  -> (Mbyte.U >> 3),
    8.U  -> (Mbyte.U << 1),
    13.U -> (Mbyte.U),
    14.U -> (Mbyte.U >> 1),
    15.U -> (Mbyte.U >> 2),
    24.U -> (Mbyte.U << 2),
    29.U -> (Mbyte.U << 1),
    30.U -> (Mbyte.U),
    31.U -> (Mbyte.U >> 1),
    56.U -> (Mbyte.U << 3),
    61.U -> (Mbyte.U << 2),
    62.U -> (Mbyte.U << 1),
    63.U -> (Mbyte.U)
  ))
  io.overVlmul := 0.U
  switch(io.nf) {
    is (0.U) { io.overVlmul := 0.U }
    is (1.U) { io.overVlmul := 1.U }
    is (3.U) { io.overVlmul := 2.U }
    is (7.U) { io.overVlmul := 3.U }
  }
}


// M is the return bus width: 512 for now, N is the DMEM width: 64 for now
class VReturnData (val M: Int, val N: Int) (implicit p: Parameters) extends Module {
    val io = IO(new Bundle {
    val lsuData = Input(UInt(N.W))
    val oviData = Output(UInt(M.W))
    // 0 for pos, 1 for neg
    val strideDir     = Input (Bool())
    val memSize = Input (UInt(2.W))
  })
    io.oviData := 0.U 
    when (io.strideDir){  // negative
       when (io.memSize === 0.U) {
        io.oviData := Cat(io.lsuData (7, 0), 0.U(504.W)) 
       }.elsewhen (io.memSize === 1.U) {
        io.oviData := Cat(io.lsuData (15, 0), 0.U(496.W))       
       }.elsewhen (io.memSize === 2.U) {
        io.oviData := Cat(io.lsuData (31, 0), 0.U(480.W))
       }.elsewhen (io.memSize === 3.U) {
        io.oviData := Cat(io.lsuData (63, 0), 0.U(448.W))
       }
    }.otherwise {
      when (io.memSize === 0.U) {
        io.oviData := Cat(0.U, io.lsuData (7, 0)) 
       }.elsewhen (io.memSize === 1.U) {
        io.oviData := Cat(0.U, io.lsuData (15, 0))       
       }.elsewhen (io.memSize === 2.U) {
        io.oviData := Cat(0.U, io.lsuData (31, 0))
       }.elsewhen (io.memSize === 3.U) {
        io.oviData := Cat(0.U, io.lsuData (63, 0))
       }
    }
}
