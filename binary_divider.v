module binary_divider (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [15:0] dividend,  // Input dalam format fixed-point 9.7
    input wire [15:0] divisor,   // Input dalam format fixed-point 9.7
    output reg [15:0] quotient,  // Output dalam format fixed-point 9.7
    output reg done
);

    // Parameter untuk representasi fixed-point 9.7
    parameter INTEGER_BITS = 9;
    parameter FRACTION_BITS = 7;
    parameter TOTAL_BITS = INTEGER_BITS + FRACTION_BITS;
    
    // State machine states
    localparam IDLE = 2'b00;
    localparam SETUP = 2'b01;
    localparam DIVIDE = 2'b10;
    localparam FINISH = 2'b11;
    
    // Internal registers
    reg [1:0] state;
    reg [5:0] count;  // Counter untuk iterasi
    reg [31:0] divisor_extended;  // Divisor yang di-extend (shift left)
    reg [31:0] remainder;         // Sisa pembagian dan hasil sementara
    
    // Algoritma pembagian
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            quotient <= 0;
            count <= 0;
            remainder <= 0;
            divisor_extended <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= SETUP;
                        done <= 0;
                    end
                end
                
                SETUP: begin
                    // Setup initial values for division
                    // Extend dividend to 32-bit untuk operasi pembagian
                    remainder <= {16'b0, dividend};
                    // Shift divisor left for proper fixed-point alignment
                    divisor_extended <= {divisor, 16'b0};
                    count <= TOTAL_BITS * 2; // Double untuk precision
                    quotient <= 0;
                    state <= DIVIDE;
                end
                
                DIVIDE: begin
                    if (count > 0) begin
                        // Try to subtract and update quotient bit
                        if (remainder >= divisor_extended) begin
                            remainder <= remainder - divisor_extended;
                            quotient <= {quotient[14:0], 1'b1};
                        end else begin
                            quotient <= {quotient[14:0], 1'b0};
                        end
                        
                        // Shift divisor right for next iteration
                        divisor_extended <= {1'b0, divisor_extended[31:1]};
                        count <= count - 1;
                    end else begin
                        state <= FINISH;
                    end
                end
                
                FINISH: begin
                    // Result is ready
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
