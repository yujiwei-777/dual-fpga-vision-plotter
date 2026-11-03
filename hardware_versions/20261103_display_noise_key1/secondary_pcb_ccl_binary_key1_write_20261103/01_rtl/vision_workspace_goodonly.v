// Purpose-owned synchronous RAM; ordinary RGB CNN byte layout is unchanged.
// bank0: ordinary words0..8191; binary C4 Conv1 signed16 words0..9215.
// bank1: packed ROI words0..4607, then binary C4 Conv2 words0..2303.
// No model contents live in activation RAM. No reset or initialization ports.
module vision_workspace_goodonly #(
    parameter BANK0_INIT_FILE="",
    parameter BANK1_INIT_FILE=""
) (
    input wire clk,
    input wire [1:0] purpose,
    input wire cnn_shape_we,
    input wire [11:0] cnn_shape_waddr,
    input wire [15:0] cnn_shape_wdata,
    input wire cnn_f1_we,
    input wire [12:0] cnn_f1_waddr,
    input wire [15:0] cnn_f1_wdata,
    input wire cnn_f2_we,
    input wire [11:0] cnn_f2_waddr,
    input wire [15:0] cnn_f2_wdata,
    input wire [1:0] cnn_rd_sel,
    input wire [12:0] cnn_rd_addr,
    output wire [7:0] cnn_rd_data,
    input wire pcb_we,
    input wire pcb_wbank,
    input wire [14:0] pcb_waddr,
    input wire [15:0] pcb_wdata,
    input wire pcb_rd_bank,
    input wire [14:0] pcb_rd_addr,
    output wire [15:0] pcb_rd_data
);
    (* ram_style="bram" *) reg [15:0] bank0 [0:9215];
    (* ram_style="bram" *) reg [15:0] bank1 [0:4607];
    wire pcb_mode = purpose==2'd1;
    wire [12:0] shape_word = {1'b0,cnn_shape_waddr[11:1]};
    wire [12:0] f1_word = 13'd2048 + {1'b0,cnn_f1_waddr[12:1]};
    wire [12:0] f2_word = 13'd6144 + {1'b0,cnn_f2_waddr[11:1]};
    wire [12:0] cnn_shape_rd_word = {1'b0,cnn_rd_addr[11:1]};
    wire [12:0] cnn_f1_rd_word = 13'd2048 + {1'b0,cnn_rd_addr[12:1]};
    wire [12:0] cnn_f2_rd_word = 13'd6144 + {1'b0,cnn_rd_addr[11:1]};

    // Keep exactly one write-address expression and one synchronous read
    // address per physical bank.  Conditional array indexing in the memory
    // assignments caused TD to infer several mutually-exclusive ports and
    // expand the activation RAMs into DRAM LUTs.
    wire cnn_shape_write = !pcb_mode && cnn_shape_we;
    wire cnn_f1_write = !pcb_mode && !cnn_shape_we && cnn_f1_we;
    wire cnn_f2_write = !pcb_mode && !cnn_shape_we && !cnn_f1_we && cnn_f2_we;
    wire bank0_we = pcb_mode ? (pcb_we && !pcb_wbank) :
                    (cnn_shape_write || cnn_f1_write || cnn_f2_write);
    wire [13:0] bank0_waddr = pcb_mode ? pcb_waddr[13:0] :
        cnn_shape_write ? {1'b0,shape_word} :
        cnn_f1_write ? {1'b0,f1_word} : {1'b0,f2_word};
    wire [15:0] bank0_wdata = pcb_mode ? pcb_wdata :
        cnn_shape_write ? cnn_shape_wdata :
        cnn_f1_write ? cnn_f1_wdata : cnn_f2_wdata;
    wire bank1_we = pcb_mode && pcb_we && pcb_wbank;
    wire [12:0] bank1_waddr = pcb_waddr[12:0];

    wire [12:0] cnn_rd_word = (cnn_rd_sel==2'd0) ? cnn_shape_rd_word :
                                (cnn_rd_sel==2'd1) ? cnn_f1_rd_word :
                                                     cnn_f2_rd_word;
    // During PCB Conv1, bank1 supplies the selected data. Holding the unused
    // bank0 port at address zero removes the tap/descriptor cone from its
    // ERAM chip-select path without changing the registered read latency.
    wire [13:0] bank0_raddr = pcb_mode ? (pcb_rd_bank ? 14'd0 : pcb_rd_addr[13:0]) : {1'b0,cnn_rd_word};
    wire [12:0] bank1_raddr = pcb_rd_addr[12:0];

    reg [15:0] bank0_q, bank1_q;
    reg cnn_rd_byte_q, pcb_rd_bank_q;

    always @(posedge clk) begin
        if(bank0_we) bank0[bank0_waddr] <= bank0_wdata;
        if(bank1_we) bank1[bank1_waddr] <= pcb_wdata;
        bank0_q <= bank0[bank0_raddr];
        bank1_q <= bank1[bank1_raddr];
        cnn_rd_byte_q <= cnn_rd_addr[0];
        pcb_rd_bank_q <= pcb_rd_bank;
    end

    assign cnn_rd_data = cnn_rd_byte_q ? bank0_q[15:8] : bank0_q[7:0];
    assign pcb_rd_data = pcb_rd_bank_q ? bank1_q : bank0_q;
endmodule
