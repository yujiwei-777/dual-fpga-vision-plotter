// Continuous document paths -> fixed-profile GRBL. No G92/homing/unlock is
// emitted: the operator's existing work origin is preserved. Pen transitions
// occur only at path boundaries. Normal lines have exactly one outstanding ok.
module doc_grbl_plotter #(
    parameter integer CLK_HZ=125000000,
    parameter integer QUERY_MS=500,STATUS_MS=2000,FINAL_MS=120000,
    parameter integer PROGRESS_MS=30000,JOB_MS=1800000,
    parameter integer EXTERNAL_MAPPER=0,
    // Logical A4 safe origin in hundredths of a millimetre.  Plot coordinates
    // are mirrored once by the formatter.  The return request is therefore
    // pre-mirrored so the machine itself ends at the physical safe point
    // X=10.00 mm (formatter input 20000 -> output 1000).
    parameter integer RETURN_X_CMM=20000,
    parameter integer RETURN_Y_CMM=1000
)(
    input wire clk,rst_n,start,cancel,rearm,reset_job,
    input wire point_valid,input wire [8:0] point_x,point_y,
    input wire point_start,point_end,point_dot,points_done,
    output wire point_ready,
    output wire busy,done,error,cancelled,recovery_required,
    output wire [7:0] error_code,output wire [2:0] job_state,
    output wire [31:0] acked_lines,
    output wire [7:0] tx_data,output wire tx_valid,input wire tx_ready,tx_done,
    input wire [7:0] rx_data,input wire rx_valid,rx_error,link_ready,
    output wire [7:0] rt_data,output wire rt_valid,input wire rt_ready,
    output wire mapper_start,output wire [8:0] mapper_x,mapper_y,
    input wire [15:0] mapper_x_cmm,mapper_y_cmm,input wire mapper_done
);
    localparam [4:0] G_IDLE=0,H_G21=1,H_G90=2,H_UP=3,G_GET=4,G_MAP=5,
        G_POINT=6,G_DOWN=7,G_AFTER_DOWN=8,G_DOT=9,G_UP=10,
        G_FMT_WAIT=11,G_ISSUE=12,G_ACK=13,
        // Format and acknowledge the final absolute return G0 before finish.
        G_RETURN_PREP=14,G_FINISH=15,G_WAIT=16;
    reg [4:0] state,resume_state;
    reg [511:0] line;
    reg [6:0] length;
    reg fmt_start,map_start,fault;
    reg [7:0] fault_code;
    reg [1:0] fmt_kind;
    reg [15:0] fmt_x,fmt_y,fmt_feed;
    reg signed [15:0] fmt_z;
    wire [511:0] fmt_line;
    wire [6:0] fmt_length;
    wire fmt_done,fmt_busy;
    reg [8:0] saved_x,saved_y;
    reg saved_start,saved_end,saved_dot,path_open,points_finished;
    wire [15:0] local_mapped_x,local_mapped_y;
    wire local_mapped_done,line_ready,line_done,stream_busy;
    wire [15:0] mapped_x=EXTERNAL_MAPPER?mapper_x_cmm:local_mapped_x;
    wire [15:0] mapped_y=EXTERNAL_MAPPER?mapper_y_cmm:local_mapped_y;
    wire mapped_done=EXTERNAL_MAPPER?mapper_done:local_mapped_done;
    wire [2:0] stream_state;
    // Reject white canvas margin at the final UART boundary. The planner
    // already clips this region, but retaining the guard prevents an invalid
    // point from becoming machine motion after a malformed stream.
    wire invalid_point=(point_x>319 || point_y<70 || point_y>249 ||
                       (point_start && path_open) || (!point_start && !path_open) ||
                       (point_dot && !(point_start && point_end)) ||
                       (point_start && point_end && !point_dot));
    assign point_ready=(state==G_GET && stream_busy && !points_finished && !cancel && !fault);
    assign busy=stream_busy;
    assign job_state=(stream_busy && state>=H_G21 && state<=H_UP)?3'd1:stream_state;
    grbl_line_formatter #(.X_MAX_CMM(20000)) u_formatter(.I_clk(clk),.I_rst_n(rst_n),.I_start(fmt_start),
        .I_kind(fmt_kind),.I_x_cmm(fmt_x),.I_y_cmm(fmt_y),.I_z_cmm(fmt_z),
        .I_feed(fmt_feed),.I_pwm(16'd0),.O_line(fmt_line),.O_length(fmt_length),
        .O_done(fmt_done),.O_busy(fmt_busy));
    assign mapper_start=map_start;assign mapper_x=saved_x;assign mapper_y=saved_y;
    generate if(!EXTERNAL_MAPPER) begin : g_local_mapper
        doc_grbl_map u_map(.clk(clk),.rst_n(rst_n),.start(map_start),.x(saved_x),.y(saved_y),
            .x_cmm(local_mapped_x),.y_cmm(local_mapped_y),.done(local_mapped_done));
    end endgenerate
    doc_grbl_streamer #(.CLK_HZ(CLK_HZ),.QUERY_MS(QUERY_MS),.STATUS_MS(STATUS_MS),
        .FINAL_MS(FINAL_MS),.PROGRESS_MS(PROGRESS_MS),.JOB_MS(JOB_MS)) u_streamer(
        .clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),.rearm(rearm),.reset_job(reset_job),
        .fault(fault),.fault_code(fault_code),.line(line),.length(length),
        .line_valid(state==G_ISSUE),.finish(state==G_FINISH),
        .line_ready(line_ready),.line_done(line_done),.busy(stream_busy),
        .done(done),.error(error),.cancelled(cancelled),.recovery_required(recovery_required),
        .error_code(error_code),.job_state(stream_state),.acked_lines(acked_lines),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),.tx_done(tx_done),
        .rt_data(rt_data),.rt_valid(rt_valid),.rt_ready(rt_ready),
        .rx_data(rx_data),.rx_valid(rx_valid),.rx_error(rx_error),.link_ready(link_ready));

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=G_IDLE;resume_state<=G_IDLE;line<=0;length<=0;
            fmt_start<=0;map_start<=0;fault<=0;fault_code<=0;
            fmt_kind<=0;fmt_x<=0;fmt_y<=0;fmt_z<=0;fmt_feed<=0;
            saved_x<=0;saved_y<=0;saved_start<=0;saved_end<=0;saved_dot<=0;
            path_open<=0;points_finished<=0;
        end else begin
            fmt_start<=0;map_start<=0;fault<=0;
            if(stream_busy && points_done)points_finished<=1;
            if(cancel || reset_job===1'b1 || error || cancelled || done)begin state<=G_IDLE;path_open<=0;end
            else case(state)
                G_IDLE:if(start && !recovery_required && link_ready)begin
                    state<=H_G21;path_open<=0;points_finished<=points_done;
                end
                H_G21:begin
                    line<=512'h313247;length<=3;resume_state<=H_G90;state<=G_ISSUE;
                end
                H_G90:begin
                    line<=512'h303947;length<=3;resume_state<=H_UP;state<=G_ISSUE;
                end
                H_UP:begin
                    fmt_kind<=2;fmt_z<=-16'sd120;fmt_feed<=1200;
                    fmt_start<=1;resume_state<=G_GET;state<=G_FMT_WAIT;
                end
                G_GET:begin
                    if(point_valid && point_ready)begin
                        if(invalid_point)begin fault<=1;fault_code<=8'h31;state<=G_WAIT;end
                        else begin
                            saved_x<=point_x;saved_y<=point_y;
                            saved_start<=point_start;saved_end<=point_end;saved_dot<=point_dot;
                            map_start<=1;state<=G_MAP;
                        end
                    end else if(points_finished || points_done)begin
                        if(path_open)begin fault<=1;fault_code<=8'h32;state<=G_WAIT;end
                        else state<=G_RETURN_PREP;
                    end
                end
                G_MAP:if(mapped_done)state<=G_POINT;
                G_POINT:begin
                    fmt_x<=mapped_x;fmt_y<=mapped_y;fmt_z<=0;
                    if(saved_start)begin
                        fmt_kind<=0;fmt_feed<=7000;resume_state<=G_DOWN;path_open<=1;
                    end else begin
                        fmt_kind<=1;fmt_feed<=3000;
                        if(saved_end)resume_state<=G_UP;else resume_state<=G_GET;
                    end
                    fmt_start<=1;state<=G_FMT_WAIT;
                end
                G_DOWN:begin
                    fmt_kind<=2;fmt_z<=16'sd500;fmt_feed<=1200;fmt_start<=1;
                    resume_state<=G_AFTER_DOWN;state<=G_FMT_WAIT;
                end
                G_AFTER_DOWN:begin
                    if(saved_dot)state<=G_DOT;else state<=G_GET;
                end
                G_DOT:begin
                    fmt_kind<=1;fmt_x<=(mapped_x<=18990)?mapped_x+16'd10:mapped_x-16'd10;
                    fmt_y<=mapped_y;fmt_feed<=3000;fmt_start<=1;
                    resume_state<=G_UP;state<=G_FMT_WAIT;
                end
                G_UP:begin
                    fmt_kind<=2;fmt_z<=-16'sd120;fmt_feed<=1200;fmt_start<=1;
                    resume_state<=G_GET;state<=G_FMT_WAIT;path_open<=0;
                end
                G_RETURN_PREP:begin
                    // Pen is already up after the last path (or H_UP for an
                    // empty path). This is an ordinary absolute G0, so GRBL
                    // must acknowledge it before the producer finish pulse;
                    // normal completion does not wait for a final Idle poll.
                    // Cancel/fault handling above takes priority and never
                    // enters this state.
                    fmt_kind<=0;fmt_x<=RETURN_X_CMM[15:0];
                    fmt_y<=RETURN_Y_CMM[15:0];fmt_z<=0;fmt_feed<=7000;
                    fmt_start<=1;resume_state<=G_FINISH;state<=G_FMT_WAIT;
                end
                G_FMT_WAIT:if(fmt_done)begin line<=fmt_line;length<=fmt_length;state<=G_ISSUE;end
                G_ISSUE:if(line_ready)state<=G_ACK;
                G_ACK:if(line_done)state<=resume_state;
                G_FINISH:state<=G_WAIT;
                G_WAIT:begin end
                default:begin fault<=1;fault_code<=8'h3f;state<=G_WAIT;end
            endcase
        end
    end
endmodule
