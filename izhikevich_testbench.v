module izhikevich_testbench;
    // Parameters
    parameter CLK_PERIOD = 10; // Clock period in ns
    parameter SIM_TIME = 10000; // Simulation time in clock cycles
    
    // Inputs
    reg clk;
    reg rst;
    reg [15:0] I_in;

    // Outputs
    wire [15:0] v_out;
    wire [15:0] u_out;
    wire [15:0] k1v_out, k2v_out, k3v_out, k4v_out;
    wire [15:0] k1u_out, k2u_out, k3u_out, k4u_out;
    wire [15:0] uinc_out, vinc_out;
    wire [15:0] ksumv_out, hdiv_out;
    wire spike_out;

    // File descriptor
    integer csv_file;

    // Instantiate neuron model
    izhikevich_model uut (
        .clk(clk),
        .rst(rst),
        .I_in(I_in),
        .v_out(v_out),
        .u_out(u_out),
        .k1v_out(k1v_out), .k2v_out(k2v_out), .k3v_out(k3v_out), .k4v_out(k4v_out),
        .k1u_out(k1u_out), .k2u_out(k2u_out), .k3u_out(k3u_out), .k4u_out(k4u_out),
        .vinc_out(vinc_out),
        .uinc_out(uinc_out),
        .ksumv_out(ksumv_out),
        .hdiv_out(hdiv_out),
        .spike_out(spike_out)
    );

    // Convert fixed-point to real
    real v_real, u_real, I_real;
    real k1v_real, k2v_real, k3v_real, k4v_real;
    real k1u_real, k2u_real, k3u_real, k4u_real;
    real vinc_real, uinc_real, ksumv_real, hdiv_real;

    always @* begin
        v_real     = $signed(v_out) / 128.0;
        u_real     = $signed(u_out) / 128.0;
        I_real     = $signed(I_in) / 128.0;

        k1v_real   = $signed(k1v_out) / 128.0;
        k2v_real   = $signed(k2v_out) / 128.0;
        k3v_real   = $signed(k3v_out) / 128.0;
        k4v_real   = $signed(k4v_out) / 128.0;

        k1u_real   = $signed(k1u_out) / 128.0;
        k2u_real   = $signed(k2u_out) / 128.0;
        k3u_real   = $signed(k3u_out) / 128.0;
        k4u_real   = $signed(k4u_out) / 128.0;

        vinc_real  = $signed(vinc_out) / 128.0;
        uinc_real  = $signed(uinc_out) / 128.0;
        ksumv_real = $signed(ksumv_out) / 128.0;
        hdiv_real  = $signed(hdiv_out) / 128.0;
    end

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Generate square wave input current
    integer cycle_count = 0;
    parameter SQUARE_PERIOD = 10000;

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if ((cycle_count % SQUARE_PERIOD) < (SQUARE_PERIOD / 2)) begin
            I_in <= 16'b0000010100000000; // I = 10 (fixed point)
        end else begin
            I_in <= 16'b0000000000000000; // I = 0
        end
    end

    // Test sequence
    initial begin
        // Reset
        rst = 1;
        I_in = 0;

        // Open CSV file
        csv_file = $fopen("izhikevich_output.csv", "w");
        if (csv_file) begin
            $fwrite(csv_file, "time_ns,v_real,u_real,I_real,spike\n");
        end else begin
            $display("Gagal membuka file CSV.");
            $finish;
        end

        // Apply reset
        #(CLK_PERIOD * 10);
        rst = 0;

        // Run simulation
        #(CLK_PERIOD * SIM_TIME);

        // Close CSV and end
        $fclose(csv_file);
        $display("Simulation completed");
        $finish;
    end

    // Monitor and write to CSV
    integer spike_count = 0;
    always @(posedge clk) begin
        if (spike_out)
            spike_count = spike_count + 1;

        if ((cycle_count % 500) == 0 || spike_out) begin
            $display("Time: %0t ns, V: %0.4f, U: %0.4f, I: %0.4f, Spike: %0d, Total Spikes: %0d",
                     $time, v_real, u_real, I_real, spike_out, spike_count);
        end

        // Write to CSV every cycle
        $fwrite(csv_file, "%0t,%0.4f,%0.4f,%0.4f,%0d\n",
                $time, v_real, u_real, I_real, spike_out);
    end

    // Dump waveform
    initial begin
        $dumpfile("izhikevich_sim.vcd");
        $dumpvars(0, izhikevich_testbench);
        $dumpvars(1, v_real, u_real, I_real);
    end
endmodule
