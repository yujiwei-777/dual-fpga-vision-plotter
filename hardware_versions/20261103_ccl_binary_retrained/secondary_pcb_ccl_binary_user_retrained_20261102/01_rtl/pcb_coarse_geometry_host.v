`timescale 1ns/1ps
// One RAM-backed arithmetic engine for both pose offsets and affine packets.
// Scratch belongs exclusively to this host until O_active falls. No partially
// generated offsets or affine packet is committed after cancellation/error.
module pcb_coarse_geometry_host #(
    parameter ROM_FILE="coarse_engine_rom.mem",
    parameter integer POSE_ENTRY=0,
    parameter integer AFFINE_ENTRY=381,
    parameter [14:0] POOL_BASE=15'd13056,
    parameter [14:0] OFFSET_BASE=15'd12800,
    parameter integer WATCHDOG=2000000
) (
    input wire I_clk,I_rst_n,I_cancel,
    input wire I_pose_start,I_affine_start,
    input wire [3:0] I_width_index,I_angle_index,
    input wire [6:0] I_center_x,I_center_y,
    output wire O_ready,O_active,
    output reg O_pose_done,O_pose_valid,
    output reg [3:0] O_pose_error,
    output reg [6:0] O_xmin,O_ymin,
    output reg O_affine_done,O_affine_valid,
    output reg [3:0] O_affine_error,
    output reg [239:0] O_coarse,
    output reg [8:0] O_diagnostic_error,
    output wire O_ws_we,
    output wire [14:0] O_ws_waddr,
    output wire [15:0] O_ws_wdata,
    output wire [14:0] O_ws_rd_addr,
    input wire [15:0] I_ws_rd_data
);
    localparam IDLE=0,PRELOAD=1,PRELOAD_WAIT=2,LAUNCH=3,RUN=4,DRAIN=5;
    localparam integer TIMER_BITS=WATCHDOG>1?$clog2(WATCHDOG):1;
    reg [3:0] state;
    reg affine,bounds_x_seen,bounds_y_seen,bounds_range_fault;
    reg [3:0] width_index,angle_index;
    reg [6:0] center_x,center_y;
    reg [2:0] preload_index;
    reg [8:0] event_count;
    reg [TIMER_BITS-1:0] clocks;
    reg [3:0] pending_error;
    wire engine_busy,engine_done,engine_valid,host_ready,host_done;
    wire [8:0] engine_status,engine_error;
    wire emit_valid;
    wire [8:0] emit_tag;
    wire [31:0] emit_d,emit_a,emit_b;
    wire [6:0] pool_addr;
    wire pool_we;
    wire [15:0] pool_data;
    wire event_shape_valid=affine ?
        (emit_tag==1 && emit_d=={23'd0,event_count} && event_count<6 &&
         emit_b[31:8]=={24{emit_b[7]}}) :
        (emit_tag==0 && emit_d=={23'd0,event_count} && event_count<256 &&
         emit_a[31:8]=={24{emit_a[7]}} && emit_b[31:8]=={24{emit_b[7]}});
    wire malformed=state==RUN && emit_valid && !event_shape_valid;
    wire busy_start=state!=IDLE && (I_pose_start||I_affine_start);
    wire watchdog=state!=IDLE && clocks>=WATCHDOG-1;
    wire abort_now=I_cancel||busy_start||watchdog||malformed;
    // Malformed metadata must fence this cycle's publication immediately, but
    // must not cancel combinationally: engine emit_valid itself is gated by
    // !I_cancel. Cancel the engine on the following DRAIN cycle instead.
    wire engine_cancel=I_cancel||busy_start||watchdog||state==DRAIN;
    wire event_accept=state==RUN && emit_valid && !abort_now;
    wire [5:0] preload_register=preload_index==0?6'd2:
        preload_index==1?6'd3:preload_index==2?6'd58:6'd59;
    wire [31:0] preload_data=preload_index==0?{28'd0,width_index}:
        preload_index==1?{28'd0,angle_index}:
        preload_index==2?{25'd0,center_x}:{25'd0,center_y};
    assign O_ready=state==IDLE&&!engine_busy&&!I_cancel;
    assign O_active=state!=IDLE||engine_busy;
    assign O_ws_we=O_active&&!abort_now&&state!=DRAIN&&
        (pool_we||(event_accept&&!affine));
    assign O_ws_waddr=event_accept&&!affine ? OFFSET_BASE+event_count : POOL_BASE+pool_addr;
    assign O_ws_wdata=event_accept&&!affine ? {emit_b[7:0],emit_a[7:0]}:pool_data;
    // Frozen microcode initially writes original legal-domain DX/DY to R8/R9,
    // then reuses these registers for every emitted offset. Capture only the
    // first low-word write; reading them after HALT would return the last offset.
    assign O_ws_rd_addr=POOL_BASE+{8'd0,pool_addr};
    pcb_microcode_engine_v1 #(.ROM_FILE(ROM_FILE)) engine(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_cancel(engine_cancel),
        .I_host_write(state==PRELOAD&&!abort_now),.I_host_index(preload_register),
        .I_host_data(preload_data),.O_host_ready(host_ready),.O_host_done(host_done),
        .I_start(state==LAUNCH&&!abort_now),.I_entry(affine?AFFINE_ENTRY[15:0]:POSE_ENTRY[15:0]),
        .O_busy(engine_busy),.O_done(engine_done),.O_valid(engine_valid),
        .O_status(engine_status),.O_error(engine_error),.O_emit_valid(emit_valid),
        .I_emit_ready(state==RUN&&!abort_now),.O_emit_tag(emit_tag),
        .O_emit_d(emit_d),.O_emit_a(emit_a),.O_emit_b(emit_b),
        .O_ws_addr(pool_addr),.O_ws_we(pool_we),.O_ws_wdata(pool_data),
        .I_ws_rdata(I_ws_rd_data),.O_pc(),.O_opcode());
    task complete_error;
        input [3:0] code;
        begin
            if(affine)begin O_affine_done<=1;O_affine_valid<=0;O_affine_error<=code;end
            else begin O_pose_done<=1;O_pose_valid<=0;O_pose_error<=code;end
            state<=IDLE;
        end
    endtask
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;affine<=0;bounds_x_seen<=0;bounds_y_seen<=0;bounds_range_fault<=0;
            width_index<=0;angle_index<=0;
            center_x<=0;center_y<=0;preload_index<=0;event_count<=0;clocks<=0;pending_error<=0;
            O_pose_done<=0;O_pose_valid<=0;O_pose_error<=0;O_xmin<=0;O_ymin<=0;
            O_affine_done<=0;O_affine_valid<=0;O_affine_error<=0;O_coarse<=0;O_diagnostic_error<=0;
        end else begin
            O_pose_done<=0;O_affine_done<=0;
            if(state!=IDLE && state!=DRAIN)clocks<=clocks+1'b1;
            if(state!=IDLE && state!=DRAIN && abort_now)begin
                pending_error<=I_cancel?4'd4:busy_start?4'd5:watchdog?4'd6:4'd7;
                O_pose_valid<=0;O_affine_valid<=0;
                O_diagnostic_error<=I_cancel?9'h104:busy_start?9'h108:watchdog?9'h109:9'h10a;
                state<=DRAIN;
            end else case(state)
                IDLE:begin
                    if(I_cancel)begin O_pose_valid<=0;O_affine_valid<=0;end
                    else if(I_pose_start||I_affine_start)begin
                        O_pose_valid<=0;O_affine_valid<=0;O_pose_error<=0;O_affine_error<=0;
                        O_diagnostic_error<=0;event_count<=0;clocks<=0;preload_index<=0;
                        bounds_x_seen<=0;bounds_y_seen<=0;bounds_range_fault<=0;
                        affine<=I_affine_start;width_index<=I_width_index;angle_index<=I_angle_index;
                        center_x<=I_center_x;center_y<=I_center_y;
                        if(I_pose_start&&I_affine_start)begin
                            O_pose_done<=1;O_affine_done<=1;O_pose_error<=5;O_affine_error<=5;
                            O_diagnostic_error<=9'h108;
                        end else state<=PRELOAD;
                    end
                end
                PRELOAD:if(host_ready)state<=PRELOAD_WAIT;
                PRELOAD_WAIT:if(host_done)begin
                    if(preload_index==(affine?3:1))state<=LAUNCH;
                    else begin preload_index<=preload_index+1'b1;state<=PRELOAD;end
                end
                LAUNCH:state<=RUN;
                RUN:begin
                    if(!affine&&pool_we)begin
                        if(pool_addr==7'd16&&!bounds_x_seen)begin
                            O_xmin<=pool_data[6:0];bounds_x_seen<=1;
                            if(pool_data[15:7]!=0)bounds_range_fault<=1;
                        end
                        if(pool_addr==7'd18&&!bounds_y_seen)begin
                            O_ymin<=pool_data[6:0];bounds_y_seen<=1;
                            if(pool_data[15:7]!=0)bounds_range_fault<=1;
                        end
                    end
                    if(event_accept)begin
                        event_count<=event_count+1'b1;
                        if(affine)case(event_count)
                            0:O_coarse[39:0]<={emit_b[7:0],emit_a};
                            1:O_coarse[79:40]<={emit_b[7:0],emit_a};
                            2:O_coarse[119:80]<={emit_b[7:0],emit_a};
                            3:O_coarse[159:120]<={emit_b[7:0],emit_a};
                            4:O_coarse[199:160]<={emit_b[7:0],emit_a};
                            5:O_coarse[239:200]<={emit_b[7:0],emit_a};
                        endcase
                    end
                    if(engine_done)begin
                        O_diagnostic_error<=engine_error;
                        if(!engine_valid||engine_error!=0)complete_error(4'd1);
                        else if(affine)begin
                            if(engine_status!=0||event_count!=6)complete_error(4'd3);
                            else begin O_affine_done<=1;O_affine_valid<=1;state<=IDLE;end
                        end else if(bounds_x_seen&&bounds_y_seen&&!bounds_range_fault&&
                            ((engine_status==0&&event_count==256&&O_xmin<64&&O_ymin<36)||
                             (engine_status==1&&event_count==0&&(O_xmin>=64||O_ymin>=36))))begin
                            O_pose_done<=1;O_pose_valid<=engine_status==0;state<=IDLE;
                        end else complete_error(4'd3);
                    end
                end
                DRAIN:if(!engine_busy)complete_error(pending_error);
                default:complete_error(4'd15);
            endcase
        end
    end
endmodule
