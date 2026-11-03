// FPGA report: PCB #### PASS/FAIL/REVIEW, DEFECTS N, then Dn x0 y0 x1 y1.
// The complete machine profile must be valid before a job can handshake.
// The secondary top supplies a board-resident fixed profile; standalone users
// still provide the explicit validity input. Default/reset state emits no
// motion. Inputs are single-clock.
module grbl_reporter_shared_candidate #(
    parameter integer CLK_HZ=50000000,
    parameter integer ACK_TIMEOUT_CYCLES=CLK_HZ*5,
    parameter integer STATUS_TIMEOUT_CYCLES=CLK_HZ*2,
    parameter integer QUERY_INTERVAL_CYCLES=CLK_HZ/5,
    parameter integer STATUS_RETRY_INTERVAL_CYCLES=CLK_HZ/2,
    parameter integer STATUS_MAX_RETRIES=3,
    parameter integer MAZE_ENABLE=1,
    parameter integer AUTO_NEWLINE=0
)(
    input wire I_clk,input wire I_rst_n,input wire I_clear,input wire I_abort,input wire I_stop,input wire I_rearm,
    input wire I_job_valid,input wire [31:0] I_job_id,input wire [63:0] I_session_id,
    // Internal source namespace only: printed IDs and HXA fields are unchanged.
    input wire [2:0] I_job_source,
    input wire [1:0] I_judgement, // 0 REVIEW, 1 PASS, 2 FAIL
    input wire [2:0] I_defect_count,input wire [255:0] I_defect_boxes,
    // Maze payload must remain stable until O_busy drops. The top reserves
    // the vision/frame store for the entire plot job.
    input wire I_maze_mode,input wire [1:0] I_maze_status,
    input wire [8:0] I_maze_steps,input wire [7:0] I_maze_start,I_maze_goal,I_maze_endpoint,
    input wire [511:0] I_maze_directions,input wire [1023:0] I_maze_walls,
    output wire O_job_ready,output wire O_busy,output wire O_done,output wire O_error,
    output wire [7:0] O_error_code,output wire [31:0] O_acked_lines,output wire [2:0] O_job_state,
    output wire O_recovery_required,
    output wire [7:0] O_rt_data,output wire O_rt_valid,input wire I_rt_ready,output wire O_rt_done,
    input wire I_link_ready,input wire I_profile_valid,input wire I_pen_pwm_mode,
    input wire [15:0] I_origin_x_cmm,input wire [15:0] I_origin_y_cmm,
    input wire [15:0] I_work_x_cmm,input wire [15:0] I_work_y_cmm,input wire [7:0] I_step_cmm,
    input wire signed [15:0] I_pen_up_cmm,input wire signed [15:0] I_pen_down_cmm,
    input wire [15:0] I_pen_up_pwm,input wire [15:0] I_pen_down_pwm,
    input wire [15:0] I_travel_feed,input wire [15:0] I_draw_feed,input wire [15:0] I_pen_feed,
    output wire [7:0] O_tx_data,output wire O_tx_valid,input wire I_tx_ready,input wire I_tx_done,
    input wire [7:0] I_rx_data,input wire I_rx_valid,input wire I_rx_error,
    // Packed per-cluster kind: 1 missing, 2 solder; 0/3 never marks a defect.
    input wire [7:0] I_defect_kinds,
    // CNN coordinates reuse I_defect_boxes[31:0] as {centre_y,centre_x}.
    // Confidence is the existing normalized 0..100 margin score.
    input wire I_cnn_mode,input wire [15:0] I_cnn_class,
    input wire [7:0] I_cnn_confidence,
    input wire I_local_test,
    output wire S_start,
    output wire S_clear,
    output wire S_abort,
    output wire S_stop,
    output wire S_rearm,
    output wire S_cancel,
    output wire S_fault,
    output wire S_reset_job,
    output wire S_profile_valid,
    output wire [7:0] S_fault_code,
    output wire [511:0] S_line,
    output wire [6:0] S_length,
    output wire S_line_valid,
    output wire S_line_last,
    output wire S_finish,
    input wire S_available,
    input wire S_line_ready,
    input wire S_line_done,
    input wire S_busy,
    input wire S_done,
    input wire S_error,
    input wire S_cancelled,
    input wire S_recovery_required,
    input wire [7:0] S_error_code,
    input wire [31:0] S_acked_lines,
    input wire [2:0] S_job_state,
    input wire S_rt_done,
    output wire X_start,
    output wire [1:0] X_kind,
    output wire [15:0] X_x,
    output wire [15:0] X_y,
    output wire [15:0] X_z,
    output wire [15:0] X_feed,
    output wire [15:0] X_pwm,
    input wire [511:0] X_line,
    input wire [6:0] X_length,
    input wire X_done,
    input wire X_busy
);
    // Keep the historical state numbers used by the diagnostic testbenches;
    // the two added fixed-command states live above the legacy range.
    localparam [6:0] R_IDLE=0,R_JOBDEC=1,R_G21=2,R_G90=3,R_INITUP=4,
                     R_DOWN=7,R_DRAW=8,R_UP=9,R_FINALUP=10,
                     R_FORMAT=11,R_SUBMIT=12,R_WAIT=13,R_DEFDEC=14,R_GLYPH=15,R_FONT=16,
                     R_MCHECK=17,R_MSCAN=18,R_MCOORD=19,R_MMOVE=20,
                     R_MDOWN=21,R_MDRAW=22,R_MUP=23,R_MROUTE=24,R_MNEXT=25,
                     R_MINIT=26,R_MCURRENT=27,R_MSTEP=28,R_MDEST=29,
                     R_MEDGE=30,R_MDPOINT=31,R_G92=34,R_DWELL=35,
                     R_DLOAD=36,R_DCENTER=37,R_DMAP=38,R_DMUL=39,
                     R_DDIV=40,R_DMAPPED=41,R_DSEG=42,R_DTRAVEL=43,
                     R_DDOWN=44,R_DDWELL=45,R_DDRAW=46,R_DUP=47,R_DNEXT=48,
                     R_TEST_G21=49,R_TEST_G90=50,R_TEST_G92=51,
                     R_TEST_MOVE=52,R_TEST_DOWN=53,R_TEST_EDGE=54,R_TEST_DRAW=55,
                     R_NPREFLIGHT=56,R_NHEIGHT=57,R_NCHECK=58,R_NEWLINE=59,
                     R_NPREFLIGHT_MARK=60,R_FONT_WAIT=61,R_GLYPH_CAPTURE=62,
                     R_VSET=63,R_VMUL=64,R_VEMIT=65,R_VTRAVEL=66,R_VLIFT=67;
    reg [6:0] state,next_after_line;
    // Maze mode is selected explicitly per build. Keeping the parameter here
    // lets the PCB release remove the legacy validation RAM at elaboration,
    // while standalone maze users retain the original default behavior.
    wire requested_maze=(MAZE_ENABLE != 0) && I_maze_mode;
    reg maze_job,maze_route,maze_fault,test_job;
    reg [1:0] test_edge;
    reg [7:0] maze_cell;
    reg [1:0] maze_edge;
    reg [8:0] maze_at;
    // Route validation needs only one visited-bit access per cycle. Use a
    // synchronous RAM initialized before validation instead of a resettable
    // 256-bit vector with an indexed write decoder and an asynchronous mux.
    wire maze_visited_q;
    reg [7:0] maze_init_cell;
    reg [3:0] maze_current_walls;
    reg [5:0] maze_x0,maze_y0,maze_x1,maze_y1;
    reg [15:0] maze_end_y;
    // Wide direction selection, neighbour arithmetic, destination wall
    // selection and edge validation each terminate at separate registers.
    // The 2-bit direction and 8-bit neighbour are shared with route drawing;
    // no copy of the full 512-bit route payload is required.
    wire [1:0] maze_dir_raw=I_maze_directions[{maze_at[7:0],1'b0}+:2];
    reg [1:0] maze_dir_q;
    reg [7:0] maze_next,maze_next_q;
    reg [1:0] maze_opposite,maze_opposite_q;
    reg maze_inbounds,maze_inbounds_q,maze_source_blocked_q;
    reg [3:0] maze_dest_walls_q;
    reg maze_edge_ok_q;
    reg maze_wall;
    reg [5:0] wall_x0,wall_y0,wall_x1,wall_y1;
    // Exactly one 256-to-1 nibble select is shared by route validation and
    // wall plotting. R_MCURRENT saves the source walls; R_MDEST saves the
    // destination walls, eliminating two full 1024-to-1 indexed-bit muxes
    // and the separate four plotting selectors.
    wire [7:0] maze_wall_cell=(state==R_MDEST)?maze_next_q:maze_cell;
    wire [3:0] maze_wall_nibble=I_maze_walls[{maze_wall_cell,2'b00}+:4];
    always @* begin
        maze_next=maze_cell;maze_opposite=0;maze_inbounds=0;
        case(maze_dir_q)
            0:begin maze_next=maze_cell-8'd16;maze_opposite=2;maze_inbounds=maze_cell[7:4]!=0;end
            1:begin maze_next=maze_cell+8'd1;maze_opposite=3;maze_inbounds=maze_cell[3:0]!=15;end
            2:begin maze_next=maze_cell+8'd16;maze_opposite=0;maze_inbounds=maze_cell[7:4]!=15;end
            3:begin maze_next=maze_cell-8'd1;maze_opposite=1;maze_inbounds=maze_cell[3:0]!=0;end
        endcase
        wall_x0={1'b0,maze_cell[3:0],1'b0};wall_y0={1'b0,maze_cell[7:4],1'b0};
        wall_x1=wall_x0;wall_y1=wall_y0;maze_wall=0;
        // Emit each physical edge once: N/W for every cell; S/E at exterior.
        case(maze_edge)
            0:begin maze_wall=maze_wall_nibble[0];wall_x1=wall_x0+6'd2;end
            1:begin maze_wall=maze_wall_nibble[3];wall_y1=wall_y0+6'd2;end
            2:begin maze_wall=(maze_cell[7:4]==15)&&maze_wall_nibble[2];
                wall_y0=wall_y0+6'd2;wall_y1=wall_y0;wall_x1=wall_x0+6'd2;end
            3:begin maze_wall=(maze_cell[3:0]==15)&&maze_wall_nibble[1];
                wall_x0=wall_x0+6'd2;wall_x1=wall_x0;wall_y1=wall_y0+6'd2;end
        endcase
    end
    wire stream_error;wire [7:0] stream_error_code;wire [2:0] stream_job_state;
    wire stream_recovery;wire [7:0] stream_rt_data;wire stream_rt_valid;wire stream_rt_done;
    reg newline_fault,newline_preflight,newline_live;
    // Shared by reports and KEY2. Per-job clear/rearm never rewinds the page.
    // An interrupted started job reserves its full extent to prevent overwrite.
    reg [15:0] newline_offset_cmm,base_origin_y;
    // Cursor is immutable until completion/failure; reuse it during the job.
    wire [15:0] job_y_offset=(AUTO_NEWLINE!=0)?newline_offset_cmm:16'd0;
    reg [7:0] original_mark_kinds;
    reg [17:0] newline_next_y;
    assign O_error=maze_fault||newline_fault||stream_error;
    assign O_error_code=newline_fault?8'd12:maze_fault?8'd11:stream_error_code;
    assign O_job_state=(maze_fault||newline_fault)?3'd5:stream_job_state;
    assign O_recovery_required=stream_recovery;
    assign O_rt_data=stream_rt_data;assign O_rt_valid=stream_rt_valid;assign O_rt_done=stream_rt_done;
    wire [7:0] maze_visit_addr=(state==R_MINIT)?maze_init_cell:maze_next_q;
    wire maze_visit_accept=(state==R_MCHECK)&&(maze_at<I_maze_steps)&&maze_edge_ok_q&&
        I_link_ready&&I_profile_valid&&!O_error&&!I_abort;
    wire maze_visit_write=(state==R_MINIT)||maze_visit_accept;
    wire maze_visit_data=(state==R_MINIT)?(maze_init_cell==I_maze_start):1'b1;
    // Do not reset the array or its output register: the 256-cycle init is
    // mandatory for every accepted maze job and permits BRAM inference.
    generate if (MAZE_ENABLE != 0) begin : g_maze_visited
        (* ram_style="bram" *) reg maze_visited [0:255] /* synthesis syn_ramstyle="block_ram" */;
        reg maze_visited_q_reg;
        always @(posedge I_clk)begin
            if(maze_visit_write)maze_visited[maze_visit_addr]<=maze_visit_data;
            else maze_visited_q_reg<=maze_visited[maze_visit_addr];
        end
        assign maze_visited_q=maze_visited_q_reg;
    end else begin : g_no_maze_visited
        assign maze_visited_q=1'b0;
    end endgenerate
    reg stream_start,line_valid,line_last;
    reg [511:0] line_data;
    reg [6:0] line_length;
    wire line_ready,line_acked,stream_busy;
    reg [31:0] last_job;
    reg [63:0] last_session;
    reg [2:0] last_source;
    reg have_job;
    reg [1:0] judgement;
    reg cnn_job,cnn_target;
    reg [3:0] cnn_class;
    reg [1:0] cnn_color,cnn_shape;
    reg [4:0] glyph_index,last_glyph;
    reg [2:0] report_line,defect_count;
    reg [3:0] coordinate_index;
    reg [255:0] defect_shift;
    reg [255:0] mark_boxes;
    reg [7:0] mark_kinds;
    reg [2:0] mark_index;
    reg [1:0] mark_kind;
    reg mark_second,mark_horizontal,map_axis;
    reg [15:0] work_x,work_y;
    reg [10:0] mark_px0,mark_px1,mark_px;
    reg [9:0] mark_py0,mark_py1,mark_py;
    reg [15:0] mark_x,mark_y;
    // Serial unsigned multiply/divide is shared by X/Y mapping. No DSP or
    // combinational divider is added to the timing-critical production path.
    // Max product is 1280*21000=26880000 < 2^25; Y is at most
    // 720*29700=21384000. Quotients fit the 16-bit machine coordinate.
    reg [24:0] map_acc,map_term,map_dividend;
    reg [15:0] map_quotient;
    reg [10:0] map_factor,map_divisor;
    reg [10:0] map_remainder;
    reg [4:0] map_bit;
    wire [24:0] map_sum=map_acc+(map_factor[0]?map_term:25'd0);
    wire [11:0] map_trial={map_remainder,map_dividend[24]};
    wire map_subtract=map_trial>={1'd0,map_divisor};
    wire [11:0] mark_sum_x={1'b0,mark_px0}+{1'b0,mark_px1};
    wire [10:0] mark_sum_y={1'b0,mark_py0}+{1'b0,mark_py1};
    function [15:0] mark_lo;
        input [15:0] center,limit,half_length;
        begin mark_lo=(center-limit>half_length)?center-half_length:limit;end
    endfunction
    function [15:0] mark_hi;
        input [15:0] center,limit,half_length;
        begin mark_hi=(limit-center>half_length)?center+half_length:limit;end
    endfunction
    wire [17:0] newline_page_bottom={2'd0,work_y}-18'd1000;
    wire [16:0] shifted_marker_end_y={1'b0,maze_end_y}+{1'b0,job_y_offset};
    wire [17:0] newline_marker_bottom={1'b0,shifted_marker_end_y}+18'd500;
    reg [31:0] decimal_value;
    // Every coordinate is converted before the first glyph is emitted.
    // No memory reset is needed; uninitialized BCD is never consumed.
    wire job_dec_done,job_dec_busy;
    wire [39:0] job_bcd;
    (* ram_style="bram" *) reg [15:0] defect_bcd_mem[0:15] /* synthesis syn_ramstyle="block_ram" */;
    reg [15:0] digit_word_q;
    wire [1:0] digit_field=cnn_job ? {1'b0,(glyph_index>=6)} :
        (glyph_index>=18)?2'd3:(glyph_index>=13)?2'd2:(glyph_index>=8)?2'd1:2'd0;
    wire [1:0] digit_line=cnn_job ? 2'd0 : report_line[1:0]-2'd2;
    wire [3:0] digit_read_addr={digit_line,digit_field};
    always @(posedge I_clk)begin
        if(I_rst_n && state==R_DEFDEC && job_dec_done)
            defect_bcd_mem[coordinate_index]<=job_bcd[15:0];
        digit_word_q<=defect_bcd_mem[digit_read_addr];
    end
    reg [3:0] stroke_start;
    reg vector_new_glyph,font_pen_down;
    reg [1:0] vector_coord;
    reg [15:0] vector_y_start,font_last_x,font_last_y;
    wire [2:0] font_x0,font_y0,font_x1,font_y1;
    // The synchronous ROM address is stable through all four serial endpoint
    // multiplies. Select one endpoint before a shared 8-bit unit adder instead
    // of storing four redundant endpoint-unit registers.
    reg [2:0] vector_endpoint;
    always @* case(vector_coord)
        0:vector_endpoint=font_x0;
        1:vector_endpoint=font_y0;
        2:vector_endpoint=font_x1;
        default:vector_endpoint=font_y1;
    endcase
    wire [7:0] vector_base_unit=vector_coord[0]?
        (({5'd0,report_line}<<3)+({5'd0,report_line}<<1)):
        (({3'd0,glyph_index}<<2)+({3'd0,glyph_index}<<1));
    wire [7:0] vector_selected_unit=vector_base_unit+{5'd0,vector_endpoint};
    reg [7:0] character,decoded_char;
    wire [3:0] font_segment_count;
    reg [15:0] origin_x,origin_y,x_start,x_end,y_pos;
    reg [7:0] step;
    reg pen_pwm;
    reg signed [15:0] pen_up,pen_down;
    reg [15:0] up_pwm,down_pwm,travel_feed,draw_feed,pen_feed;
    reg job_dec_start;
    reg [15:0] job_digits;
    reg fmt_start;
    reg [1:0] fmt_kind;
    reg [15:0] fmt_x,fmt_y,fmt_feed,fmt_pwm;
    reg signed [15:0] fmt_z;
    wire [511:0] fmt_line;
    wire [6:0] fmt_length;
    wire fmt_done,fmt_busy;
    // Profile geometry is stable between configuration commits. Separate the
    // extent arithmetic from its comparison so it never drives the large
    // job-admission fanout in one cycle. A matching signature is required:
    // changing any geometry input immediately invalidates a stale good result.
    wire [72:0] geometry_key={requested_maze,I_origin_x_cmm,I_origin_y_cmm,
                             I_work_x_cmm,I_work_y_cmm,I_step_cmm};
    reg [72:0] geometry_key_s1,geometry_key_s2;
    reg [17:0] max_report_x_s1,max_report_y_s1;
    reg geometry_ok_s2;
    reg [1:0] geometry_seen;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            geometry_key_s1<=0;geometry_key_s2<=0;
            max_report_x_s1<=0;max_report_y_s1<=0;
            geometry_ok_s2<=0;geometry_seen<=0;
        end else begin
            geometry_key_s1<=geometry_key;geometry_key_s2<=geometry_key_s1;
            // Constant extents are shift/add forms. Keeping this admission
            // guard away from DSP multipliers also avoids consuming the last
            // LUTL/DSP columns in the PH1P35 placer.
            max_report_x_s1<={2'd0,I_origin_x_cmm}+
                ({10'd0,I_step_cmm}<<7)+({10'd0,I_step_cmm}<<2);
            max_report_y_s1<={2'd0,I_origin_y_cmm}+
                (requested_maze ? (({10'd0,I_step_cmm}<<7)) :
                 (({10'd0,I_step_cmm}<<5)+({10'd0,I_step_cmm}<<4)+
                  ({10'd0,I_step_cmm}<<3)+{10'd0,I_step_cmm}));
            geometry_ok_s2<=(max_report_x_s1<={2'd0,geometry_key_s1[39:24]})&&
                            (max_report_y_s1<={2'd0,geometry_key_s1[23:8]});
            geometry_seen<=I_clear?2'b00:{geometry_seen[0],1'b1};
        end
    end
    wire profile_ok=I_profile_valid && I_step_cmm!=0 && I_travel_feed!=0 && I_draw_feed!=0 &&
        I_pen_feed!=0 && geometry_seen[1] && geometry_key==geometry_key_s2 && geometry_ok_s2 &&
        I_origin_x_cmm<16'd21000 && I_origin_y_cmm<16'd29700 &&
        (requested_maze ? ((I_maze_status==1||I_maze_status==2)&&I_maze_steps<=255) : I_defect_count<=3'd4) &&
        // Both Z conventions are valid: some plotters use positive Z for
        // lift, while the fixed board preset uses negative Z for lift and
        // positive Z for contact.  Equality remains invalid because it would
        // never move the pen between strokes.
        (I_pen_pwm_mode || (I_pen_up_cmm!=I_pen_down_cmm &&
                           I_pen_up_cmm<=16'sd500 &&
                           I_pen_up_cmm>=-16'sd500 &&
                           I_pen_down_cmm<=16'sd500 &&
                           I_pen_down_cmm>=-16'sd500));
    wire local_test_mode=(I_local_test===1'b1);
    assign O_job_ready=S_available && (state==R_IDLE) && !O_error && !stream_recovery && !I_abort && !I_stop && !I_clear && profile_ok && I_link_ready &&
                       !(have_job && last_job==I_job_id && last_session==I_session_id && last_source==I_job_source);
    assign O_busy=(state!=R_IDLE)||stream_busy;
    grbl_decimal u_job_decimal(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(job_dec_start),
        .I_value(decimal_value),.O_bcd(job_bcd),.O_done(job_dec_done),.O_busy(job_dec_busy));
    assign X_start=fmt_start;
    assign X_kind=fmt_kind;
    assign X_x=fmt_x;
    assign X_y=fmt_y;
    assign X_z=fmt_z;
    assign X_feed=fmt_feed;
    assign fmt_line=X_line;
    assign fmt_length=X_length;
    assign fmt_done=X_done;
    assign fmt_busy=X_busy;
    assign X_pwm=fmt_pwm;
    grbl_vector_font_rom #(.SYNC_ROM(1)) u_font(.I_clk(I_clk),.I_char(character),.I_row(3'd0),.O_pixels(),
        .O_segment_count(font_segment_count),.O_advance_width(),.I_segment(stroke_start),
        .O_x0(font_x0),.O_y0(font_y0),.O_x1(font_x1),.O_y1(font_y1));
    assign S_start=stream_start;
    assign S_clear=I_clear;
    assign S_abort=I_abort;
    assign S_stop=I_stop;
    assign S_rearm=I_rearm;
    assign S_cancel=1'b0;
    assign S_fault=1'b0;
    assign S_reset_job=1'b0;
    assign S_profile_valid=I_profile_valid;
    assign S_fault_code=8'd0;
    assign S_line=line_data;
    assign S_length=line_length;
    assign S_line_valid=line_valid;
    assign S_line_last=line_last;
    assign S_finish=1'b0;
    assign line_ready=S_line_ready;
    assign line_acked=S_line_done;
    assign stream_busy=S_busy;
    assign O_done=S_done;
    assign stream_error=S_error;
    assign stream_error_code=S_error_code;
    assign O_acked_lines=S_acked_lines;
    assign stream_job_state=S_job_state;
    assign stream_recovery=S_recovery_required;
    assign stream_rt_data=8'd0;
    assign stream_rt_valid=1'b0;
    assign stream_rt_done=S_rt_done;
    assign O_tx_data=8'd0;
    assign O_tx_valid=1'b0;
    always @*begin
        cnn_color=0;cnn_shape=0;
        case(cnn_class)
            1,2,3:cnn_color=1;
            4,5,6:cnn_color=2;
            7,8,9:cnn_color=3;
            default:cnn_color=0;
        endcase
        case(cnn_class)
            1,4,7:cnn_shape=1;
            2,5,8:cnn_shape=2;
            3,6,9:cnn_shape=3;
            default:cnn_shape=0;
        endcase
        decoded_char=" ";
        if(cnn_job)begin
            if(!cnn_target)case(glyph_index)
                0:decoded_char="N";1:decoded_char="O";
                3:decoded_char="T";4:decoded_char="A";5:decoded_char="R";
                6:decoded_char="G";7:decoded_char="E";8:decoded_char="T";
                default:decoded_char=" ";
            endcase
            else if(report_line==0)begin
                if(glyph_index<5)case(cnn_color)
                    1:case(glyph_index)
                        0:decoded_char="R";1:decoded_char="E";2:decoded_char="D";
                        default:decoded_char=" ";
                    endcase
                    2:case(glyph_index)
                        0:decoded_char="G";1:decoded_char="R";2:decoded_char="E";
                        3:decoded_char="E";4:decoded_char="N";
                        default:decoded_char=" ";
                    endcase
                    3:case(glyph_index)
                        0:decoded_char="B";1:decoded_char="L";2:decoded_char="U";3:decoded_char="E";
                        default:decoded_char=" ";
                    endcase
                    default:decoded_char=" ";
                endcase
                else case(cnn_shape)
                    1:case(glyph_index)
                        6:decoded_char="T";7:decoded_char="R";8:decoded_char="I";9:decoded_char="A";
                        10:decoded_char="N";11:decoded_char="G";12:decoded_char="L";13:decoded_char="E";
                        default:decoded_char=" ";
                    endcase
                    2:case(glyph_index)
                        6:decoded_char="C";7:decoded_char="I";8:decoded_char="R";
                        9:decoded_char="C";10:decoded_char="L";11:decoded_char="E";
                        default:decoded_char=" ";
                    endcase
                    3:case(glyph_index)
                        6:decoded_char="S";7:decoded_char="Q";8:decoded_char="U";
                        9:decoded_char="A";10:decoded_char="R";11:decoded_char="E";
                        default:decoded_char=" ";
                    endcase
                    default:decoded_char=" ";
                endcase
            end else if(report_line==2)case(glyph_index)
                0:decoded_char="C";1:decoded_char="O";2:decoded_char="N";3:decoded_char="F";
                5:decoded_char=8'h30+{4'd0,job_digits[11:8]};
                6:decoded_char=8'h30+{4'd0,job_digits[7:4]};
                7:decoded_char=8'h30+{4'd0,job_digits[3:0]};
                default:decoded_char=" ";
            endcase
            else case(glyph_index)
                0:decoded_char="X";6:decoded_char="Y";
                1,7:decoded_char=8'h30+{4'd0,digit_word_q[15:12]};
                2,8:decoded_char=8'h30+{4'd0,digit_word_q[11:8]};
                3,9:decoded_char=8'h30+{4'd0,digit_word_q[7:4]};
                4,10:decoded_char=8'h30+{4'd0,digit_word_q[3:0]};
                default:decoded_char=" ";
            endcase
        end else if(report_line==0)begin
            case(glyph_index)
                0:decoded_char="P";1:decoded_char="C";2:decoded_char="B";
                4:decoded_char=8'h30+{4'd0,job_digits[15:12]};5:decoded_char=8'h30+{4'd0,job_digits[11:8]};
                6:decoded_char=8'h30+{4'd0,job_digits[7:4]};7:decoded_char=8'h30+{4'd0,job_digits[3:0]};
                9:decoded_char=(judgement==1)?"P":(judgement==2)?"F":"R";
                10:decoded_char=(judgement==0)?"E":"A";
                11:decoded_char=(judgement==1)?"S":(judgement==2)?"I":"V";
                12:decoded_char=(judgement==1)?"S":(judgement==2)?"L":"I";
                13:decoded_char="E";14:decoded_char="W";
                default:decoded_char=" ";
            endcase
        end
        else if(report_line==1)case(glyph_index)
            0:decoded_char="D";1:decoded_char="E";2:decoded_char="F";3:decoded_char="E";
            4:decoded_char="C";5:decoded_char="T";6:decoded_char="S";
            8:decoded_char=8'h30+{5'd0,defect_count};default:decoded_char=" ";
        endcase
        else case(glyph_index)
            0:decoded_char="D";1:decoded_char=8'h30+{5'd0,(report_line-3'd1)};
            3:decoded_char=8'h30+{4'd0,digit_word_q[15:12]};4:decoded_char=8'h30+{4'd0,digit_word_q[11:8]};
            5:decoded_char=8'h30+{4'd0,digit_word_q[7:4]};6:decoded_char=8'h30+{4'd0,digit_word_q[3:0]};
            8:decoded_char=8'h30+{4'd0,digit_word_q[15:12]};9:decoded_char=8'h30+{4'd0,digit_word_q[11:8]};
            10:decoded_char=8'h30+{4'd0,digit_word_q[7:4]};11:decoded_char=8'h30+{4'd0,digit_word_q[3:0]};
            13:decoded_char=8'h30+{4'd0,digit_word_q[15:12]};14:decoded_char=8'h30+{4'd0,digit_word_q[11:8]};
            15:decoded_char=8'h30+{4'd0,digit_word_q[7:4]};16:decoded_char=8'h30+{4'd0,digit_word_q[3:0]};
            18:decoded_char=8'h30+{4'd0,digit_word_q[15:12]};19:decoded_char=8'h30+{4'd0,digit_word_q[11:8]};
            20:decoded_char=8'h30+{4'd0,digit_word_q[7:4]};21:decoded_char=8'h30+{4'd0,digit_word_q[3:0]};
            default:decoded_char=" ";
        endcase
    end
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            newline_fault<=0;newline_preflight<=0;newline_live<=0;
            newline_offset_cmm<=0;base_origin_y<=0;newline_next_y<=0;original_mark_kinds<=0;
            maze_job<=0;maze_route<=0;maze_fault<=0;test_job<=0;test_edge<=0;maze_cell<=0;maze_edge<=0;
            maze_at<=0;maze_init_cell<=0;maze_current_walls<=0;maze_dir_q<=0;
            maze_next_q<=0;maze_opposite_q<=0;maze_inbounds_q<=0;
            maze_source_blocked_q<=0;maze_dest_walls_q<=0;maze_edge_ok_q<=0;
            maze_x0<=0;maze_y0<=0;maze_x1<=0;maze_y1<=0;maze_end_y<=0;
            state<=R_IDLE;next_after_line<=R_IDLE;stream_start<=0;line_valid<=0;line_last<=0;
            line_data<=0;line_length<=0;last_job<=0;last_session<=0;last_source<=0;have_job<=0;judgement<=0;
            cnn_job<=0;cnn_target<=0;cnn_class<=0;
            glyph_index<=0;last_glyph<=14;stroke_start<=0;
            vector_new_glyph<=1;font_pen_down<=0;
            vector_coord<=0;vector_y_start<=0;font_last_x<=0;font_last_y<=0;origin_x<=0;origin_y<=0;
            x_start<=0;x_end<=0;y_pos<=0;step<=0;pen_pwm<=0;pen_up<=0;pen_down<=0;
            up_pwm<=0;down_pwm<=0;travel_feed<=0;draw_feed<=0;pen_feed<=0;job_dec_start<=0;
            job_digits<=0;fmt_start<=0;fmt_kind<=0;fmt_x<=0;fmt_y<=0;fmt_z<=0;fmt_feed<=0;fmt_pwm<=0;
            report_line<=0;defect_count<=0;coordinate_index<=0;defect_shift<=0;decimal_value<=0;character<=0;
            mark_boxes<=0;mark_kinds<=0;mark_index<=0;mark_kind<=0;
            mark_second<=0;mark_horizontal<=0;map_axis<=0;work_x<=0;work_y<=0;
            mark_px0<=0;mark_px1<=0;mark_py0<=0;mark_py1<=0;mark_px<=0;mark_py<=0;
            mark_x<=0;mark_y<=0;map_acc<=0;map_term<=0;map_dividend<=0;map_quotient<=0;
            map_factor<=0;map_divisor<=0;map_remainder<=0;map_bit<=0;
        end else begin
            stream_start<=0;job_dec_start<=0;fmt_start<=0;
            if(I_clear&&!O_busy)begin maze_fault<=0;newline_fault<=0;end
            if(AUTO_NEWLINE!=0 && newline_live &&
               ((state==R_WAIT && O_done)||stream_error||I_abort||I_stop))begin
                newline_offset_cmm<=newline_next_y[15:0]-base_origin_y;
                newline_live<=0;
            end
            if(O_error || I_abort || I_stop)begin state<=R_IDLE;line_valid<=0;end
            else case(state)
                R_IDLE:if(I_job_valid && O_job_ready)begin
                    last_job<=I_job_id;last_session<=I_session_id;last_source<=I_job_source;have_job<=1;
                    judgement<=(I_judgement>2)?0:I_judgement;
                    cnn_job<=I_cnn_mode;
                    cnn_target<=I_judgement==2 && I_cnn_class>=1 && I_cnn_class<=9;
                    cnn_class<=I_cnn_class[3:0];
                    last_glyph<=I_cnn_mode?((I_judgement==2 && I_cnn_class>=1 && I_cnn_class<=9)?13:8):((I_judgement==1 || I_judgement==2)?12:14);
                    origin_x<=I_origin_x_cmm;
                    origin_y<=I_origin_y_cmm+((AUTO_NEWLINE!=0)?newline_offset_cmm:16'd0);
                    base_origin_y<=I_origin_y_cmm;
                    step<=I_step_cmm;
                    work_x<=(I_work_x_cmm>16'd21000)?16'd21000:I_work_x_cmm;
                    work_y<=(I_work_y_cmm>16'd29700)?16'd29700:I_work_y_cmm;
                    pen_pwm<=I_pen_pwm_mode;pen_up<=I_pen_up_cmm;pen_down<=I_pen_down_cmm;
                    up_pwm<=I_pen_up_pwm;down_pwm<=I_pen_down_pwm;travel_feed<=I_travel_feed;
                    draw_feed<=I_draw_feed;pen_feed<=I_pen_feed;glyph_index<=0;
                    report_line<=0;defect_count<=(!I_cnn_mode && I_judgement==2)?I_defect_count:3'd0;defect_shift<=I_defect_boxes;
                    mark_boxes<=I_defect_boxes;mark_kinds<=I_defect_kinds;
                    original_mark_kinds<=I_defect_kinds;
                    mark_index<=0;mark_second<=0;
                    coordinate_index<=0;decimal_value<=I_cnn_mode?{24'd0,I_cnn_confidence}:I_job_id;
                    line_last<=0;maze_job<=requested_maze;maze_route<=0;vector_new_glyph<=1;font_pen_down<=0;stroke_start<=0;
                    test_job<=local_test_mode;test_edge<=0;
                    if(AUTO_NEWLINE!=0 && !requested_maze)begin
                        newline_preflight<=1;state<=R_NPREFLIGHT;
                    end else if(local_test_mode)begin
                        stream_start<=1;state<=R_TEST_G21;
                    end else if(requested_maze)begin
                        maze_cell<=I_maze_start;maze_at<=0;maze_init_cell<=0;
                        state<=R_MINIT;
                    end else begin stream_start<=1;job_dec_start<=1;state<=R_JOBDEC;end
                end
                R_NPREFLIGHT:begin
                    // Reuse the marker's serial multiplier; no new DSP/divider.
                    map_acc<=0;map_term<={17'd0,step};map_bit<=0;
                    map_factor<=((({8'd0,defect_count}+11'd1)<<3)+
                                 (({8'd0,defect_count}+11'd1)<<1)+11'd6);
                    if(cnn_job)map_factor<=cnn_target?11'd26:11'd6;
                    if(test_job)begin
                        newline_next_y<={2'd0,origin_y}+18'd2500;
                        state<=R_NCHECK;
                    end else begin newline_next_y<={2'd0,origin_y}+18'd500;state<=R_NHEIGHT;end
                end
                R_NHEIGHT:begin
                    if(map_bit==10)begin
                        newline_next_y<=newline_next_y+map_sum;
                        state<=R_DLOAD;
                    end else begin
                        map_acc<=map_sum;map_term<=map_term<<1;map_factor<=map_factor>>1;
                        map_bit<=map_bit+1'b1;
                    end
                end
                R_NCHECK:begin
                    newline_preflight<=0;mark_index<=0;mark_second<=0;
                    mark_boxes<=defect_shift;mark_kinds<=original_mark_kinds;
                    // Test square and final pen-up return must both fit. No
                    // command is emitted until the entire report passes.
                    if(newline_next_y>newline_page_bottom || work_y<16'd2000 ||
                       (test_job && ({1'b0,origin_x}+17'd2000>{1'b0,work_x})))begin
                        newline_fault<=1;state<=R_IDLE;
                    end else begin
                        newline_live<=1;stream_start<=1;
                        if(test_job)state<=R_TEST_G21;
                        else begin job_dec_start<=1;state<=R_JOBDEC;end
                    end
                end
                R_NPREFLIGHT_MARK:begin
                    if(newline_marker_bottom>newline_next_y)newline_next_y<=newline_marker_bottom;
                    mark_boxes<={64'd0,mark_boxes[255:64]};mark_kinds<={2'd0,mark_kinds[7:2]};
                    mark_index<=mark_index+1'b1;state<=R_DLOAD;
                end
                R_JOBDEC:if(job_dec_done)begin
                    job_digits<=job_bcd[15:0];decimal_value<={16'd0,defect_shift[15:0]};
                    job_dec_start<=1;state<=R_DEFDEC;
                end
                R_DEFDEC:if(job_dec_done)begin
                    defect_shift<={16'd0,defect_shift[255:16]};
                    if(coordinate_index==15)state<=R_G21;
                    else begin
                        coordinate_index<=coordinate_index+1'b1;
                        decimal_value<={16'd0,defect_shift[31:16]};job_dec_start<=1;
                    end
                end
                R_G21:begin line_data<={488'd0,8'h31,8'h32,8'h47};line_length<=3;
                            line_valid<=1;next_after_line<=R_G90;state<=R_SUBMIT;end
                R_TEST_G21:begin line_data<={488'd0,8'h31,8'h32,8'h47};line_length<=3;
                            line_valid<=1;next_after_line<=R_TEST_G90;state<=R_SUBMIT;end
                R_TEST_G90:begin line_data<={488'd0,8'h30,8'h39,8'h47};line_length<=3;
                            line_valid<=1;next_after_line<=R_TEST_G92;state<=R_SUBMIT;end
                R_TEST_G92:begin
                            if(AUTO_NEWLINE!=0)begin line_data<={488'd0,8'h34,8'h35,8'h47};line_length<=3;end
                            else begin line_data<={440'd0,8'h30,8'h59,8'h20,8'h30,8'h58,8'h20,8'h32,8'h39,8'h47};line_length<=9;end
                            line_valid<=1;next_after_line<=R_INITUP;state<=R_SUBMIT;end
                R_G90:begin line_data<={488'd0,8'h30,8'h39,8'h47};line_length<=3;
                            line_valid<=1;next_after_line<=R_G92;state<=R_SUBMIT;end
                R_G92:begin
                            if(AUTO_NEWLINE!=0)begin line_data<={488'd0,8'h34,8'h35,8'h47};line_length<=3;end
                            else begin line_data<={440'd0,8'h30,8'h59,8'h20,8'h30,8'h58,8'h20,8'h32,8'h39,8'h47};line_length<=9;end
                            line_valid<=1;next_after_line<=R_INITUP;state<=R_SUBMIT;end
                R_INITUP,R_UP,R_FINALUP:begin
                    fmt_kind<=pen_pwm?3:2;fmt_z<=pen_up;fmt_pwm<=up_pwm;fmt_feed<=pen_feed;
                    fmt_start<=1;next_after_line<=(state==R_FINALUP)?((AUTO_NEWLINE!=0&&!maze_job)?R_NEWLINE:R_WAIT):(state==R_INITUP)?(test_job?R_TEST_MOVE:(maze_job?R_MSCAN:R_GLYPH)):R_GLYPH;
                    line_last<=(state==R_FINALUP)&&!(AUTO_NEWLINE!=0&&!maze_job);state<=R_FORMAT;
                end
                R_NEWLINE:begin
                    fmt_kind<=0;fmt_x<=origin_x;fmt_y<=newline_next_y[15:0];fmt_feed<=travel_feed;
                    fmt_start<=1;line_last<=1;next_after_line<=R_WAIT;state<=R_FORMAT;
                end
                // Only the glyph's disconnected polylines lift the pen.
                // Joined segments and closed loops keep a continuous G1 path.
                R_GLYPH:begin
                    if(vector_new_glyph)state<=R_GLYPH_CAPTURE;
                    else if(stroke_start<font_segment_count)state<=R_FONT;
                    else if(font_pen_down)begin font_pen_down<=0;state<=R_UP;end
                    else begin
                        stroke_start<=0;vector_new_glyph<=1;
                        if(glyph_index==last_glyph)begin
                            if(cnn_job)begin
                                if(!cnn_target || report_line==2)state<=R_FINALUP;
                                else begin
                                    report_line<=report_line+1'b1;glyph_index<=0;
                                    last_glyph<=(report_line==1)?5'd7:5'd10;state<=R_GLYPH;
                                end
                            end else if(report_line==defect_count+3'd1)
                                state<=(judgement==2&&defect_count!=0)?R_DLOAD:R_FINALUP;
                            else begin
                                report_line<=report_line+1'b1;glyph_index<=0;
                                last_glyph<=(report_line==0)?5'd8:5'd21;state<=R_GLYPH;
                            end
                        end else begin glyph_index<=glyph_index+1'b1;state<=R_GLYPH;end
                    end
                end
                R_GLYPH_CAPTURE:begin character<=decoded_char;stroke_start<=0;vector_new_glyph<=0;state<=R_FONT;end
                R_FONT:state<=R_FONT_WAIT;
                R_FONT_WAIT:begin
                    if(font_segment_count==0)state<=R_GLYPH;
                    else begin
                        vector_coord<=0;state<=R_VSET;
                    end
                end
                R_VSET:begin
                    // Reuse the existing serial defect-map multiplier. No
                    // parallel endpoint multipliers or floating point added.
                    map_acc<=0;map_term<={17'd0,step};map_bit<=0;
                    map_factor<={3'd0,vector_selected_unit};
                    state<=R_VMUL;
                end
                R_VMUL:begin
                    if(map_bit==7)begin
                        case(vector_coord)
                            0:x_start<=origin_x+map_sum[15:0];
                            1:vector_y_start<=origin_y+map_sum[15:0];
                            2:x_end<=origin_x+map_sum[15:0];
                            default:y_pos<=origin_y+map_sum[15:0];
                        endcase
                        if(vector_coord==3)state<=R_VEMIT;
                        else begin vector_coord<=vector_coord+1'b1;state<=R_VSET;end
                    end else begin map_acc<=map_sum;map_term<=map_term<<1;map_factor<=map_factor>>1;map_bit<=map_bit+1'b1;end
                end
                R_VEMIT:begin
                    // Safety is checked before both the G0 segment start and
                    // its G1 endpoint. X mirroring remains formatter-only.
                    if(x_start>work_x||x_end>work_x||vector_y_start>work_y||y_pos>work_y||
                       x_start<origin_x||x_end<origin_x||vector_y_start<origin_y||y_pos<origin_y)begin
                        newline_fault<=1;state<=R_IDLE;
                    end else if(font_pen_down && font_last_x==x_start && font_last_y==vector_y_start)state<=R_DRAW;
                    else if(font_pen_down)state<=R_VLIFT;
                    else state<=R_VTRAVEL;
                end
                R_VLIFT:begin
                    fmt_kind<=pen_pwm?3:2;fmt_z<=pen_up;fmt_pwm<=up_pwm;fmt_feed<=pen_feed;
                    fmt_start<=1;font_pen_down<=0;next_after_line<=R_VTRAVEL;state<=R_FORMAT;
                end
                R_VTRAVEL:begin
                    fmt_kind<=0;fmt_x<=x_start;fmt_y<=vector_y_start;fmt_feed<=travel_feed;
                    fmt_start<=1;next_after_line<=R_DOWN;state<=R_FORMAT;
                end
                R_DOWN:begin
                    fmt_kind<=pen_pwm?3:2;fmt_z<=pen_down;fmt_pwm<=down_pwm;fmt_feed<=pen_feed;
                    fmt_start<=1;next_after_line<=R_DWELL;state<=R_FORMAT;
                end
                R_DWELL:begin
                    // GRBL's G4 P value is expressed in seconds.  0.1 s
                    // gives the intended 100 ms pen-settle delay; P100 would
                    // pause for one hundred seconds at every stroke.
                    line_data<={456'd0,8'h31,8'h2e,8'h30,8'h50,8'h20,8'h34,8'h47};line_length<=7;
                    line_valid<=1;next_after_line<=test_job?R_TEST_DRAW:R_DRAW;state<=R_SUBMIT;
                end
                R_TEST_MOVE:begin
                    fmt_kind<=0;fmt_x<=origin_x;fmt_y<=origin_y;fmt_feed<=travel_feed;
                    fmt_start<=1;next_after_line<=R_TEST_DOWN;state<=R_FORMAT;
                end
                R_TEST_DOWN:begin
                    fmt_kind<=pen_pwm?3:2;fmt_z<=pen_down;fmt_pwm<=down_pwm;fmt_feed<=pen_feed;
                    fmt_start<=1;next_after_line<=R_DWELL;state<=R_FORMAT;
                end
                R_TEST_EDGE:begin
                    if(test_edge==3)state<=R_FINALUP;
                    else begin test_edge<=test_edge+1'b1;state<=R_TEST_DRAW;end
                end
                R_TEST_DRAW:begin
                    fmt_kind<=1;fmt_feed<=draw_feed;
                    case(test_edge)
                        0:begin fmt_x<=origin_x+16'd2000;fmt_y<=origin_y;end
                        1:begin fmt_x<=origin_x+16'd2000;fmt_y<=origin_y+16'd2000;end
                        2:begin fmt_x<=origin_x;fmt_y<=origin_y+16'd2000;end
                        default:begin fmt_x<=origin_x;fmt_y<=origin_y;end
                    endcase
                    next_after_line<=(test_edge==3)?R_FINALUP:R_TEST_EDGE;
                    fmt_start<=1;state<=R_FORMAT;
                end
                R_DRAW:begin
                    fmt_kind<=1;fmt_x<=x_end;fmt_y<=y_pos;fmt_feed<=draw_feed;
                    fmt_start<=1;stroke_start<=stroke_start+1'b1;font_pen_down<=1;
                    font_last_x<=x_end;font_last_y<=y_pos;next_after_line<=R_GLYPH;state<=R_FORMAT;
                end
                R_MINIT:begin
                    if(!I_link_ready||!I_profile_valid)begin maze_fault<=1;state<=R_IDLE;end
                    else if(maze_init_cell==255)state<=R_MCURRENT;
                    else maze_init_cell<=maze_init_cell+1'b1;
                end
                R_DLOAD:begin
                    if(mark_index>=defect_count)state<=newline_preflight?R_NCHECK:R_FINALUP;
                    // An omitted compatibility port is Z in simulation and
                    // deliberately cannot enter either physical marker path.
                    else if(mark_kinds[1:0]==1||mark_kinds[1:0]==2)begin
                        mark_kind<=mark_kinds[1:0];mark_second<=0;
                        mark_px0<=(mark_boxes[15:0]>1280)?11'd1280:mark_boxes[10:0];
                        mark_py0<=(mark_boxes[31:16]>720)?10'd720:mark_boxes[25:16];
                        mark_px1<=(mark_boxes[47:32]>1280)?11'd1280:mark_boxes[42:32];
                        mark_py1<=(mark_boxes[63:48]>720)?10'd720:mark_boxes[57:48];
                        state<=R_DCENTER;
                    end else begin
                        mark_boxes<={64'd0,mark_boxes[255:64]};mark_kinds<={2'd0,mark_kinds[7:2]};
                        mark_index<=mark_index+1'b1;
                    end
                end
                R_DCENTER:begin
                    if(mark_px1<=mark_px0||mark_py1<=mark_py0)begin
                        mark_boxes<={64'd0,mark_boxes[255:64]};mark_kinds<={2'd0,mark_kinds[7:2]};
                        mark_index<=mark_index+1'b1;state<=R_DLOAD;
                    end else begin
                        mark_px<=mark_sum_x[11:1];mark_py<=mark_sum_y[10:1];
                        mark_horizontal<=(mark_px1-mark_px0)>=(mark_py1-mark_py0);
                        map_axis<=newline_preflight;state<=R_DMAP;
                    end
                end
                R_DMAP:begin
                    map_acc<=0;map_factor<=map_axis?{1'b0,mark_py}:mark_px;
                    map_term<={9'd0,(map_axis?(work_y-base_origin_y):(work_x-origin_x))};
                    map_divisor<=map_axis?11'd720:11'd1280;
                    map_bit<=0;state<=R_DMUL;
                end
                R_DMUL:begin
                    if(map_bit==10)begin
                        map_dividend<=map_sum;map_quotient<=0;map_remainder<=0;
                        map_bit<=0;state<=R_DDIV;
                    end else begin
                        map_acc<=map_sum;map_term<=map_term<<1;map_factor<=map_factor>>1;
                        map_bit<=map_bit+1'b1;
                    end
                end
                R_DDIV:begin
                    map_remainder<=map_subtract?(map_trial-{1'd0,map_divisor}):map_trial;
                    map_dividend<=map_dividend<<1;
                    map_quotient<={map_quotient[14:0],map_subtract};
                    if(map_bit==24)state<=R_DMAPPED;
                    else map_bit<=map_bit+1'b1;
                end
                R_DMAPPED:begin
                    if(!map_axis)begin mark_x<=origin_x+map_quotient[15:0];map_axis<=1;state<=R_DMAP;end
                    else begin
                        mark_y<=base_origin_y+map_quotient[15:0];
                        if(newline_preflight)mark_second<=1;
                        state<=R_DSEG;
                    end
                end
                R_DSEG:begin
                    // Missing: 2 mm cross, two pen strokes. Solder: one 4 mm
                    // line along the pixel box's longer axis. Clamp every
                    // endpoint to the latched A4 workspace before formatting.
                    if((mark_kind==1&&!mark_second)||(mark_kind==2&&mark_horizontal))begin
                        x_start<=mark_lo(mark_x,origin_x,(mark_kind==1)?16'd100:16'd200);
                        x_end<=mark_hi(mark_x,work_x,(mark_kind==1)?16'd100:16'd200);
                        y_pos<=mark_y;maze_end_y<=mark_y;
                    end else begin
                        x_start<=mark_x;x_end<=mark_x;
                        y_pos<=mark_lo(mark_y,base_origin_y,(mark_kind==1)?16'd100:16'd200);
                        maze_end_y<=mark_hi(mark_y,work_y,(mark_kind==1)?16'd100:16'd200);
                    end
                    // The same endpoint/clamp hardware preflights each mark.
                    // Crosses inspect their vertical second segment (max Y).
                    state<=newline_preflight?R_NPREFLIGHT_MARK:R_DTRAVEL;
                end
                R_DTRAVEL:begin
                    fmt_kind<=0;fmt_x<=x_start;fmt_y<=y_pos+job_y_offset;fmt_feed<=travel_feed;
                    fmt_start<=1;next_after_line<=R_DDOWN;state<=R_FORMAT;
                end
                R_DDOWN:begin
                    fmt_kind<=pen_pwm?3:2;fmt_z<=pen_down;fmt_pwm<=down_pwm;fmt_feed<=pen_feed;
                    fmt_start<=1;next_after_line<=R_DDWELL;state<=R_FORMAT;
                end
                R_DDWELL:begin
                    line_data<={456'd0,8'h31,8'h2e,8'h30,8'h50,8'h20,8'h34,8'h47};line_length<=7;
                    line_valid<=1;next_after_line<=R_DDRAW;state<=R_SUBMIT;
                end
                R_DDRAW:begin
                    fmt_kind<=1;fmt_x<=x_end;fmt_y<=shifted_marker_end_y[15:0];fmt_feed<=draw_feed;
                    fmt_start<=1;next_after_line<=R_DUP;state<=R_FORMAT;
                end
                R_DUP:begin
                    fmt_kind<=pen_pwm?3:2;fmt_z<=pen_up;fmt_pwm<=up_pwm;fmt_feed<=pen_feed;
                    fmt_start<=1;next_after_line<=R_DNEXT;state<=R_FORMAT;
                end
                R_DNEXT:begin
                    if(mark_kind==1&&!mark_second)begin mark_second<=1;state<=R_DSEG;end
                    else begin
                        mark_boxes<={64'd0,mark_boxes[255:64]};mark_kinds<={2'd0,mark_kinds[7:2]};
                        mark_index<=mark_index+1'b1;state<=R_DLOAD;
                    end
                end
                R_MCURRENT:begin
                    maze_current_walls<=maze_wall_nibble;
                    maze_dir_q<=maze_dir_raw;
                    state<=R_MSTEP;
                end
                R_MSTEP:begin
                    maze_next_q<=maze_next;
                    maze_opposite_q<=maze_opposite;
                    maze_inbounds_q<=maze_inbounds;
                    maze_source_blocked_q<=maze_current_walls[maze_dir_q];
                    state<=maze_route?R_MDPOINT:R_MDEST;
                end
                R_MDEST:begin
                    // maze_next_q also addresses visited RAM during this
                    // cycle; its registered output is consumed in R_MEDGE.
                    maze_dest_walls_q<=maze_wall_nibble;
                    state<=R_MEDGE;
                end
                R_MEDGE:begin
                    maze_edge_ok_q<=maze_inbounds_q&&!maze_source_blocked_q&&
                        !maze_dest_walls_q[maze_opposite_q]&&!maze_visited_q;
                    state<=R_MCHECK;
                end
                R_MCHECK:begin
                    // Validate the complete route before emitting any machine byte.
                    if(!I_link_ready||!I_profile_valid)begin maze_fault<=1;state<=R_IDLE;end
                    else if(maze_at==I_maze_steps)begin
                        if(maze_cell!=I_maze_endpoint ||
                           (I_maze_status==1&&maze_cell!=I_maze_goal) ||
                           (I_maze_status==2&&maze_cell==I_maze_goal))begin maze_fault<=1;state<=R_IDLE;end
                        else begin stream_start<=1;maze_cell<=0;maze_edge<=0;state<=R_G21;end
                    end else if(!maze_edge_ok_q)begin maze_fault<=1;state<=R_IDLE;end
                    else begin maze_cell<=maze_next_q;maze_at<=maze_at+1'b1;state<=R_MCURRENT;end
                end
                R_MSCAN:begin
                    if(maze_wall)begin
                        maze_x0<=wall_x0;maze_y0<=wall_y0;maze_x1<=wall_x1;maze_y1<=wall_y1;
                        state<=R_MCOORD;
                    end else if(maze_edge==3)begin
                        if(maze_cell==255)begin maze_cell<=I_maze_start;maze_at<=0;state<=R_MROUTE;end
                        else begin maze_cell<=maze_cell+1'b1;maze_edge<=0;end
                    end else maze_edge<=maze_edge+1'b1;
                end
                R_MCOORD:begin
                    // A maze cell is eight font steps; coordinates use half cells.
                    x_start<=origin_x+(({10'd0,maze_x0}*step)<<2);
                    y_pos<=origin_y+(({10'd0,maze_y0}*step)<<2);
                    x_end<=origin_x+(({10'd0,maze_x1}*step)<<2);
                    maze_end_y<=origin_y+(({10'd0,maze_y1}*step)<<2);
                    state<=R_MMOVE;
                end
                R_MMOVE:begin
                    fmt_kind<=0;fmt_x<=x_start;fmt_y<=y_pos;fmt_feed<=travel_feed;
                    fmt_start<=1;next_after_line<=R_MDOWN;state<=R_FORMAT;
                end
                R_MDOWN:begin
                    fmt_kind<=pen_pwm?3:2;fmt_z<=pen_down;fmt_pwm<=down_pwm;fmt_feed<=pen_feed;
                    fmt_start<=1;next_after_line<=R_MDRAW;state<=R_FORMAT;
                end
                R_MDRAW:begin
                    fmt_kind<=1;fmt_x<=x_end;fmt_y<=maze_end_y;fmt_feed<=draw_feed;
                    fmt_start<=1;next_after_line<=R_MUP;state<=R_FORMAT;
                end
                R_MUP:begin
                    fmt_kind<=pen_pwm?3:2;fmt_z<=pen_up;fmt_pwm<=up_pwm;fmt_feed<=pen_feed;
                    fmt_start<=1;next_after_line<=R_MNEXT;state<=R_FORMAT;
                end
                R_MNEXT:begin
                    if(maze_route)begin maze_cell<=maze_next_q;maze_at<=maze_at+1'b1;state<=R_MROUTE;end
                    else if(maze_edge==3)begin
                        if(maze_cell==255)begin maze_cell<=I_maze_start;maze_at<=0;state<=R_MROUTE;end
                        else begin maze_cell<=maze_cell+1'b1;maze_edge<=0;state<=R_MSCAN;end
                    end else begin maze_edge<=maze_edge+1'b1;state<=R_MSCAN;end
                end
                R_MROUTE:begin
                    maze_route<=1;
                    if(maze_at==I_maze_steps)state<=R_FINALUP;
                    else begin
                        maze_dir_q<=maze_dir_raw;
                        state<=R_MSTEP;
                    end
                end
                R_MDPOINT:begin
                    maze_x0<={1'b0,maze_cell[3:0],1'b1};maze_y0<={1'b0,maze_cell[7:4],1'b1};
                    maze_x1<={1'b0,maze_next_q[3:0],1'b1};maze_y1<={1'b0,maze_next_q[7:4],1'b1};
                    state<=R_MCOORD;
                end
                R_FORMAT:if(fmt_done)begin line_data<=fmt_line;line_length<=fmt_length;line_valid<=1;state<=R_SUBMIT;end
                R_SUBMIT:if(line_valid && line_ready)begin line_valid<=0;state<=next_after_line;end
                R_WAIT:if(O_done)state<=R_IDLE;
                default:state<=R_IDLE;
            endcase
        end
    end
endmodule
