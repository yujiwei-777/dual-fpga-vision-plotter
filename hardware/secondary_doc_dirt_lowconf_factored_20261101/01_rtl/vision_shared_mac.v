// The ordinary CNN and PCB jobs are mutually exclusive at the controller
// level.  Keep their multipliers physically separate: selecting operands in
// front of one DSP put the workspace ERAM output, a purpose mux, and the DSP
// on one 125 MHz path.  The unused multiplier is idle for each job, while the
// separate datapaths preserve the exact signed product values and remove the
// high-fanout purpose mux from both timing cones.
(* keep_hierarchy = "yes" *) module vision_shared_mac(
    input  wire               pcb_select,
    input  wire signed [15:0] cnn_a,
    input  wire signed [7:0]  cnn_w,
    input  wire signed [15:0] pcb_a,
    input  wire signed [7:0]  pcb_w,
    output wire signed [23:0] product,
    output wire signed [23:0] cnn_product,
    output wire signed [23:0] pcb_product
);
    wire signed [23:0] cnn_product_i = cnn_a * cnn_w;
    wire signed [23:0] pcb_product_i = pcb_a * pcb_w;

    assign cnn_product = cnn_product_i;
    assign pcb_product = pcb_product_i;
    // Compatibility output for older harnesses that observe the selected
    // product.  Classifier cores use their dedicated outputs above.
    assign product = pcb_select ? pcb_product_i : cnn_product_i;
endmodule
