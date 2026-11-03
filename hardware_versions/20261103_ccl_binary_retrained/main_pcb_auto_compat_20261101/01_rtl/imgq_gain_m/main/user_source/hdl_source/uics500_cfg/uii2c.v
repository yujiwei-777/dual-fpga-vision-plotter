
/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2022/12/23
*Module Name:uii2c
*File Name:uii2c.v
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.1
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/

/*******************************I2C控制器 MASTER*********************
--以下是米联客设计的I2C总线MASTER控制器
--1.代码简洁，占用极少逻辑资源，代码结构清晰，逻辑设计严谨
--2.使用方便，只需要把发送的数据放入寄存器，就可以自动支持任意长度的写数据
--3.使用方便，只需要把读的数据告知控制器，就可以自动支持任意长度的读数据
--4.1.1版本，升级了O_iic_bus_error标志信号，当总线写操作没有ACK返回，设置O_iic_bus_error，可以通过观察O_iic_bus_error查看总线是否有错误
*********************************************************************/

`timescale 1ns / 1ns //仿真刻度/精度

module uii2c#
(
parameter integer WMEN_LEN = 8'd0,//写长度，以字节为单位，包含器件地址
parameter integer RMEN_LEN = 8'd0,//读长度，以字节为单位，不包含器件地址
parameter integer CLK_DIV  = 16'd499// I2C时钟分频系数
)
(
input  wire I_clk,//系统时钟输入
input  wire I_rstn,//系统复位，低电平有效
output reg  O_iic_scl = 1'b0,//I2C时钟SCL
inout  wire IO_iic_sda,//I2C 数据总线
input  wire [WMEN_LEN*8-1'b1:0]I_wr_data,//写数据寄存器，其中WMEN_LEN设置了最大支持的数据字节数，越大占用的FPGA资源越多
input  wire [7:0]I_wr_cnt,//写数据计数器，代表写了多少个字节
output reg  [RMEN_LEN*8-1'b1:0]O_rd_data = 0,//读数据寄存器，其中RMEN_LEN设置了最大支持的数据字节数，越大占用的FPGA资源越多
input  wire [7:0]I_rd_cnt,//读数据计数器
input  wire I_iic_req,//I_iic_req == 1 使能I2C传输
input  wire I_iic_mode,//I_iic_mode = 1 随机读   I_iic_mode = 0 读当前寄存器或者页读
output reg  O_iic_busy = 1'b0,//I2C控制器忙
output reg  O_iic_bus_error, //I2C总线，无法读到正确ACK出错
output reg  IO_iic_sda_dg
);

// The source config FSM and the SCL divider both change on posedge I_clk.
// Sample the request and payload on the opposite source edge, providing half
// an I_clk period of hold margin at either generated SCL edge. These paths
// remain timed normally; no data-path exception is needed. Payload/counts
// remain stable for the complete request/busy handshake, as before.
reg [WMEN_LEN*8-1:0] wr_data_half;
reg [7:0] wr_cnt_half, rd_cnt_half;
reg iic_req_half = 1'b0;
reg iic_mode_half;
always @(negedge I_clk) begin
    wr_data_half <= I_wr_data;
    wr_cnt_half <= I_wr_cnt;
    rd_cnt_half <= I_rd_cnt;
    iic_req_half <= I_rstn && I_iic_req;
    iic_mode_half <= I_iic_mode;
end

localparam IDLE    = 4'd0;//I2C 总线空闲状态
localparam START   = 4'd1;//I2C 总线启动
localparam W_WAIT  = 4'd2;//I2C 总线等待写完成
localparam W_ACK   = 4'd3;//I2C 总线等待写WACK
localparam R_WAIT  = 4'd4;//I2C 总线等待读完成 
localparam R_ACK   = 4'd5;//I2C 总线等待读RACK 
localparam STOP1   = 4'd6;//I2C 总线产生停止位
localparam STOP2   = 4'd7;//I2C 总线产生停止位   

localparam SCL_DIV = CLK_DIV/2;

localparam OFFSET = SCL_DIV - SCL_DIV/4;//设置I2C总线的SCL时钟的偏移，以满足SCL和SDA的时序要求，外部的SCL延迟内部的半周期的四分之三

reg [2:0] IIC_S = 4'd0; //I2C 状态机
//generate  scl
reg [15:0] clkdiv = 16'd0;   //I2C 时钟分频寄存器
reg scl_r 	   = 1'b1;       //I2C控制器的SCL内部时钟
reg sda_o 	   = 1'b0;       //I2C控制器的SDA
reg scl_clk_raw = 1'b0;
// SCL is a protocol waveform, not a second FPGA clock. Keep all sequential
// logic in the source I_clk domain and use one-cycle edge enables below. The
// former LUT-generated clock path was the source of RTCLK-5078.
wire scl_tick = (clkdiv == SCL_DIV);
wire scl_rise_tick = scl_tick && (scl_clk_raw == 1'b0);
wire scl_fall_tick = scl_tick && (scl_clk_raw == 1'b1);
reg [7:0] sda_r = 8'd0;      //发送寄存器
reg [7:0] sda_i_r = 8'd0;    //接收寄存器
reg [7:0] wcnt = 8'd0;       //发送数据计数器，以byte为单位
reg [7:0] rcnt = 8'd0;       //接收数据计数器，以byte为单位
reg [2:0] bcnt = 3'd0;       //bit计数器
reg  rd_req = 1'b0;          //读请求，当判断到需要读数据，内部状态机中设置1
wire sda_i;                  //sda 输入
wire scl_offset;             //scl 时钟偏移控制

assign  sda_i   = IO_iic_sda ;  //读总线 
assign  IO_iic_sda = (sda_o == 1'b0) ?  1'b0 : 1'bz;    //写总线，1'bz代表高阻，I2C外部通过上拉电阻，实现总线的高电平

//PULLUP PULLUP_inst (.O(iic_sda));

//XILINX I2C 用IOBUF实现控制
//IOBUF #(
//.DRIVE(12), // Specify the output drive strength
//.IBUF_LOW_PWR("TRUE"),  // Low Power - "TRUE", High Performance = "FALSE" 
//.IOSTANDARD("DEFAULT"), // Specify the I/O standard
//.SLEW("SLOW") // Specify the output slew rate
//) IOBUF_inst (
//.O(sda_i),    // Buffer output
//.IO(IO_iic_sda), // Buffer inout port (connect directly to top-level port)
//.I(sda_o),    // Buffer input
//.T(sda_o)     // 3-state enable input, high=input, low=output
//);

//scl 时钟分频器
assign  scl_offset  = (clkdiv == OFFSET);//设置scl_offset的时间参数
always @(posedge I_clk) O_iic_scl <=  scl_offset ?  scl_r : O_iic_scl; //O_iic_scl延迟scl_offset时间的scl_r

//采集I2C 数据总线sda
always @(posedge I_clk) IO_iic_sda_dg <= sda_i;  

//当IIC_S状态机处于，同时空闲状态，设置SCL为高电平，同时也是空闲，停止状态，用于产生起始位和停止位时序，否则寄存scl_clk时钟
always @(*) 
    if(IIC_S == IDLE || IIC_S == STOP1 || IIC_S == STOP2)
        scl_r <= 1'b1;
    else 
        scl_r <= scl_clk_raw;
  

//当进入IIC_S状态为启动、停止设置sda=0，结合scl产生起始位，或者(IIC_S == R_ACK && (rcnt != rd_cnt_half) sda=0，用于产生读操作的ACK
always @(*) 
    if(IIC_S == START || IIC_S == STOP1 || (IIC_S == R_ACK && (rcnt != rd_cnt_half)))
        sda_o <= 1'b0;
    else if(IIC_S == W_WAIT)
        sda_o <= sda_r[7]; 
    else  sda_o <= 1'b1; //否则其他状态都为1，当(IIC_S == R_ACK && (rcnt == rd_cnt_half) 产生一个NACK 

//I2C数据发送模块，所有的写数据都通过此模块发送
// All former posedge/negedge scl_clk_g blocks are expressed as I_clk-domain
// edge enables. This preserves the original SCL protocol timing while keeping
// the implementation on one legal clock domain.
always @(posedge I_clk or negedge I_rstn) begin
    if (!I_rstn) begin
        clkdiv          <= 16'd0;
        scl_clk_raw     <= 1'b0;
        sda_r           <= 8'd0;
        sda_i_r         <= 8'd0;
        O_rd_data       <= 0;
        O_iic_busy      <= 1'b0;
        O_iic_bus_error <= 1'b0;
        wcnt            <= 8'd0;
        rcnt            <= 8'd0;
        rd_req          <= 1'b0;
        bcnt            <= 3'd0;
        IIC_S           <= IDLE;
    end else begin
        if (clkdiv < SCL_DIV)
            clkdiv <= clkdiv + 1'b1;
        else begin
            clkdiv      <= 16'd0;
            scl_clk_raw <= ~scl_clk_raw;
        end

        if (scl_rise_tick) begin
            if (IIC_S == W_ACK || IIC_S == START) begin
                sda_r <= wr_data_half[(wcnt*8) +: 8];
                if (rd_req) sda_r <= {wr_data_half[7:1],1'b1};
            end else if (IIC_S == W_WAIT)
                sda_r <= {sda_r[6:0],1'b1};

            if (iic_req_half || rd_req || O_iic_bus_error)
                O_iic_busy <= 1'b1;
            else if (IIC_S == IDLE)
                O_iic_busy <= 1'b0;

            case (IIC_S)
                IDLE: begin
                    if (iic_req_half || rd_req) IIC_S <= START;
                    else begin wcnt <= 8'd0; rcnt <= 8'd0; end
                end
                START: begin bcnt <= 3'd7; IIC_S <= W_WAIT; end
                W_WAIT: begin
                    if (bcnt > 3'd0) bcnt <= bcnt - 1'b1;
                    else begin wcnt <= wcnt + 1'b1; IIC_S <= W_ACK; end
                end
                W_ACK: begin
                    if (wcnt < wr_cnt_half) begin
                        bcnt <= 3'd7; IIC_S <= W_WAIT;
                    end else if (rd_cnt_half > 3'd0) begin
                        if (!rd_req && iic_mode_half) begin
                            rd_req <= 1'b1; IIC_S <= IDLE;
                        end else begin
                            IIC_S <= R_WAIT; bcnt <= 3'd7;
                        end
                    end else IIC_S <= STOP1;
                end
                R_WAIT: begin
                    rd_req <= 1'b0;
                    bcnt <= bcnt - 1'b1;
                    if (bcnt == 3'd0) begin
                        rcnt <= (rcnt < rd_cnt_half) ? (rcnt + 1'b1) : rcnt;
                        IIC_S <= R_ACK;
                    end
                end
                R_ACK: begin
                    bcnt <= 3'd7;
                    IIC_S <= (rcnt < rd_cnt_half) ? R_WAIT : STOP1;
                end
                STOP1: begin rd_req <= 1'b0; IIC_S <= STOP2; end
                STOP2: IIC_S <= IDLE;
                default: IIC_S <= IDLE;
            endcase
        end

        if (scl_fall_tick) begin
            if (IIC_S == R_WAIT)
                sda_i_r <= {sda_i_r[6:0],sda_i};
            else if (IIC_S == R_ACK)
                O_rd_data[((rcnt-1'b1)*8) +: 8] <= sda_i_r[7:0];
            else if (IIC_S == IDLE)
                sda_i_r <= 8'd0;

            if (IIC_S == W_ACK && sda_i)
                O_iic_bus_error <= 1'b1;
            else if (!iic_req_half)
                O_iic_bus_error <= 1'b0;
        end
    end
end

endmodule
