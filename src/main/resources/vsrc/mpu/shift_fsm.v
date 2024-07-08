module shift_fsm #(parameter ml = 2) (
    input clk,
    input reset,
    input c_valid,
    input ab_valid,
    output reg en_c,
    output reg en_ab
);
    // States of the FSM    // States of the FSM
    parameter OPACC    = 2'b00,
              LD_C          = 2'b10;
    reg [1:0] next_state;
    reg [1:0] current_state;

    reg [3:0] shift_counter;

    // FSM state transition
    always @(posedge clk or posedge reset) begin
        if (reset) current_state <= OPACC;
        else current_state <= next_state;
    end

    // FSM next state logic
    always @(*) begin
        case (current_state)
            OPACC: begin
                if (c_valid) next_state = LD_C;
                else next_state = OPACC;
            end
            LD_C: begin
                if (shift_counter == ml - 1) next_state = OPACC;
                else next_state = LD_C;
            end
            default: begin
                next_state = OPACC;
            end
        endcase
    end

    // FSM output logic and internal shift register control
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            shift_counter <= 0;
            en_c <= 0;
            en_ab <= 0;
        end else begin
            case (current_state)
                OPACC: begin
                    en_c <= 0;
                    if (ab_valid) en_ab <= 1;
                end
                LD_C: begin
                    shift_counter <= shift_counter + 1;
                    en_c <= 1;
                end
            endcase
        end
    end
endmodule
