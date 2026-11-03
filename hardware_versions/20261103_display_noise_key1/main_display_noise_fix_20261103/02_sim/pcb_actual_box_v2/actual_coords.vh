    wire S_use_multi_box = S_multi_px_valid && !S_pcb_window_on;
    wire [10:0] S_box_x0 = S_use_multi_box ? S_multi_px_boxes[10:0] : S_show_x0;
    wire [10:0] S_box_x1 = S_use_multi_box ? S_multi_px_boxes[42:32]-11'd1 : S_show_x1;
    wire [10:0] S_box_cx = S_use_multi_box ? S_multi_cx : S_show_cx;
    wire [9:0] S_box_y0 = S_use_multi_box ? S_multi_px_boxes[25:16] : S_show_y0;
    wire [9:0] S_box_y1 = S_use_multi_box ? S_multi_px_boxes[57:48]-10'd1 : S_show_y1;
    wire [9:0] S_box_cy = S_use_multi_box ? S_multi_cy : S_show_cy;
