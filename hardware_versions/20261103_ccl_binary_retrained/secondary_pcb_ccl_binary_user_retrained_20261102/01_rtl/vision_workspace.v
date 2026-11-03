// Lifecycle-shared activation workspace for the ordinary RGB CNN and PCB
// TinyCNN.  The two jobs are mutually exclusive (purpose=0 ordinary,
// purpose=1 PCB), so the PCB-sized banks also hold all ordinary activations.
// Read data is registered without reset; this is intentional for PH1P ERAM
// inference and matches the synchronous-read contract of both cores.
module vision_workspace(
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
    // bank0: PCB f1, 18,432 x 16 bits.  Ordinary CNN occupies words 0..8191
    // while purpose=0. bank1: PCB packed input/f2, 6,912 x 16 bits.
    (* ram_style="bram" *) reg [15:0] bank0 [0:18431];
    (* ram_style="bram" *) reg [15:0] bank1 [0:6911];
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
    wire [14:0] bank0_waddr = pcb_mode ? pcb_waddr :
        cnn_shape_write ? {2'b0,shape_word} :
        cnn_f1_write ? {2'b0,f1_word} : {2'b0,f2_word};
    wire [15:0] bank0_wdata = pcb_mode ? pcb_wdata :
        cnn_shape_write ? cnn_shape_wdata :
        cnn_f1_write ? cnn_f1_wdata : cnn_f2_wdata;
    wire bank1_we = pcb_mode && pcb_we && pcb_wbank;
    wire [12:0] bank1_waddr = pcb_waddr[12:0];

    wire [14:0] cnn_rd_word = (cnn_rd_sel==2'd0) ? {2'b0,cnn_shape_rd_word} :
                                (cnn_rd_sel==2'd1) ? {2'b0,cnn_f1_rd_word} :
                                                     {2'b0,cnn_f2_rd_word};
    // During PCB Conv1, bank1 supplies the selected data. Holding the unused
    // bank0 port at address zero removes the tap/descriptor cone from its
    // ERAM chip-select path without changing the registered read latency.
    wire [14:0] bank0_raddr = pcb_mode ? (pcb_rd_bank ? 15'd0 : pcb_rd_addr) : cnn_rd_word;
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
