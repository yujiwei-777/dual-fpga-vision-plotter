// The task controller locks pcb_select before either classifier starts.
// Ordinary activations are signed 8-bit; pose7 activations span -128..255.
// Both therefore fit a signed 9x8 DSP. Product timing remains combinational:
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
    wire signed [8:0] operand_a = pcb_select ? pcb_a[8:0] : cnn_a[8:0];
    wire signed [7:0] operand_w = pcb_select ? pcb_w : cnn_w;
    (* use_dsp="yes" *) wire signed [16:0] product_i = operand_a * operand_w;
    wire signed [23:0] product_ext = {{7{product_i[16]}},product_i};
    assign product=product_ext;
    assign cnn_product=product_ext;
    assign pcb_product=product_ext;
endmodule
