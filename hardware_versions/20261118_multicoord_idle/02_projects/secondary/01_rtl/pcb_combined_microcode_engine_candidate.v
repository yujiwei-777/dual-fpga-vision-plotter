// Reports-only combined engine. Unqualified until the frozen RTL suite passes.
// Independent IO28 outline experiment. One additional acceptance bit,
// no additional arithmetic/operand/result bank and no extra state.
// INDEPENDENT CANDIDATE, not a production replacement.
// One physical32-bit ALU and one registered16x16 DSP serve ISA and NCC.
// Adds fixed opcode26, a second RF read port, and NCC_WAIT=14 only.
// A private synchronous TDP RF is required; do not alias live image memory.
`timescale 1ns/1ps
// Minimal independent engine for the frozen coarse microcode ISA.
// All64 architectural words reside in an exclusive external synchronous16bit
// pool (128words). No asynchronous architectural register bank is inferred.
// Program531words +constant426words share one1024x32 synchronous ROM.
// Shifts are deliberately bit-serial; MUL16 is one registered16x16 DSP.
module pcb_combined_microcode_engine_candidate #(
    parameter ROM_FILE="coarse_engine_rom.mem",
    parameter integer ROM_BITS=11,
    parameter integer PROGRAM_WORDS=1242,
    parameter integer CONSTANT_WORDS=486,
    parameter integer ENABLE_NCC=0,
    parameter integer PIXEL_TIMEOUT=4096
) (
    input wire I_clk,I_rst_n,I_cancel,
    // Owner6 borrows the existing ALU and result register only while ISA idle.
    input wire I_context_grant,I_context_r_we,
    input wire [31:0] I_context_r_data,I_context_alu_a,I_context_alu_b,
    input wire I_context_alu_carry,
    output wire [31:0] O_context_r,
    output wire [32:0] O_context_alu_sum,
    output wire O_context_available,
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
    // Blocking IO28: accepted once; operands stay in the existing A/B banks.
    // A response may coincide with acceptance. An endpoint must discard/drain
    // its canceled transaction before accepting a later request.
    output wire O_io_valid,
    input wire I_io_ready,
    output wire [8:0] O_io_command,
    output wire [31:0] O_io_a,O_io_b,
    input wire I_io_response_valid,
    output wire O_io_response_ready,
    input wire [31:0] I_io_return_data,
    output wire O_io_abort,
    // Opcode27 holds the same engine owner through pixel drain/LOCKED.
    output wire O_pixel_request,
    output wire [10:0] O_pixel_x,
    output wire [9:0] O_pixel_y,
    input wire I_pixel_ready,I_pixel_valid,
    input wire [7:0] I_pixel_y8,
    output wire O_warp_busy,O_warp_done,O_warp_valid,
    output wire [3:0] O_warp_error,
    output wire [7:0] O_warp_gray,
    output wire O_warp_complete,
    output wire [3:0] O_warp_taps,
    output wire [6:0] O_ws_addr,
    output wire [6:0] O_ws_baddr,
    input wire [15:0] I_ws_brdata,
    output wire O_ws_we,
    output wire [15:0] O_ws_wdata,
    input wire [15:0] I_ws_rdata,
    output wire [15:0] O_pc,
    output wire [4:0] O_opcode
);
    localparam NOP=0,LDC=1,MOV=2,ADD=3,ADC=4,SUB=5,SBC=6,
      AND_=7,OR_=8,XOR_=9,SHL=10,SHR=11,SAR=12,CMP=13,LUT=14,
      JMP=15,BZ=16,BNZ=17,BC=18,BNC=19,CALL=20,RET=21,
      MUL16=22,EMIT=23,HALT=24,FAIL=25,NCC=26,WARP=27,IO=28;
    localparam IDLE=0,FETCH_WAIT=1,FETCH_CAPTURE=2,DECODE=3,
      READ_WAIT=4,READ_CAPTURE=5,EXECUTE=6,CONST_WAIT=7,
      CONST_CAPTURE=8,WRITE_LOW=9,WRITE_HIGH=10,SHIFT=11,
      MULTIPLY_WAIT=12,EMIT_WAIT=13,NCC_WAIT=14,WARP_WAIT=15;
    reg [3:0] state;
    reg [15:0] pc,return_pc;
    reg return_valid,carry,zero,host_write,io_accepted;
    reg [31:0] instruction,operand_a,operand_b,result;
    reg [5:0] destination;
    reg [1:0] read_slot,read_count;
    reg read_high;
    reg [15:0] read_low;
    reg [4:0] shift_count;
    reg [ROM_BITS-1:0] rom_address;
    reg [6:0] ws_addr;
    reg [31:0] rom_q;
    (* ram_style="bram" *) reg [31:0] rom[0:(1<<ROM_BITS)-1] /* synthesis syn_ramstyle="block_ram" */;
    initial $readmemh(ROM_FILE,rom);
    wire warp_active=state==WARP_WAIT;
    wire [8:0] warp_norm_addr;
    wire [ROM_BITS-1:0] actual_rom_address=warp_active?
        PROGRAM_WORDS+CONSTANT_WORDS+warp_norm_addr:rom_address;
    always @(posedge I_clk)rom_q<=rom[actual_rom_address];
    wire [4:0] op=instruction[31:27];
    wire [5:0] rd=instruction[26:21],ra=instruction[20:15],rb=instruction[14:9];
    wire [8:0] immediate=instruction[8:0];
    wire [15:0] branch_target=instruction[15:0];
    wire subtract=(op==SUB||op==SBC||op==CMP);
    wire [31:0] alu_b=(op==LUT)?{23'd0,immediate}:operand_b;
    wire alu_carry=subtract?((op==SBC)?carry:1'b1):((op==ADC)?carry:1'b0);
    wire abort_operation=I_cancel||(I_start&&state!=IDLE);
    wire io_waiting=state==EMIT_WAIT&&op==IO;
    wire warp_begin=state==DECODE&&op==WARP&&!abort_operation;
    wire warp_done,warp_busy,warp_valid;
    wire [3:0] warp_error;
    wire [6:0] warp_a_addr,warp_b_addr;
    wire warp_we;
    wire [15:0] warp_wdata,warp_aux_data;
    wire warp_aw,warp_bw,warp_rw,warp_xw,warp_cw,warp_carry_data;
    wire [31:0] warp_a_data,warp_b_data,warp_r_data,warp_alu_a,warp_alu_b;
    wire warp_alu_carry;
    wire ncc_active=state==NCC_WAIT;
    wire ncc_begin=ENABLE_NCC&&state==DECODE&&op==NCC&&!abort_operation;
    wire ncc_done,ncc_busy;
    wire [3:0] ncc_fault;
    wire [6:0] ncc_a_addr,ncc_b_addr;
    wire ncc_we;
    wire [15:0] ncc_wdata,ncc_aux_data;
    wire ncc_aw,ncc_bw,ncc_rw,ncc_xw,ncc_cw,ncc_carry_data;
    wire [31:0] ncc_a_data,ncc_b_data,ncc_r_data,ncc_alu_a,ncc_alu_b;
    wire ncc_alu_carry;
    wire [31:0] shared_alu_a=I_context_grant?I_context_alu_a:warp_active?warp_alu_a:ncc_active?ncc_alu_a:operand_a;
    wire [31:0] shared_alu_b=I_context_grant?I_context_alu_b:warp_active?warp_alu_b:ncc_active?ncc_alu_b:(subtract?~alu_b:alu_b);
    wire shared_alu_carry=I_context_grant?I_context_alu_carry:warp_active?warp_alu_carry:ncc_active?ncc_alu_carry:alu_carry;
    wire [32:0] alu_sum={1'b0,shared_alu_a}+{1'b0,shared_alu_b}+shared_alu_carry;
    // Registering only the product leaves the DSP free of asynchronous resets.
    (* use_dsp="yes" *) wire [31:0] dsp_product=operand_a[15:0]*operand_b[15:0];
    reg [31:0] dsp_q;
    always @(posedge I_clk)dsp_q<=dsp_product;
    assign O_busy=state!=IDLE||warp_busy;
    assign O_context_available=state==IDLE&&!warp_busy&&!ncc_busy;
    assign O_context_r=result;
    assign O_context_alu_sum=alu_sum;
    assign O_host_ready=state==IDLE&&!warp_busy&&!I_start&&!I_cancel&&!I_context_grant;
    assign O_emit_valid=state==EMIT_WAIT&&op==EMIT&&!abort_operation;
    assign O_io_valid=io_waiting&&!io_accepted&&!abort_operation;
    assign O_io_command=immediate;
    assign O_io_a=operand_a;assign O_io_b=operand_b;
    assign O_io_response_ready=io_waiting&&!abort_operation&&
        (io_accepted||(O_io_valid&&I_io_ready));
    assign O_io_abort=abort_operation;
    assign O_emit_tag=immediate;
    assign O_emit_d=result;assign O_emit_a=operand_a;assign O_emit_b=operand_b;
    assign O_ws_we=(warp_active?warp_we:ncc_active?ncc_we:(state==WRITE_LOW||state==WRITE_HIGH))&&!abort_operation;
    assign O_ws_addr=warp_active?warp_a_addr:ncc_active?ncc_a_addr:ws_addr;
    assign O_ws_baddr=warp_active?warp_b_addr:ncc_active?ncc_b_addr:7'd0;
    assign O_ws_wdata=warp_active?warp_wdata:ncc_active?ncc_wdata:(state==WRITE_HIGH)?result[31:16]:result[15:0];
    assign O_pc=pc;assign O_opcode=op;
    generate if(ENABLE_NCC)begin:g_ncc
    pcb_ncc_fast_uop_candidate ncc(
        .clk(I_clk),.rst_n(I_rst_n),.start(ncc_begin),
        .cancel(I_cancel||(I_start&&state!=IDLE)),.busy(ncc_busy),.done(ncc_done),.fault(ncc_fault),
        .rf_a_addr(ncc_a_addr),.rf_b_addr(ncc_b_addr),.rf_we(ncc_we),.rf_wdata(ncc_wdata),
        .rf_a_data(I_ws_rdata),.rf_b_data(I_ws_brdata),
        .a(operand_a),.b(operand_b),.r(result),.product(dsp_q),.aux(read_low),.carry(carry),.alu_sum(alu_sum),
        .a_we(ncc_aw),.b_we(ncc_bw),.r_we(ncc_rw),.aux_we(ncc_xw),.carry_we(ncc_cw),
        .a_data(ncc_a_data),.b_data(ncc_b_data),.r_data(ncc_r_data),.aux_data(ncc_aux_data),
        .carry_data(ncc_carry_data),.alu_a(ncc_alu_a),.alu_b(ncc_alu_b),.alu_carry(ncc_alu_carry));
    end else begin:g_no_ncc
        assign ncc_busy=0;assign ncc_done=0;assign ncc_fault=0;
        assign ncc_a_addr=0;assign ncc_b_addr=0;assign ncc_we=0;
        assign ncc_wdata=0;assign ncc_aux_data=0;
        assign ncc_aw=0;assign ncc_bw=0;assign ncc_rw=0;assign ncc_xw=0;assign ncc_cw=0;
        assign ncc_carry_data=0;assign ncc_a_data=0;assign ncc_b_data=0;assign ncc_r_data=0;
        assign ncc_alu_a=0;assign ncc_alu_b=0;assign ncc_alu_carry=0;
    end endgenerate
    assign O_warp_busy=warp_busy;
    assign O_warp_done=warp_done;assign O_warp_valid=warp_valid;
    assign O_warp_error=warp_error;
    pcb_affine6_rf_uop_candidate #(.WAIT_TIMEOUT(PIXEL_TIMEOUT)) warp(
        // Keep busy-start distinct from cancel. Never restart an idle uop
        // while the engine is still collecting its previous completion.
        .clk(I_clk),.rst_n(I_rst_n),
        .start(warp_begin||(I_start&&warp_active&&warp_busy)),.cancel(I_cancel),
        .busy(warp_busy),.done(warp_done),.valid(warp_valid),.error(warp_error),
        .O_gray(O_warp_gray),.O_sample_complete(O_warp_complete),.O_tap_inside(O_warp_taps),
        .O_pixel_request(O_pixel_request),.O_pixel_x(O_pixel_x),.O_pixel_y(O_pixel_y),
        .I_pixel_ready(I_pixel_ready),.I_pixel_valid(I_pixel_valid),.I_pixel_y8(I_pixel_y8),
        .norm_addr(warp_norm_addr),.norm_q(rom_q),
        .rf_a_addr(warp_a_addr),.rf_b_addr(warp_b_addr),.rf_we(warp_we),.rf_wdata(warp_wdata),
        .rf_a_data(I_ws_rdata),.rf_b_data(I_ws_brdata),
        .a(operand_a),.b(operand_b),.r(result),.product(dsp_q),.aux(read_low),.carry(carry),.alu_sum(alu_sum),
        .a_we(warp_aw),.b_we(warp_bw),.r_we(warp_rw),.aux_we(warp_xw),.carry_we(warp_cw),
        .a_data(warp_a_data),.b_data(warp_b_data),.r_data(warp_r_data),.aux_data(warp_aux_data),
        .carry_data(warp_carry_data),.alu_a(warp_alu_a),.alu_b(warp_alu_b),.alu_carry(warp_alu_carry));
    task fail;
        input [8:0] code;
        begin O_done<=1;O_valid<=0;O_error<=code;io_accepted<=0;state<=IDLE;end
    endtask
    task fetch;
        input [15:0] target;
        begin
            if(target>=PROGRAM_WORDS)fail(9'h101);
            else begin pc<=target;rom_address<=target[ROM_BITS-1:0];state<=FETCH_WAIT;end
        end
    endtask
    task write_result;
        input [31:0] value;
        begin result<=value;zero<=value==0;ws_addr<={destination,1'b0};state<=WRITE_LOW;end
    endtask
    task begin_read;
        input [5:0] index;
        begin ws_addr<={index,1'b0};read_high<=0;state<=READ_WAIT;end
    endtask
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;pc<=0;return_pc<=0;return_valid<=0;carry<=0;zero<=0;host_write<=0;io_accepted<=0;
            instruction<=0;operand_a<=0;operand_b<=0;result<=0;destination<=0;
            read_slot<=0;read_count<=0;read_high<=0;read_low<=0;shift_count<=0;rom_address<=0;
            O_host_done<=0;O_done<=0;O_valid<=0;O_status<=0;O_error<=0;ws_addr<=0;
        end else begin
            O_host_done<=0;O_done<=0;O_valid<=0;
            if(I_context_grant&&state==IDLE&&!warp_busy&&!ncc_busy)begin
                if(I_context_r_we&&!I_cancel)result<=I_context_r_data;
            end else if(warp_active)begin
                // Do not turn an accepted pixel read into an idle owner on
                // cancel. The uop remains active until drain or reset.
                if(warp_aw&&!abort_operation)operand_a<=warp_a_data;
                if(warp_bw&&!abort_operation)operand_b<=warp_b_data;
                if(warp_rw&&!abort_operation)result<=warp_r_data;
                if(warp_xw&&!abort_operation)read_low<=warp_aux_data;
                if(warp_cw&&!abort_operation)carry<=warp_carry_data;
                if(warp_done)begin
                    if(warp_busy)begin
                        O_done<=1;O_valid<=0;O_error<=9'h120|{5'd0,warp_error};
                    end else if(abort_operation||warp_error==4||warp_error==6)begin
                        return_valid<=0;fail((I_cancel||warp_error==4)?9'h104:9'h108);
                    end else if(warp_error!=0||!warp_valid)fail(9'h120|{5'd0,warp_error});
                    else fetch(pc);
                end
            end else if(I_cancel&&state!=IDLE)begin return_valid<=0;fail(9'h104);end
            else if(I_start&&state!=IDLE)begin return_valid<=0;fail(9'h108);end
            else if(ncc_active)begin
                if(ncc_aw)operand_a<=ncc_a_data;
                if(ncc_bw)operand_b<=ncc_b_data;
                if(ncc_rw)result<=ncc_r_data;
                if(ncc_xw)read_low<=ncc_aux_data;
                if(ncc_cw)carry<=ncc_carry_data;
                if(ncc_done)begin
                    if(ncc_fault!=0)fail(9'h110);
                    else fetch(pc);
                end
            end else case(state)
                IDLE:begin
                    if(I_start&&!I_cancel)begin
                        O_status<=0;O_error<=0;return_valid<=0;host_write<=0;io_accepted<=0;fetch(I_entry);
                    end else if(I_host_write&&O_host_ready)begin
                        result<=I_host_data;destination<=I_host_index;ws_addr<={I_host_index,1'b0};
                        host_write<=1;state<=WRITE_LOW;
                    end
                end
                FETCH_WAIT:state<=FETCH_CAPTURE;
                FETCH_CAPTURE:begin instruction<=rom_q;pc<=pc+1'b1;state<=DECODE;end
                DECODE:begin
                    destination<=rd;read_slot<=0;
                    case(op)
                        NOP:fetch(pc);
                        NCC:if(ENABLE_NCC)state<=NCC_WAIT;else fail(9'h102);
                        WARP:state<=WARP_WAIT;
                        LDC:begin
                            if(immediate>=CONSTANT_WORDS)fail(9'h106);
                            else begin rom_address<=PROGRAM_WORDS+immediate;state<=CONST_WAIT;end
                        end
                        MOV,SHL,SHR,SAR,LUT:begin read_count<=1;begin_read(ra);end
                        ADD,ADC,SUB,SBC,AND_,OR_,XOR_,CMP,MUL16,IO:begin read_count<=2;begin_read(ra);end
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
                    if(!read_high)begin read_low<=I_ws_rdata;read_high<=1;ws_addr[0]<=1;state<=READ_WAIT;end
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
                        else begin rom_address<=PROGRAM_WORDS+alu_sum[ROM_BITS-1:0];state<=CONST_WAIT;end
                    end
                    MUL16:state<=MULTIPLY_WAIT;
                    EMIT,IO:begin io_accepted<=0;state<=EMIT_WAIT;end
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
                WRITE_LOW:begin ws_addr[0]<=1;state<=WRITE_HIGH;end
                WRITE_HIGH:begin
                    if(host_write)begin host_write<=0;O_host_done<=1;state<=IDLE;end
                    else fetch(pc);
                end
                EMIT_WAIT:if(op==IO)begin
                    if(O_io_response_ready&&I_io_response_valid)begin
                        io_accepted<=0;write_result(I_io_return_data);
                    end else if(O_io_valid&&I_io_ready)io_accepted<=1;
                end else if(I_emit_ready)fetch(pc);
                default:fail(9'h107);
            endcase
        end
    end
endmodule
