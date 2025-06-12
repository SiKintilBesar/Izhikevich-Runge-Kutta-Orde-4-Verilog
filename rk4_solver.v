module rk4_solver(
    input wire clk,              // Clock input
    input wire reset,            // Reset signal
    input wire start,            // Start signal for computation
    input wire [15:0] v_in,      // Membrane potential input
    input wire [15:0] u_in,      // Recovery variable input
    input wire [15:0] I_in,      // Input current
    input wire [15:0] a_param,   // Parameter a
    input wire [15:0] b_param,   // Parameter b
    input wire [15:0] h_step,    // Step size h
    output reg [15:0] v_out,     // Next membrane potential
    output reg [15:0] u_out,     // Next recovery variable
    output reg [15:0] k1v_out,
    output reg [15:0] k2v_out,
    output reg [15:0] k3v_out,
    output reg [15:0] k4v_out,
    output reg [15:0] k1u_out,
    output reg [15:0] k2u_out,
    output reg [15:0] k3u_out,
    output reg [15:0] k4u_out,
    output reg [15:0] vinc_out,
    output reg [15:0] uinc_out,
    output reg [15:0] ksumv_out,
    output reg [15:0] hdiv_out,
    output reg spike,            // Spike detection
    output reg done              // Computation done signal
);

    // Fixed-point math utilities
    // Multiply two 9.7 fixed-point numbers and return a 9.7 result
    function [15:0] multiply;
        input [15:0] a;
        input [15:0] b;
        reg [31:0] result;
        begin
            result = (a * b) >>> 7; // Multiply and shift right to keep 9.7 format
            multiply = result[15:0];
        end
    endfunction
    
    // Add two 9.7 fixed-point numbers
    function [15:0] add;
        input [15:0] a;
        input [15:0] b;
        begin
            add = a + b;
        end
    endfunction
    
    // Subtract two 9.7 fixed-point numbers
    function [15:0] subtract;
        input [15:0] a;
        input [15:0] b;
        begin
            subtract = a - b;
        end
    endfunction
    
    // Function for dv/dt = 0.04v² + 5v + 140 - u + I
    function [15:0] f_v;
        input [15:0] v;
        input [15:0] u;
        input [15:0] I;
        reg [15:0] v_squared;
        reg [15:0] term1, term2, term3;
        begin
            // Constants in 9.7 fixed point
            // 0.04 = 0000000000101001
            // 5 = 0000010100000000
            // 140 = 0100011000000000
            
            v_squared = multiply(v, v);
            term1 = multiply(16'b0000000000000101, v_squared);   // 0.04v²
            term2 = multiply(16'b0000001010000000, v);           // 5v
            term3 = add(16'b0100011000000000, I);                // 140 + I
            
            f_v = add(add(term1, term2), subtract(term3, u));
        end
    endfunction
    
    // Function for du/dt = a(bv - u)
    function [15:0] f_u;
        input [15:0] v;
        input [15:0] u;
        input [15:0] a;
        input [15:0] b;
        reg [15:0] b_times_v;
        begin
            b_times_v = multiply(b, v);
            f_u = multiply(a, subtract(b_times_v, u));
        end
    endfunction

    // Threshold for spike detection (30mV in fixed point)
    parameter [15:0] THRESHOLD = 16'b0000111100000000;

    // State machine states
    localparam IDLE = 4'b0000;
    localparam CALC_K1 = 4'b0001;
    localparam DIV_1 = 4'b0010;
    localparam CALC_TEMP1 = 4'b0011;
    localparam CALC_K2 = 4'b0100;
    localparam DIV_2 = 4'b0101;
    localparam CALC_TEMP2 = 4'b0110;
    localparam CALC_K3 = 4'b0111;
    localparam CALC_TEMP3 = 4'b1000;
    localparam CALC_K4 = 4'b1001;
    localparam DIV_3 = 4'b1010;
    localparam CALC_FINAL = 4'b1011;
    localparam DONE = 4'b1100;

    // Internal state registers
    reg [3:0] state;
    reg [15:0] k1_v, k1_u, k2_v, k2_u, k3_v, k3_u, k4_v, k4_u;
    reg [15:0] v_temp1, u_temp1, v_temp2, u_temp2, v_temp3, u_temp3;
    reg [15:0] k2_v_doubled, k2_u_doubled, k3_v_doubled, k3_u_doubled;
    reg [15:0] k_sum_v, k_sum_u;
    reg [15:0] h_div_2, h_div_6;
    reg [15:0] v_inc, u_inc;
    reg [15:0] v_next, u_next;
	 reg [15:0] I_in1, I_in2;
    
    // Binary divider signals
    reg div_start;
    reg [15:0] div_dividend, div_divisor;
    wire [15:0] div_quotient;
    wire div_done;
    
    // Instantiate binary divider module
    binary_divider divider (
        .clk(clk),
        .reset(reset),
        .start(div_start),
        .dividend(div_dividend),
        .divisor(div_divisor),
        .quotient(div_quotient),
        .done(div_done)
    );
    
    // RK4 computation state machine
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            div_start <= 0;
            // Reset all intermediate values
            k1_v <= 0; k1_u <= 0;
            k2_v <= 0; k2_u <= 0;
            k3_v <= 0; k3_u <= 0;
            k4_v <= 0; k4_u <= 0;
            v_temp1 <= 0; u_temp1 <= 0;
            v_temp2 <= 0; u_temp2 <= 0;
            v_temp3 <= 0; u_temp3 <= 0;
            h_div_2 <= 0; h_div_6 <= 0;
            v_inc <= 0; u_inc <= 0;
            v_next <= 0; u_next <= 0;
            k_sum_v <= 0; k_sum_u <= 0;
				I_in1 <= 0; I_in2 <= 0;
            // Reset outputs
            v_out <= 0; u_out <= 0;
            k1v_out <= 0; k2v_out <= 0; k3v_out <= 0; k4v_out <= 0;
            k1u_out <= 0; k2u_out <= 0; k3u_out <= 0; k4u_out <= 0;
            vinc_out <= 0; uinc_out <= 0;
            ksumv_out <= 0; hdiv_out <= 0;
            spike <= 0;
				
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        // Calculate k1
                        k1_v <= f_v(v_in, u_in, I_in);
                        k1_u <= f_u(v_in, u_in, a_param, b_param);
                        state <= CALC_K1;
                    end
                    done <= 0;
                end
                
                CALC_K1: begin
                    div_start <= 0;
                    h_div_2 <= (h_step >>> 1);
                    state <= DIV_1;
                end
                
                DIV_1: begin
                    // Calculate temp values for k2
                    v_temp1 <= add(v_in, multiply(h_div_2, k1_v));
                    u_temp1 <= add(u_in, multiply(h_div_2, k1_u));
						  I_in1 <= add(I_in, h_div_2);
						  I_in2 <= add(I_in, h_step);
                    state <= CALC_TEMP1;
                end
                
                CALC_TEMP1: begin
                    // Calculate k2
                    k2_v <= f_v(v_temp1, u_temp1, I_in1);
                    k2_u <= f_u(v_temp1, u_temp1, a_param, b_param);
                    state <= CALC_K2;
                end
                
                CALC_K2: begin
                    // Calculate temp values for k3
                    v_temp2 <= add(v_in, multiply(h_div_2, k2_v));
                    u_temp2 <= add(u_in, multiply(h_div_2, k2_u));
                    state <= DIV_2;
                end
                
                DIV_2: begin
                    // Calculate k3
                    k3_v <= f_v(v_temp2, u_temp2, I_in1);
                    k3_u <= f_u(v_temp2, u_temp2, a_param, b_param);
                    state <= CALC_TEMP2;
                end
                
                CALC_TEMP2: begin
                    // Calculate temp values for k4
                    v_temp3 <= add(v_in, multiply(h_step, k3_v));
                    u_temp3 <= add(u_in, multiply(h_step, k3_u));
                    state <= CALC_K3;
                end
                
                CALC_K3: begin
                    // Calculate k4
                    k4_v <= f_v(v_temp3, u_temp3, I_in2);
                    k4_u <= f_u(v_temp3, u_temp3, a_param, b_param);
                    state <= CALC_TEMP3;
                end
                
                CALC_TEMP3: begin
                    // Double k2 and k3 values
                    k2_v_doubled <= k2_v <<< 1; // 2*k2_v
                    k2_u_doubled <= k2_u <<< 1; // 2*k2_u
                    k3_v_doubled <= k3_v <<< 1; // 2*k3_v
                    k3_u_doubled <= k3_u <<< 1; // 2*k3_u
                    state <= CALC_K4;
                end
                
                CALC_K4: begin
                    // Calculate weighted sum of k values
                    k_sum_v <= add(k1_v, add(k4_v, add(k2_v_doubled, k3_v_doubled)));
                    k_sum_u <= add(k1_u, add(k4_u, add(k2_u_doubled, k3_u_doubled)));
                    
                    // Start division to get h/6
                    div_dividend <= h_step;
                    div_divisor <= 16'd768;  // Divisor is 6
                    div_start <= 1;
                    state <= DIV_3;
                end
                
                DIV_3: begin
                    div_start <= 0;  // Clear divider start signal
                    if (div_done) begin
                        // Save h/6
                        h_div_6 <= div_quotient;
                        state <= CALC_FINAL;
                    end
                end
                
                CALC_FINAL: begin
                    // Calculate increments
                    v_inc <= multiply(h_div_6, k_sum_v);
                    u_inc <= multiply(h_div_6, k_sum_u);
                    
                    // Calculate next values
                    v_next <= add(v_in, multiply(h_div_6, k_sum_v));
                    u_next <= add(u_in, multiply(h_div_6, k_sum_u));
                    
                    state <= DONE;
                end
                
                DONE: begin
                    // Set outputs
                    v_out <= v_next;
                    u_out <= u_next;
                    k1v_out <= k1_v;
                    k2v_out <= k2_v;
                    k3v_out <= k3_v;
                    k4v_out <= k4_v;
                    k1u_out <= k1_u;
                    k2u_out <= k2_u;
                    k3u_out <= k3_u;
                    k4u_out <= k4_u;
                    vinc_out <= v_inc;
                    uinc_out <= u_inc;
                    ksumv_out <= k_sum_v;
                    hdiv_out <= h_div_6;
                    
                    // Detect spike
                    spike <= (v_next >= THRESHOLD) ? 1'b1 : 1'b0;
                    
                    // Signal completion
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
