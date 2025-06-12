module izhikevich_model(
    input wire clk,              // Clock input
    input wire rst,              // Reset input
    input wire [15:0] I_in,      // Input current (16-bit fixed point)
    output wire [15:0] v_out,    // Membrane potential output
    output wire [15:0] u_out,    // Recovery variable output
    output wire [15:0] k1v_out,
    output wire [15:0] k2v_out,
    output wire [15:0] k3v_out,
    output wire [15:0] k4v_out,
    output wire [15:0] k1u_out,
    output wire [15:0] k2u_out,
    output wire [15:0] k3u_out,
    output wire [15:0] k4u_out,
    output wire [15:0] vinc_out,
    output wire [15:0] uinc_out,
    output wire [15:0] ksumv_out,
    output wire [15:0] hdiv_out,
    output wire spike_out        // Spike output signal
);
    // Fixed-point representation: 9.7 format
    // 9 bits for integer part, 7 bits for fractional part
    
    // Tonic spiking neuron parameters (fixed point 9.7)
    // a = 0.02, b = 0.2, c = -65, d = 6
    parameter [15:0] a_param = 16'b0000000000000011;    // 0.02 in fixed point
    parameter [15:0] b_param = 16'b0000000000011010;    // 0.2 in fixed point
    parameter signed [15:0] c_param = 16'b1101111110000000;    // -65 in fixed point
    parameter [15:0] d_param = 16'b0000001100000000;    // 6 in fixed point
    
    // Step size for RK4 (fixed point 9.7)
    parameter [15:0] h_step = 16'b0000000000000010;     // 0.015 in fixed point
    
    // State variables
    reg signed[15:0] v, u;
    wire signed [15:0] v_next, u_next;
    wire spike;
    wire solver_done;
    reg solver_start;
    
    // State machine for managing RK4 solver
    localparam WAITING = 2'b00;
    localparam SOLVING = 2'b01;
    localparam UPDATE = 2'b10;
    
    reg [1:0] state;
    
    // Instantiate the RK4 solver module
    rk4_solver rk4_inst (
        .clk(clk),
        .reset(rst),
        .start(solver_start),
        .v_in(v),
        .u_in(u),
        .I_in(I_in),
        .a_param(a_param),
        .b_param(b_param),
        .h_step(h_step),
        .v_out(v_next),
        .u_out(u_next),
        .k1v_out(k1v_out),
        .k2v_out(k2v_out),
        .k3v_out(k3v_out),
        .k4v_out(k4v_out),
        .k1u_out(k1u_out),
        .k2u_out(k2u_out),
        .k3u_out(k3u_out),
        .k4u_out(k4u_out),
        .vinc_out(vinc_out),
        .uinc_out(uinc_out),
        .ksumv_out(ksumv_out),
        .hdiv_out(hdiv_out),
        .spike(spike),
        .done(solver_done)
    );
    
    // Sequential logic for state machine and updating state variables
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            v <= 16'b1101111110000000;    // -65 in fixed point
            u <= 16'b0000000000000000;    // 0 in fixed point
            solver_start <= 0;
            state <= WAITING;
        end else begin
            case (state)
                WAITING: begin
                    // Start the solver at each new cycle
                    solver_start <= 1;
                    state <= SOLVING;
                end
                
                SOLVING: begin
                    // Wait for solver to finish
                    solver_start <= 0;
                    if (solver_done) begin
                        state <= UPDATE;
                    end
                end
                
                UPDATE: begin
                    if (spike) begin
                        // Reset membrane potential and update recovery variable
                        v <= c_param;
                        u <= u_next + d_param;
                    end else begin
                        v <= v_next;
                        u <= u_next;
                    end
                    state <= WAITING;
                end
            endcase
        end
    end
    
    // Assign outputs
    assign v_out = v;
    assign u_out = u;
    assign spike_out = spike;
endmodule
