// Iterative decimal conversion: one small add/shift datapath, no /10 in RTL.
module grbl_decimal(
    input wire I_clk,input wire I_rst_n,input wire I_start,input wire [31:0] I_value,
    output reg [39:0] O_bcd,output reg O_done,output reg O_busy
);
    reg [31:0] binary;
    reg [5:0] count;
    reg [39:0] adjusted;
    integer i;
    always @*begin
        adjusted=O_bcd;
        for(i=0;i<10;i=i+1)
            if(O_bcd[i*4+:4]>=5)adjusted[i*4+:4]=O_bcd[i*4+:4]+4'd3;
    end
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin O_bcd<=0;binary<=0;count<=0;O_done<=0;O_busy<=0;end
        else begin
            O_done<=0;
            if(I_start && !O_busy)begin O_bcd<=0;binary<=I_value;count<=0;O_busy<=1;end
            else if(O_busy)begin
                O_bcd<={adjusted[38:0],binary[31]};binary<={binary[30:0],1'b0};
                if(count==31)begin O_busy<=0;O_done<=1;end
                else count<=count+1'b1;
            end
        end
    end
endmodule

// kind=0 G0 XY F, 1 G1 XY F, 2 G1 Z F, 3 M3 S.
// XY/Z units are 0.01 mm; feed units are mm/min; all feed inputs positive.
module grbl_line_formatter #(
    parameter integer PLOT_MIRROR_X=1,
    parameter integer X_MIN_CMM=1000,
    // Keep the released PCB/CNN report profile at 19000 cmm.  The document
    // plotter overrides this parameter to 20000 for its 10..200 mm A4 box.
    parameter integer X_MAX_CMM=19000
)(
    input wire I_clk,input wire I_rst_n,input wire I_start,input wire [1:0] I_kind,
    input wire [15:0] I_x_cmm,input wire [15:0] I_y_cmm,
    input wire signed [15:0] I_z_cmm,input wire [15:0] I_feed,input wire [15:0] I_pwm,
    output reg [511:0] O_line,output reg [6:0] O_length,output reg O_done,output wire O_busy
);
    reg [2:0] state;
    reg [1:0] kind;
    reg [15:0] y,feed;
    reg negative;
    reg dec_start;
    reg [31:0] dec_value;
    wire [39:0] dec_bcd;
    wire dec_done,dec_busy;
    reg [19:0] bcd_x,bcd_y,bcd_feed;
    reg [511:0] formatted;
    reg [6:0] formatted_length;
    integer j;
    function [15:0] plot_x;
        input [15:0] value;
        begin
            plot_x=(PLOT_MIRROR_X != 0) ? X_MIN_CMM+X_MAX_CMM-value : value;
        end
    endfunction
    assign O_busy=(state!=0);
    grbl_decimal u_decimal(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(dec_start),.I_value(dec_value),
                          .O_bcd(dec_bcd),.O_done(dec_done),.O_busy(dec_busy));
    always @*begin
        formatted=0;formatted_length=0;
        if(kind==3)begin
            formatted[7:0]="M";formatted[15:8]="3";formatted[23:16]=" ";formatted[31:24]="S";
            for(j=0;j<5;j=j+1)formatted[(4+j)*8+:8]=8'h30+{4'd0,bcd_x[(4-j)*4+:4]};
            formatted_length=9;
        end else if(kind==2)begin
            formatted[7:0]="G";formatted[15:8]="1";formatted[23:16]=" ";formatted[31:24]="Z";
            formatted[39:32]=negative?"-":"+";
            formatted[47:40]=8'h30+{4'd0,bcd_x[19:16]};
            formatted[55:48]=8'h30+{4'd0,bcd_x[15:12]};
            formatted[63:56]=8'h30+{4'd0,bcd_x[11:8]};formatted[71:64]=".";
            formatted[79:72]=8'h30+{4'd0,bcd_x[7:4]};formatted[87:80]=8'h30+{4'd0,bcd_x[3:0]};
            formatted[95:88]=" ";formatted[103:96]="F";
            for(j=0;j<5;j=j+1)formatted[(13+j)*8+:8]=8'h30+{4'd0,bcd_feed[(4-j)*4+:4]};
            formatted_length=18;
        end else begin
            formatted[7:0]="G";formatted[15:8]=(kind==0)?"0":"1";
            formatted[23:16]=" ";formatted[31:24]="X";
            formatted[39:32]=8'h30+{4'd0,bcd_x[19:16]};formatted[47:40]=8'h30+{4'd0,bcd_x[15:12]};
            formatted[55:48]=8'h30+{4'd0,bcd_x[11:8]};formatted[63:56]=".";
            formatted[71:64]=8'h30+{4'd0,bcd_x[7:4]};formatted[79:72]=8'h30+{4'd0,bcd_x[3:0]};
            formatted[87:80]=" ";formatted[95:88]="Y";
            formatted[103:96]=8'h30+{4'd0,bcd_y[19:16]};formatted[111:104]=8'h30+{4'd0,bcd_y[15:12]};
            formatted[119:112]=8'h30+{4'd0,bcd_y[11:8]};formatted[127:120]=".";
            formatted[135:128]=8'h30+{4'd0,bcd_y[7:4]};formatted[143:136]=8'h30+{4'd0,bcd_y[3:0]};
            formatted[151:144]=" ";formatted[159:152]="F";
            for(j=0;j<5;j=j+1)formatted[(20+j)*8+:8]=8'h30+{4'd0,bcd_feed[(4-j)*4+:4]};
            formatted_length=25;
        end
    end
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=0;kind<=0;y<=0;feed<=0;negative<=0;dec_start<=0;dec_value<=0;
            bcd_x<=0;bcd_y<=0;bcd_feed<=0;O_line<=0;O_length<=0;O_done<=0;
        end else begin
            O_done<=0;dec_start<=0;
            case(state)
                0:if(I_start)begin
                    kind<=I_kind;y<=I_y_cmm;feed<=I_feed;negative<=I_z_cmm[15];
                    if(I_kind==3)dec_value<={16'd0,I_pwm};
                    else if(I_kind==2)dec_value<=I_z_cmm[15]?{16'd0,(~I_z_cmm+16'd1)}:{16'd0,I_z_cmm};
                    else dec_value<={16'd0,plot_x(I_x_cmm)};
                    dec_start<=1;state<=1;
                end
                1:if(dec_done)begin
                    bcd_x<=dec_bcd[19:0];
                    if(kind==3)state<=4;
                    else begin dec_value<={16'd0,y};dec_start<=1;state<=2;end
                end
                2:if(dec_done)begin bcd_y<=dec_bcd[19:0];dec_value<={16'd0,feed};dec_start<=1;state<=3;end
                3:if(dec_done)begin bcd_feed<=dec_bcd[19:0];state<=4;end
                4:begin O_line<=formatted;O_length<=formatted_length;O_done<=1;state<=0;end
                default:state<=0;
            endcase
        end
    end
endmodule
