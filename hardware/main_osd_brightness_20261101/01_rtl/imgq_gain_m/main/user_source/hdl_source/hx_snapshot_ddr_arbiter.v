// The original camera/display clients retain their 240-beat transactions.
// Snapshot clients use short transactions. Only one read owner may have
// outstanding responses; ownership changes only after the last response.
module hx_snapshot_ddr_arbiter #(
    parameter integer SNAP_BURST=32,
    parameter integer LEGACY_WINDOW=32
)(
    input wire I_clk,I_rst_n,
    input wire I_vi_active,I_vo_active,
    input wire I_vi_wr_en,input wire [24:0] I_vi_addr,input wire [127:0] I_vi_data,
    input wire I_vo_rd_en,input wire [24:0] I_vo_addr,
    output wire O_legacy_ready,O_bus_pause,O_video_rd_valid,
    input wire I_snap_wr_valid,input wire [24:0] I_snap_wr_addr,
    input wire [127:0] I_snap_wr_data,output wire O_snap_wr_ready,
    input wire I_snap_rd_valid,input wire [24:0] I_snap_rd_addr,
    output wire O_snap_rd_ready,O_snap_rd_valid,
    input wire I_mc_ready,I_mc_rd_valid,
    output wire O_mc_wr_en,O_mc_rd_en,
    output wire [24:0] O_mc_addr,output wire [127:0] O_mc_wr_data,
    output wire [23:0] O_debug
);
    localparam LEGACY=2'd0,SNAP_WRITE=2'd1,SNAP_READ=2'd2,DRAIN=2'd3;
    reg [1:0] state;
    reg [5:0] beats,cooldown;
    reg [10:0] reads_pending;
    reg read_owner_snapshot;
    wire legacy_active=I_vi_active|I_vo_active;
    wire want_snapshot=I_snap_wr_valid|I_snap_rd_valid;
    wire claim=(state==LEGACY)&&!legacy_active&&(cooldown==0)&&want_snapshot;
    // Pause prevents BOTH old clients from starting on the claim edge.
    // Active transactions ignore pause and are always allowed to finish.
    assign O_bus_pause=(state!=LEGACY)||claim;
    assign O_legacy_ready=(state==LEGACY)&&I_mc_ready;
    assign O_snap_wr_ready=(state==SNAP_WRITE)&&I_mc_ready;
    assign O_snap_rd_ready=(state==SNAP_READ)&&I_mc_ready;
    assign O_mc_wr_en=(state==LEGACY)?I_vi_wr_en:
                       (state==SNAP_WRITE)?(I_snap_wr_valid&&I_mc_ready):1'b0;
    assign O_mc_rd_en=(state==LEGACY)?I_vo_rd_en:
                       (state==SNAP_READ)?(I_snap_rd_valid&&I_mc_ready):1'b0;
    assign O_mc_addr=(state==SNAP_WRITE)?I_snap_wr_addr:
                     (state==SNAP_READ)?I_snap_rd_addr:
                     I_vi_wr_en?I_vi_addr:I_vo_addr;
    assign O_mc_wr_data=(state==SNAP_WRITE)?I_snap_wr_data:I_vi_data;
    assign O_video_rd_valid=I_mc_rd_valid&&!read_owner_snapshot;
    assign O_snap_rd_valid=I_mc_rd_valid&&read_owner_snapshot;
    // DDR-domain observation bus. The snapshot service samples this into a
    // held mailbox; no bit here is independently sampled by the NET clock.
    assign O_debug={1'b0,O_mc_rd_en,O_mc_wr_en,I_snap_wr_valid,
                    I_snap_rd_valid,O_snap_rd_ready,I_vo_active,I_vi_active,
                    I_mc_rd_valid,I_mc_ready,read_owner_snapshot,state,reads_pending};

    always @(posedge I_clk or negedge I_rst_n) begin
      if(!I_rst_n) begin
        state<=LEGACY;beats<=0;cooldown<=0;reads_pending<=0;read_owner_snapshot<=0;
      end else begin
        case({O_mc_rd_en,I_mc_rd_valid})
          2'b10: reads_pending<=reads_pending+1'b1;
          2'b01: if(reads_pending!=0) reads_pending<=reads_pending-1'b1;
          default: ;
        endcase
        if(cooldown!=0) cooldown<=cooldown-1'b1;
        case(state)
          LEGACY: begin
            beats<=0;
            // Writes do not change response ownership. Waiting for old
            // video reads here needlessly blocks all three clients and
            // can overflow the unthrottled camera capture FIFO.
            // Only a snapshot READ must wait for the previous read owner.
            if(claim && (I_snap_wr_valid || (reads_pending==0 && !I_mc_rd_valid))) begin
              if(I_snap_wr_valid) state<=SNAP_WRITE;
              else begin state<=SNAP_READ;read_owner_snapshot<=1;end
            end
          end
          SNAP_WRITE: begin
            if(!I_snap_wr_valid) begin state<=LEGACY;cooldown<=LEGACY_WINDOW;end
            else if(O_mc_wr_en) begin
              if(beats==SNAP_BURST-1) begin state<=LEGACY;cooldown<=LEGACY_WINDOW;end
              else beats<=beats+1'b1;
            end
          end
          SNAP_READ: begin
            if(!I_snap_rd_valid) state<=DRAIN;
            else if(O_mc_rd_en) begin
              if(beats==SNAP_BURST-1) state<=DRAIN;
              else beats<=beats+1'b1;
            end
          end
          DRAIN: if(reads_pending==0 && !I_mc_rd_valid) begin
            read_owner_snapshot<=0;state<=LEGACY;cooldown<=LEGACY_WINDOW;
          end
          default: state<=LEGACY;
        endcase
      end
    end
endmodule
