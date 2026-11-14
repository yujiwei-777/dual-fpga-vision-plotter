

module mc_to_user_interface (
    input wire          I_clk,
    input wire          I_rst_n,

    /*
        ddr user interface
        当I_ddr_user_ready拉低时，还能写入8个长度数据
    */
    input wire          I_ddr_user_wr_en,
    input wire          I_ddr_user_rd_en,  //synthesis keep
    input wire[24:0]    I_ddr_user_addr,
    input wire[127:0]   I_ddr_user_wr_data,
    output wire         O_ddr_user_ready,
    output wire         O_ddr_user_rd_valid,
    output wire[127:0]  O_ddr_user_rd_data,
    output wire         O_write_retire,
    output wire[24:0]   O_write_retire_addr,

    /*
        ddr memory controller interface
    */
    output  wire        O_mc_app_en,
    output  wire [24:0] O_mc_app_addr,
    output  wire [2:0]  O_mc_app_cmd,
    input  wire         I_mc_app_rdy,
    output wire         O_mc_app_wdf_wren,
    output wire [127:0] O_mc_app_wdf_data,
    output wire         O_mc_app_wdf_end,
    output wire [31:0]  O_mc_app_wdf_mask,
    input wire          I_mc_app_wdf_rdy,
    input wire [127:0]  I_mc_app_rd_data,
    input wire          I_mc_app_rd_data_end,
    input wire          I_mc_app_rd_data_valid
);

    wire        S_fifo_wr_en;    
    wire[154:0] S_fifo_wr_data;
    wire        S_fifio_pro_full;
    wire        S_fifo_rd_en;    
    wire[154:0] S_fifo_rd_data;
    wire        S_fifo_rd_valid;
    wire        S_fifo_empty;   

    // The vendor command FIFO keeps its pointers in reset for two clock
    // edges after rst deasserts. afull is LOW during that interval: it is
    // not an indication that writes can already be accepted. Advertising
    // ready then loses the first display read while the arbiter counts it,
    // leaving a permanent pending read that blocks snapshot ownership.
    // Wait four local edges before admitting any command. This also covers
    // clients whose reset releases before this bridge's reset.
    reg [3:0] fifo_startup;
    wire fifo_operational = fifo_startup[3];
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) fifo_startup <= 4'b0000;
        else fifo_startup <= {fifo_startup[2:0],1'b1};
    end

    // Gate startup only, not afull: the camera has an already-authorized
    // registered final write after ready falls, covered by FIFO headroom.
    assign S_fifo_wr_en = fifo_operational &&
                         (I_ddr_user_wr_en | I_ddr_user_rd_en);

    assign S_fifo_wr_data = {I_ddr_user_wr_en,I_ddr_user_rd_en,I_ddr_user_addr,I_ddr_user_wr_data};

    // Keep the FIFO head stable until the independent command and write
    // data channels have each accepted it. A read needs only command ready.
    // Command/address/valid never depend combinationally on ready.
    reg command_accepted, data_accepted;
    wire head_write=S_fifo_rd_data[154];
    wire command_fire=O_mc_app_en&&I_mc_app_rdy;
    wire data_fire=O_mc_app_wdf_wren&&I_mc_app_wdf_rdy;
    assign S_fifo_rd_en = fifo_operational && !S_fifo_empty &&
        (command_accepted||command_fire) &&
        (!head_write||data_accepted||data_fire);
    assign O_write_retire=S_fifo_rd_en&&head_write;
    assign O_write_retire_addr=S_fifo_rd_data[152:128];
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin command_accepted<=0;data_accepted<=0;end
        else if(!fifo_operational || S_fifo_rd_en) begin command_accepted<=0;data_accepted<=0;end
        else begin
            if(command_fire)command_accepted<=1;
            if(data_fire)data_accepted<=1;
        end
    end

    assign O_ddr_user_ready = fifo_operational && ~S_fifio_pro_full;

    assign O_mc_app_en = fifo_operational&&!S_fifo_empty&&!command_accepted;

    assign O_mc_app_addr = S_fifo_rd_data[152:128];

    assign O_mc_app_cmd = S_fifo_rd_data[153] ? 3'd1 : 3'd0;

    assign O_mc_app_wdf_wren = fifo_operational&&!S_fifo_empty&&head_write&&!data_accepted;

    assign O_mc_app_wdf_end = O_mc_app_wdf_wren;

    assign O_mc_app_wdf_mask = 'd0;

    assign O_mc_app_wdf_data = S_fifo_rd_data[127:0];

    assign O_ddr_user_rd_valid = I_mc_app_rd_data_valid;
    
    assign O_ddr_user_rd_data = I_mc_app_rd_data;

    w155_d512_fifo U_w155_d512_fifo(
        .clk        ( I_clk            ),     
        .rst        ( ~I_rst_n         ),     

        .we         ( S_fifo_wr_en     ),
        .di         ( S_fifo_wr_data   ),
        .afull      ( S_fifio_pro_full ),
        .full_flag  (),
        .wrusedw    (),
 
        .re         ( S_fifo_rd_en     ), 
        .valid      ( S_fifo_rd_valid  ), 
        .dout       ( S_fifo_rd_data   ),  
        .empty_flag ( S_fifo_empty     ),
        .aempty     (),
        .rdusedw    ()
    );
    
endmodule
