`timescale 1ns/1ps
// Minimal independent engine for the frozen coarse microcode ISA.
// All64 architectural words reside in an exclusive external synchronous16bit
// pool (128words). No asynchronous architectural register bank is inferred.
// Program531words +constant426words share one1024x32 synchronous ROM.
// Shifts are deliberately bit-serial; MUL16 is one registered16x16 DSP.
module pcb_microcode_engine_v1 #(
    parameter ROM_FILE="coarse_engine_rom.mem",
    parameter integer PROGRAM_WORDS=531,
    parameter integer CONSTANT_WORDS=426
) (
    input wire I_clk,I_rst_n,I_cancel,
    input wire I_host_write,
    input wire [5:0] I_host_index,
    input wire [31:0] I_host_data,
    output wire O_host_ready,
    output reg O_host_done,
    input wire I_start,
    input wire [15:0] I_entry,
    output wire O_busy,
    output reg O_done,O_valid,
    output reg [8:0] O_status,O_error,
    output wire O_emit_valid,
    input wire I_emit_ready,
    output wire [8:0] O_emit_tag,
    output wire [31:0] O_emit_d,O_emit_a,O_emit_b,
    output reg [6:0] O_ws_addr,
    output wire O_ws_we,
    output wire [15:0] O_ws_wdata,
    input wire [15:0] I_ws_rdata,
    output wire [15:0] O_pc,
    output wire [4:0] O_opcode
);
    localparam NOP=0,LDC=1,MOV=2,ADD=3,ADC=4,SUB=5,SBC=6,
      AND_=7,OR_=8,XOR_=9,SHL=10,SHR=11,SAR=12,CMP=13,LUT=14,
      JMP=15,BZ=16,BNZ=17,BC=18,BNC=19,CALL=20,RET=21,
      MUL16=22,EMIT=23,HALT=24,FAIL=25;
    localparam IDLE=0,FETCH_WAIT=1,FETCH_CAPTURE=2,DECODE=3,
      READ_WAIT=4,READ_CAPTURE=5,EXECUTE=6,CONST_WAIT=7,
      CONST_CAPTURE=8,WRITE_LOW=9,WRITE_HIGH=10,SHIFT=11,
      MULTIPLY_WAIT=12,EMIT_WAIT=13;
    reg [3:0] state;
    reg [15:0] pc,return_pc;
    reg return_valid,carry,zero,host_write;
    reg [31:0] instruction,operand_a,operand_b,result;
    reg [5:0] destination;
    reg [1:0] read_slot,read_count;
    reg read_high;
    reg [15:0] read_low;
    reg [4:0] shift_count;
    reg [9:0] rom_address;
    reg [31:0] rom_q;
    (* ram_style="bram" *) reg [31:0] rom[0:1023] /* synthesis syn_ramstyle="block_ram" */;
    initial $readmemh(ROM_FILE,rom);
    always @(posedge I_clk)rom_q<=rom[rom_address];
    wire [4:0] op=instruction[31:27];
    wire [5:0] rd=instruction[26:21],ra=instruction[20:15],rb=instruction[14:9];
    wire [8:0] immediate=instruction[8:0];
    wire [15:0] branch_target=instruction[15:0];
    wire subtract=(op==SUB||op==SBC||op==CMP);
    wire [31:0] alu_b=(op==LUT)?{23'd0,immediate}:operand_b;
    wire alu_carry=subtract?((op==SBC)?carry:1'b1):((op==ADC)?carry:1'b0);
    wire [32:0] alu_sum={1'b0,operand_a}+{1'b0,(subtract?~alu_b:alu_b)}+alu_carry;
    // Registering only the product leaves the DSP free of asynchronous resets.
    (* use_dsp="yes" *) wire [31:0] dsp_product=operand_a[15:0]*operand_b[15:0];
    reg [31:0] dsp_q;
    always @(posedge I_clk)dsp_q<=dsp_product;
    assign O_busy=state!=IDLE;
    assign O_host_ready=state==IDLE&&!I_start&&!I_cancel;
    assign O_emit_valid=state==EMIT_WAIT&&!I_cancel;
    assign O_emit_tag=immediate;
    assign O_emit_d=result;assign O_emit_a=operand_a;assign O_emit_b=operand_b;
    assign O_ws_we=(state==WRITE_LOW||state==WRITE_HIGH)&&!I_cancel;
    assign O_ws_wdata=(state==WRITE_HIGH)?result[31:16]:result[15:0];
    assign O_pc=pc;assign O_opcode=op;
    task fail;
        input [8:0] code;
        begin O_done<=1;O_valid<=0;O_error<=code;state<=IDLE;end
    endtask
    task fetch;
        input [15:0] target;
        begin
            if(target>=PROGRAM_WORDS)fail(9'h101);
            else begin pc<=target;rom_address<=target[9:0];state<=FETCH_WAIT;end
        end
    endtask
    task write_result;
        input [31:0] value;
        begin result<=value;zero<=value==0;O_ws_addr<={destination,1'b0};state<=WRITE_LOW;end
    endtask
    task begin_read;
        input [5:0] index;
        begin O_ws_addr<={index,1'b0};read_high<=0;state<=READ_WAIT;end
    endtask
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;pc<=0;return_pc<=0;return_valid<=0;carry<=0;zero<=0;host_write<=0;
            instruction<=0;operand_a<=0;operand_b<=0;result<=0;destination<=0;
            read_slot<=0;read_count<=0;read_high<=0;read_low<=0;shift_count<=0;rom_address<=0;
            O_host_done<=0;O_done<=0;O_valid<=0;O_status<=0;O_error<=0;O_ws_addr<=0;
        end else begin
            O_host_done<=0;O_done<=0;O_valid<=0;
            if(I_cancel&&state!=IDLE)begin return_valid<=0;fail(9'h104);end
            else if(I_start&&state!=IDLE)begin return_valid<=0;fail(9'h108);end
            else case(state)
                IDLE:begin
                    if(I_start&&!I_cancel)begin
                        O_status<=0;O_error<=0;return_valid<=0;host_write<=0;fetch(I_entry);
                    end else if(I_host_write&&O_host_ready)begin
                        result<=I_host_data;destination<=I_host_index;O_ws_addr<={I_host_index,1'b0};
                        host_write<=1;state<=WRITE_LOW;
                    end
                end
                FETCH_WAIT:state<=FETCH_CAPTURE;
                FETCH_CAPTURE:begin instruction<=rom_q;pc<=pc+1'b1;state<=DECODE;end
                DECODE:begin
                    destination<=rd;read_slot<=0;
                    case(op)
                        NOP:fetch(pc);
                        LDC:begin
                            if(immediate>=CONSTANT_WORDS)fail(9'h106);
                            else begin rom_address<=PROGRAM_WORDS+immediate;state<=CONST_WAIT;end
                        end
                        MOV,SHL,SHR,SAR,LUT:begin read_count<=1;begin_read(ra);end
                        ADD,ADC,SUB,SBC,AND_,OR_,XOR_,CMP,MUL16:begin read_count<=2;begin_read(ra);end
                        EMIT:begin read_count<=3;begin_read(rd);end
                        JMP:fetch(branch_target);
                        BZ:fetch(zero?branch_target:pc);
                        BNZ:fetch(!zero?branch_target:pc);
                        BC:fetch(carry?branch_target:pc);
                        BNC:fetch(!carry?branch_target:pc);
                        CALL:begin
                            if(return_valid)fail(9'h103);
                            else begin return_pc<=pc;return_valid<=1;fetch(branch_target);end
                        end
                        RET:begin
                            if(!return_valid)fail(9'h103);
                            else begin return_valid<=0;fetch(return_pc);end
                        end
                        HALT:begin O_status<=immediate;O_done<=1;O_valid<=1;state<=IDLE;end
                        FAIL:fail(immediate);
                        default:fail(9'h102);
                    endcase
                end
                READ_WAIT:state<=READ_CAPTURE;
                READ_CAPTURE:begin
                    if(!read_high)begin read_low<=I_ws_rdata;read_high<=1;O_ws_addr[0]<=1;state<=READ_WAIT;end
                    else begin
                        if(op==EMIT)case(read_slot)
                            0:result<={I_ws_rdata,read_low};
                            1:operand_a<={I_ws_rdata,read_low};
                            2:operand_b<={I_ws_rdata,read_low};
                        endcase
                        else if(read_slot==0)operand_a<={I_ws_rdata,read_low};
                        else operand_b<={I_ws_rdata,read_low};
                        if(read_slot+1'b1==read_count)state<=EXECUTE;
                        else begin
                            read_slot<=read_slot+1'b1;
                            begin_read((op==EMIT&&read_slot==0)?ra:rb);
                        end
                    end
                end
                EXECUTE:case(op)
                    MOV:write_result(operand_a);
                    ADD,ADC,SUB,SBC:begin carry<=alu_sum[32];write_result(alu_sum[31:0]);end
                    CMP:begin carry<=alu_sum[32];zero<=alu_sum[31:0]==0;fetch(pc);end
                    AND_:write_result(operand_a&operand_b);
                    OR_:write_result(operand_a|operand_b);
                    XOR_:write_result(operand_a^operand_b);
                    SHL,SHR,SAR:begin
                        if(immediate>=32)fail(9'h105);
                        else if(immediate==0)write_result(operand_a);
                        else begin shift_count<=immediate[4:0];state<=SHIFT;end
                    end
                    LUT:begin
                        if(alu_sum>=CONSTANT_WORDS)fail(9'h106);
                        else begin rom_address<=PROGRAM_WORDS+alu_sum[9:0];state<=CONST_WAIT;end
                    end
                    MUL16:state<=MULTIPLY_WAIT;
                    EMIT:state<=EMIT_WAIT;
                    default:fail(9'h102);
                endcase
                SHIFT:begin
                    if(op==SHL)operand_a<={operand_a[30:0],1'b0};
                    else operand_a<={(op==SAR)?operand_a[31]:1'b0,operand_a[31:1]};
                    if(shift_count==1)begin
                        if(op==SHL)write_result({operand_a[30:0],1'b0});
                        else write_result({(op==SAR)?operand_a[31]:1'b0,operand_a[31:1]});
                    end else shift_count<=shift_count-1'b1;
                end
                MULTIPLY_WAIT:write_result(dsp_q);
                CONST_WAIT:state<=CONST_CAPTURE;
                CONST_CAPTURE:write_result(rom_q);
                WRITE_LOW:begin O_ws_addr[0]<=1;state<=WRITE_HIGH;end
                WRITE_HIGH:begin
                    if(host_write)begin host_write<=0;O_host_done<=1;state<=IDLE;end
                    else fetch(pc);
                end
                EMIT_WAIT:if(I_emit_ready)fetch(pc);
                default:fail(9'h107);
            endcase
        end
    end
endmodule
