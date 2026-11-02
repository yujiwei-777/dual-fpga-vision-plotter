// Compact 16x16 breadth-first maze solver. All per-cell state is held in one
// synchronous single-port RAM: {visited,parent_direction,walls}. The queue
// is a second synchronous RAM. RAM read/write processes deliberately have
// no reset; a full ST_COPY initializes every cell before a search begins.
// walls: bit 0=N, 1=E, 2=S, 3=W. status: 0 NO_ROUTE, 1 EXACT, 2 APPROX.
module maze_solver_16x16(
    input wire clk,input wire rst_n,input wire start,
    input wire [1023:0] walls,input wire markers_valid,
    input wire [7:0] start_cell,input wire [7:0] goal_cell,
    output reg busy,output reg done,output reg [1:0] status,
    output reg [8:0] steps,output reg [7:0] endpoint,
    output reg [511:0] directions
);
    localparam ST_IDLE=4'd0,ST_COPY=4'd1,ST_INIT_READ=4'd2,
               ST_INIT=4'd3,ST_POP=4'd4,ST_POP_WAIT=4'd5,
               ST_CURRENT_READ=4'd6,ST_CURRENT_WAIT=4'd7,
               ST_NEIGH_READ=4'd8,ST_NEIGH=4'd9,ST_RECON_READ=4'd10,
               ST_RECON_WRITE=4'd11,ST_FINISH=4'd12;
    reg [3:0] state;
    reg [7:0] saved_start,saved_goal,copy_cell;
    (* ram_style="bram" *) reg [7:0] queue [0:255] /* synthesis syn_ramstyle="block_ram" */;
    (* ram_style="bram" *) reg [6:0] cell_mem [0:255] /* synthesis syn_ramstyle="block_ram" */;
    reg [7:0] queue_rd_data; reg [6:0] cell_rd_data;
    reg [3:0] current_walls;
    reg [8:0] q_rd,q_wr,level_remaining,next_level_count,wave_depth;
    reg [7:0] current_cell,recon_cell; reg [1:0] neighbour_dir;
    reg [8:0] recon_index; reg [7:0] best_cell; reg [8:0] best_depth,best_manhattan;
    reg neighbour_valid,edge_blocked; reg [7:0] neighbour_cell; reg [1:0] opposite_dir; reg [8:0] candidate_manhattan;
    function [8:0] cell_manhattan; input [7:0] a; input [7:0] b; reg [4:0] dx,dy;
        begin if(a[3:0]>=b[3:0])dx=a[3:0]-b[3:0];else dx=b[3:0]-a[3:0]; if(a[7:4]>=b[7:4])dy=a[7:4]-b[7:4];else dy=b[7:4]-a[7:4]; cell_manhattan={4'd0,dx}+{4'd0,dy}; end
    endfunction
    always @* begin
        neighbour_valid=0;neighbour_cell=current_cell;opposite_dir=0;
        case(neighbour_dir)
            0:if(current_cell[7:4]!=0)begin neighbour_valid=1;neighbour_cell=current_cell-8'd16;opposite_dir=2;end
            1:if(current_cell[3:0]!=15)begin neighbour_valid=1;neighbour_cell=current_cell+1;opposite_dir=3;end
            2:if(current_cell[7:4]!=15)begin neighbour_valid=1;neighbour_cell=current_cell+8'd16;opposite_dir=0;end
            default:if(current_cell[3:0]!=0)begin neighbour_valid=1;neighbour_cell=current_cell-1;opposite_dir=1;end
        endcase
        edge_blocked=1; if(neighbour_valid)edge_blocked=current_walls[neighbour_dir]|cell_rd_data[opposite_dir];
        candidate_manhattan=cell_manhattan(neighbour_cell,saved_goal);
    end
    reg [7:0] parent_cell; reg [1:0] forward_dir;
    always @* begin
        parent_cell=recon_cell;forward_dir=0;
        case(cell_rd_data[5:4])
            0:begin parent_cell=recon_cell-8'd16;forward_dir=2;end
            1:begin parent_cell=recon_cell+1;forward_dir=3;end
            2:begin parent_cell=recon_cell+8'd16;forward_dir=0;end
            default:begin parent_cell=recon_cell-1;forward_dir=1;end
        endcase
    end
    wire accept_neighbour = (state==ST_NEIGH) && neighbour_valid && !edge_blocked && !cell_rd_data[6];
    reg [7:0] cell_addr,queue_addr;
    reg [6:0] cell_wr_data;
    reg [7:0] queue_wr_data;
    reg cell_write,queue_write;
    always @* begin
        cell_addr=current_cell;cell_wr_data=7'd0;cell_write=0;
        case(state)
            ST_COPY:begin cell_addr=copy_cell;cell_wr_data={3'b000,walls[{copy_cell,2'b00}+:4]};cell_write=1;end
            ST_INIT_READ:cell_addr=saved_start;
            ST_INIT:begin cell_addr=saved_start;cell_wr_data={1'b1,2'b00,cell_rd_data[3:0]};cell_write=1;end
            ST_NEIGH_READ,ST_NEIGH:begin
                cell_addr=neighbour_cell;
                cell_wr_data={1'b1,opposite_dir,cell_rd_data[3:0]};
                cell_write=accept_neighbour;
            end
            ST_RECON_READ,ST_RECON_WRITE:cell_addr=recon_cell;
            default:;
        endcase
        queue_addr=q_rd[7:0];queue_wr_data=neighbour_cell;queue_write=0;
        if(state==ST_INIT)begin queue_addr=0;queue_wr_data=saved_start;queue_write=1;end
        else if(accept_neighbour)begin queue_addr=q_wr[7:0];queue_write=1;end
    end
    // Single-port synchronous RAM templates, with the address shared by
    // read and write. No combinational cell reads or RAM output resets.
    always @(posedge clk) begin
        if(cell_write)cell_mem[cell_addr]<=cell_wr_data;
        else cell_rd_data<=cell_mem[cell_addr];
        if(queue_write)queue[queue_addr]<=queue_wr_data;
        else queue_rd_data<=queue[queue_addr];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin state<=ST_IDLE;busy<=0;done<=0;status<=0;steps<=0;endpoint<=0;directions<=0;saved_start<=0;saved_goal<=0;copy_cell<=0;current_walls<=0;q_rd<=0;q_wr<=0;level_remaining<=0;next_level_count<=0;wave_depth<=0;current_cell<=0;recon_cell<=0;neighbour_dir<=0;recon_index<=0;best_cell<=0;best_depth<=0;best_manhattan<=9'h1ff;end
        else begin done<=0; case(state)
            ST_IDLE:begin busy<=0;if(start)begin busy<=1;saved_start<=start_cell;saved_goal<=goal_cell;status<=0;steps<=0;endpoint<=0;directions<=0;q_rd<=0;q_wr<=0;level_remaining<=0;next_level_count<=0;wave_depth<=0;best_cell<=start_cell;best_depth<=0;best_manhattan<=cell_manhattan(start_cell,goal_cell);copy_cell<=0;state<=markers_valid?ST_COPY:ST_FINISH;end end
            ST_COPY:begin if(copy_cell==255)state<=ST_INIT_READ;else copy_cell<=copy_cell+1;end
            ST_INIT_READ:state<=ST_INIT;
            ST_INIT:begin q_rd<=0;q_wr<=1;level_remaining<=1;next_level_count<=0;wave_depth<=0;best_cell<=saved_start;best_depth<=0;if(saved_start==saved_goal)begin status<=1;endpoint<=saved_start;state<=ST_FINISH;end else state<=ST_POP;end
            ST_POP:begin if(level_remaining==0)begin if(q_rd==q_wr)begin status<=2;endpoint<=best_cell;steps<=best_depth;recon_cell<=best_cell;recon_index<=best_depth;state<=best_depth==0?ST_FINISH:ST_RECON_READ;end else begin level_remaining<=next_level_count;next_level_count<=0;wave_depth<=wave_depth+1;end end else begin q_rd<=q_rd+1;level_remaining<=level_remaining-1;state<=ST_POP_WAIT;end end
            ST_POP_WAIT:begin current_cell<=queue_rd_data;neighbour_dir<=0;state<=ST_CURRENT_READ;end
            ST_CURRENT_READ:state<=ST_CURRENT_WAIT;
            ST_CURRENT_WAIT:begin current_walls<=cell_rd_data[3:0];state<=ST_NEIGH_READ;end
            ST_NEIGH_READ:state<=ST_NEIGH;
            ST_NEIGH:begin
                if(accept_neighbour)begin
                    q_wr<=q_wr+1;next_level_count<=next_level_count+1;
                    if(candidate_manhattan<best_manhattan||(candidate_manhattan==best_manhattan&&(wave_depth+1<best_depth||(wave_depth+1==best_depth&&neighbour_cell<best_cell))))begin best_manhattan<=candidate_manhattan;best_depth<=wave_depth+1;best_cell<=neighbour_cell;end
                    if(neighbour_cell==saved_goal)begin status<=1;endpoint<=neighbour_cell;steps<=wave_depth+1;recon_cell<=neighbour_cell;recon_index<=wave_depth+1;state<=ST_RECON_READ;end
                    else if(neighbour_dir==3)state<=ST_POP;
                    else begin neighbour_dir<=neighbour_dir+1;state<=ST_NEIGH_READ;end
                end else if(neighbour_dir==3)state<=ST_POP;
                else begin neighbour_dir<=neighbour_dir+1;state<=ST_NEIGH_READ;end
            end
            ST_RECON_READ:state<=ST_RECON_WRITE;
            // Reverse traversal emits last-to-first. Prepending each new
            // direction places the final start direction in bits [1:0]
            // without a 256-way indexed write decoder.
            ST_RECON_WRITE:begin directions<={directions[509:0],forward_dir};recon_cell<=parent_cell;recon_index<=recon_index-1;if(recon_index==1)state<=ST_FINISH;else state<=ST_RECON_READ;end
            ST_FINISH:begin busy<=0;done<=1;state<=ST_IDLE;end
            default:state<=ST_IDLE;
        endcase end
    end
endmodule
