module shift_fsm #(parameter ml = 2) (
    input clk,
    input reset,
    input c_valid,
    input ab_valid,
    output logic en_c,
    output logic en_ab
);
    // States of the FSM    // States of the FSM
    parameter OPACC = 1'b1,
              LD_C  = 1'b0;
    logic next_state;
    logic current_state;
    logic [$clog2(ml)-1:0] shift_counter;
    logic [$clog2(ml)-1:0] next_shift_counter;

    // FSM state transition
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= LD_C;
            shift_counter <= 0;
        end
        else begin 
            current_state <= next_state;
            shift_counter <= next_shift_counter;
        end
    end

    // FSM next state logic
    always @(*) begin
        case (current_state)
            LD_C: begin
                if (shift_counter == ml-1) begin
                    next_state = OPACC;
                    next_shift_counter = shift_counter;
                end
                else if (c_valid) begin
                    next_state = LD_C;
                    next_shift_counter = shift_counter + 1;
                end
                else begin
                    next_state = LD_C;
                    next_shift_counter = shift_counter + 1;
                end
            end
            OPACC: begin
                if (ab_valid) begin
                    next_state = OPACC;
                    next_shift_counter = shift_counter;
                end
                else if (c_valid) begin
                    next_state = LD_C;
                    next_shift_counter = 0;
                end
            end
            default: begin
                next_state = LD_C;
                next_shift_counter = shift_counter;
            end
        endcase
    end

    assign next_shift_counter = shift_counter + 1;

    assign en_c = (current_state==LD_C) && c_valid;
    assign en_ab = (current_state==OPACC) && ab_valid;
    
endmodule

