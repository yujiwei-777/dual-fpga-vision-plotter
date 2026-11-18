// Shared signed arithmetic for the document-copy pipeline.
//
// The interface intentionally remains 128-bit on A/result because the
// homography and refinement blocks use Q20 numerators.  The datapath is
// serialized around 64-bit limbs: additions/subtractions consume low and
// high limbs on successive clocks, multiplication uses a 64-bit shift/add
// loop with a 128-bit product held as two limbs, and division uses a
// restoring 128/64 loop with a 64-bit remainder.  This avoids a wide
// inferred multiplier/divider and keeps the arithmetic deterministic.
//
// operation: 2'b00 multiply, 2'b01 divide, 2'b10 add, 2'b11 subtract.
// Multiply accepts a only when it is a sign-extended 64-bit value, matching
// the original module. Divide is signed, truncates toward zero, and reports
// divide-by-zero through error. Add/subtract retain modulo-2^128 behavior.
module doc_arithmetic(
 input wire clk,rst_n,start,input wire [1:0] operation,
 input wire signed [127:0] a,input wire signed [63:0] b,
 output reg busy,done,error,output reg signed [127:0] result
);
 localparam IDLE=4'd0,
            ADD_LO=4'd1,ADD_HI=4'd2,
            MUL_ACC_LO=4'd3,MUL_ACC_HI=4'd4,MUL_SHIFT=4'd5,
            DIVIDE=4'd6,FINISH=4'd7,
            NEG_LO=4'd8,NEG_HI=4'd9;

 reg [3:0] state;
 reg [7:0] count;
 reg negative,serial_div;
 reg arith_sub;

 // Add/subtract limbs. b is sign-extended to 128 bits at launch.
 reg [63:0] arith_a_lo,arith_a_hi,arith_b_lo,arith_b_hi;
 reg [63:0] arith_lo;
 reg arith_carry;
 wire [64:0] add_lo_ext={1'b0,arith_a_lo}+{1'b0,arith_b_lo};
 wire [64:0] add_hi_ext={1'b0,arith_a_hi}+{1'b0,arith_b_hi}+arith_carry;
 wire [64:0] sub_lo_ext={1'b0,arith_a_lo}-{1'b0,arith_b_lo};
 wire [64:0] sub_hi_ext={1'b0,arith_a_hi}-{1'b0,arith_b_hi}-arith_carry;

 // 64-bit serial multiply with a two-limb product and multiplicand.
 reg [63:0] mul_mcand_lo,mul_mcand_hi,mul_multiplier;
 reg [63:0] mul_acc_lo,mul_acc_hi;
 reg mul_carry;
 wire [64:0] mul_lo_ext={1'b0,mul_acc_lo}+{1'b0,mul_mcand_lo};
 wire [64:0] mul_hi_ext={1'b0,mul_acc_hi}+{1'b0,mul_mcand_hi}+mul_carry;

 // Restoring divide: quotient is held as two 64-bit limbs. A shifted
 // remainder never needs a 65-bit adder; the old top bit is handled by the
 // compare and the low 64-bit subtract below.
 reg [63:0] div_q_hi,div_q_lo,div_divisor,div_remainder;
 wire [63:0] div_shifted={div_remainder[62:0],div_q_hi[63]};
 wire div_take=(div_remainder[63] || (div_shifted>=div_divisor));
 wire [63:0] div_remainder_next=div_take ? (div_shifted-div_divisor) : div_shifted;

 // Full-width absolute value is formed from 64-bit limbs. The explicit
 // carry condition is important for negative values whose low limb is zero.
 wire [63:0] a_neg_lo=~a[63:0]+64'd1;
 wire [63:0] a_neg_hi=~a[127:64]+((a[63:0]==64'd0)?64'd1:64'd0);
 wire [63:0] a_mag_lo=a[127]?a_neg_lo:a[63:0];
 wire [63:0] a_mag_hi=a[127]?a_neg_hi:a[127:64];
 wire [63:0] b_mag=b[63]?(~b+64'd1):b;
 wire [63:0] b_ext_hi=b[63]?64'hffffffffffffffff:64'd0;

 // Negation of the final 128-bit magnitude is split into limbs.
 reg [63:0] neg_src_lo,neg_src_hi,neg_lo;
 reg neg_carry;

 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;count<=0;negative<=0;serial_div<=0;arith_sub<=0;
   arith_a_lo<=0;arith_a_hi<=0;arith_b_lo<=0;arith_b_hi<=0;arith_lo<=0;arith_carry<=0;
   mul_mcand_lo<=0;mul_mcand_hi<=0;mul_multiplier<=0;mul_acc_lo<=0;mul_acc_hi<=0;mul_carry<=0;
   div_q_hi<=0;div_q_lo<=0;div_divisor<=0;div_remainder<=0;
   neg_src_lo<=0;neg_src_hi<=0;neg_lo<=0;neg_carry<=0;
   busy<=0;done<=0;error<=0;result<=0;
  end else begin
   done<=0;
   case(state)
    IDLE: begin
     busy<=0;
     if(start) begin
      error<=0;count<=0;negative<=a[127]^b[63];serial_div<=operation==2'd1;
      if(operation==2'd2 || operation==2'd3) begin
       // Preserve the old modulo-2^128 add/subtract result, but perform the
       // two limbs on separate clocks to keep the arithmetic width at 64.
       arith_sub<=operation==2'd3;
       arith_a_lo<=a[63:0];arith_a_hi<=a[127:64];
       arith_b_lo<=b;arith_b_hi<=b_ext_hi;arith_carry<=0;busy<=1;state<=ADD_LO;
      end else if(operation==2'd1 && b==0) begin
       error<=1;result<=0;done<=1;state<=IDLE;
      end else if(operation==2'd0 && a[127:64]!={64{a[63]}}) begin
       // Multiplication is deliberately limited to signed 64x64, as in the
       // previous implementation. This catches accidental wide operands.
       error<=1;result<=0;done<=1;state<=IDLE;
      end else if(operation==2'd0) begin
       mul_mcand_lo<=a_mag_lo;mul_mcand_hi<=0;mul_multiplier<=b_mag;
       mul_acc_lo<=0;mul_acc_hi<=0;mul_carry<=0;busy<=1;state<=MUL_ACC_LO;
      end else begin
       // Signed restoring division. Keep the complete 128-bit dividend and
       // emit a 128-bit quotient so MIN_INT and Q20 numerators are preserved.
       div_q_hi<=a_mag_hi;div_q_lo<=a_mag_lo;div_divisor<=b_mag;
       div_remainder<=0;busy<=1;state<=DIVIDE;
      end
     end
    end

    ADD_LO: begin
     if(arith_sub) begin
      arith_lo<=sub_lo_ext[63:0];arith_carry<=sub_lo_ext[64];
     end else begin
      arith_lo<=add_lo_ext[63:0];arith_carry<=add_lo_ext[64];
     end
     state<=ADD_HI;
    end

    ADD_HI: begin
     if(arith_sub) begin
      result<={sub_hi_ext[63:0],arith_lo};
     end else begin
      result<={add_hi_ext[63:0],arith_lo};
     end
     busy<=0;done<=1;state<=IDLE;
    end

    MUL_ACC_LO: begin
     if(mul_multiplier[0]) begin
      mul_acc_lo<=mul_lo_ext[63:0];mul_carry<=mul_lo_ext[64];state<=MUL_ACC_HI;
     end else begin
      mul_carry<=0;state<=MUL_SHIFT;
     end
    end

    MUL_ACC_HI: begin
     mul_acc_hi<=mul_hi_ext[63:0];
     // A 64x64 product fits in exactly 128 bits; any carry beyond bit 127
     // is outside the result and is intentionally discarded.
     state<=MUL_SHIFT;
    end

    MUL_SHIFT: begin
     mul_mcand_hi<=(mul_mcand_hi<<1)|mul_mcand_lo[63];
     mul_mcand_lo<=mul_mcand_lo<<1;
     mul_multiplier<=mul_multiplier>>1;
     if(count==8'd63) begin count<=0;state<=FINISH;end
     else begin count<=count+1'b1;state<=MUL_ACC_LO;end
    end

    DIVIDE: begin
     div_remainder<=div_remainder_next;
     div_q_hi<={div_q_hi[62:0],div_q_lo[63]};
     div_q_lo<={div_q_lo[62:0],div_take};
     if(count==8'd127) begin count<=0;state<=FINISH;end
     else begin count<=count+1'b1;end
    end

    FINISH: begin
     if(serial_div || negative) begin
      // Only multiply/divide reach FINISH. For a negative result, negate the
      // 128-bit magnitude over two 64-bit cycles; positive results complete
      // directly. serial_div selects the division quotient versus product.
      if(negative) begin
       if(serial_div) begin neg_src_lo<=div_q_lo;neg_src_hi<=div_q_hi;end
       else begin neg_src_lo<=mul_acc_lo;neg_src_hi<=mul_acc_hi;end
       state<=NEG_LO;
      end else begin
       if(serial_div) result<={div_q_hi,div_q_lo};
       else result<={mul_acc_hi,mul_acc_lo};
       busy<=0;done<=1;state<=IDLE;
      end
     end else begin
      result<={mul_acc_hi,mul_acc_lo};busy<=0;done<=1;state<=IDLE;
     end
    end

    NEG_LO: begin
     neg_lo<=~neg_src_lo+64'd1;neg_carry<=(neg_src_lo==64'd0);state<=NEG_HI;
    end

    NEG_HI: begin
     result<={~neg_src_hi+neg_carry,neg_lo};
     busy<=0;done<=1;state<=IDLE;
    end

    default: begin state<=IDLE;busy<=0;end
   endcase
  end
 end
endmodule
