// The task controller locks pcb_select before either classifier starts.
// Ordinary activations fit signed9; restored binary PCB activations need16.
// Independent DSP inputs remove the purpose mux from both timing cones.
// Product timing remains combinational:
// cnn_core already supplies the exact RAM/product capture pipeline, so adding
// another register here would shift its continuous per-tap product stream.
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
    wire signed [8:0] cnn_operand = cnn_a[8:0];
    (* use_dsp="yes" *) wire signed [16:0] cnn_product_i = cnn_operand * cnn_w;
    (* use_dsp="yes" *) wire signed [23:0] pcb_product_i = pcb_a * pcb_w;
    wire signed [23:0] cnn_product_ext = {{7{cnn_product_i[16]}},cnn_product_i};
    assign product=pcb_select ? pcb_product_i : cnn_product_ext;
    assign cnn_product=cnn_product_ext;
    assign pcb_product=pcb_product_i;
endmodule
