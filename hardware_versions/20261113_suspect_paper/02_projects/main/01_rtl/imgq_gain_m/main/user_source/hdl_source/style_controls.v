// Host-to-camera bundled-data mailbox, with a reverse restore handshake.
// The epoch rejects a host command that was in flight when KEY3 was pressed.
// Payload stays stable until acknowledged; a busy mailbox retains the latest
// pending host selection. Other host ISP settings are deliberately untouched.
module style_controls #(
    parameter integer DEBOUNCE_CYCLES=500000,
    parameter CARTOON_ENABLE=1'b1
)(
    input wire I_clk,I_rst_n,I_key2_n,I_key3_n,I_host_mode,
    input wire I_host_clk,I_host_rst_n,I_host_valid,
    input wire [4:0] I_host_style,
    output wire [4:0] O_style,
    output wire O_restore_busy,
    output reg [4:0] O_host_shadow
);
    wire next_press,restore_press;
    pcb_teach_key #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_next(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_key_n(I_key2_n),.O_press(next_press));
    pcb_teach_key #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_restore(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_key_n(I_key3_n),.O_press(restore_press));
    reg restore_req,restore_ack;
    (* async_reg="true" *) reg [1:0] restore_sync,restore_ack_sync;
    reg req,ack;
    (* async_reg="true" *) reg [1:0] req_sync,ack_sync;
    reg [4:0] payload,pending_style;
    reg payload_epoch,pending;
    reg [4:0] local_style,host_style;
    localparam integer STYLE_COUNT = CARTOON_ENABLE ? 19 : 18;
    wire [5:0] sum={1'b0,local_style}+{1'b0,host_style};
    // Keep the five-bit protocol, but when CART is disabled expose only
    // modes 0..17.  A stale host value 18 is normalized to ORIG before it
    // reaches the ISP or HDMI OSD.
    assign O_style=I_host_mode?((sum>=STYLE_COUNT)?sum-STYLE_COUNT:sum[4:0]):local_style;
    assign O_restore_busy=(restore_ack_sync[1]!=restore_req);
    always @(posedge I_host_clk or negedge I_host_rst_n)begin
        if(!I_host_rst_n)begin
            restore_sync<=0;restore_ack<=0;ack_sync<=0;req<=0;
            payload<=0;payload_epoch<=0;pending<=0;pending_style<=0;O_host_shadow<=0;
        end else begin
            restore_sync<={restore_sync[0],restore_req};ack_sync<={ack_sync[0],ack};
            if(restore_sync[1]!=restore_ack)begin
                restore_ack<=restore_sync[1];O_host_shadow<=0;pending<=0;pending_style<=0;
            end else if(I_host_valid)begin
                O_host_shadow<=(I_host_style<STYLE_COUNT)?I_host_style:0;
                pending_style<=(I_host_style<STYLE_COUNT)?I_host_style:0;pending<=1;
            end else if(pending && ack_sync[1]==req)begin
                payload<=pending_style;payload_epoch<=restore_ack;
                req<=~req;pending<=0;
            end
        end
    end
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            req_sync<=0;restore_ack_sync<=0;restore_req<=0;ack<=0;local_style<=0;host_style<=0;
        end else begin
            req_sync<={req_sync[0],req};restore_ack_sync<={restore_ack_sync[0],restore_ack};
            if(req_sync[1]!=ack)begin
                ack<=req_sync[1];
                if(payload_epoch==restore_req)host_style<=payload;
            end
            if(next_press)local_style<=(local_style==STYLE_COUNT-1)?0:local_style+1'b1;
            if(restore_press)begin
                local_style<=0;host_style<=0;
                // A held press never repeats; a second press while the
                // handshake is busy still restores locally without wrapping
                // the epoch and accidentally accepting an old command.
                if(!O_restore_busy)restore_req<=~restore_req;
            end
        end
    end
endmodule
