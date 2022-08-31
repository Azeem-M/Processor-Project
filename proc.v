// Processor Project - Completed on March 28, 2022 //

module proc(DIN, Resetn, Clock, Run, DOUT, ADDR, W);
// These are the main inputs and outputs for this processor module
    input [15:0] DIN;
    input Resetn, Clock, Run;
    output wire [15:0] DOUT;
    output wire [15:0] ADDR;
    output wire W;



// These are internal wires/inputs/outputs within the processor
    wire [0:7] R_in; // r0, ..., r7 register enables
    reg rX_in, IR_in, ADDR_in, Done, DOUT_in, A_in, G_in, AddSub, ALU_and;
    reg [2:0] Tstep_Q, Tstep_D;
    reg [15:0] BusWires;
    reg [3:0] Select; // BusWires selector
    reg [16:0] Sum; // one bit bigger to detect a carry 
    wire [2:0] III, rX, rY; // instruction opcode and register operands
    wire [15:0] r0, r1, r2, r3, r4, r5, r6, pc, A;
    wire [15:0] G;
    wire [15:0] IR;
    reg pc_incr;    // used to increment the pc
    reg pc_in;      // used to load the pc
    reg W_D;        // used for write signal
    wire Imm;


// dealing with the flags

   reg F_in; //enable
   wire [2:0] CNZ_flag_in; // flags in here (connected to sum)
   assign CNZ_flag_in[0] = (Sum == 16'b0); // for z
   assign CNZ_flag_in[1] = Sum[15];  // for n
   assign CNZ_flag_in[2] = Sum[16]; // for c

   wire [2:0] CNZ_flag_out; // 3 bits flags out of here
   wire c;
   wire n;
   wire z;

   assign c = CNZ_flag_out[2];
   assign n = CNZ_flag_out[1];
   assign z = CNZ_flag_out[0];

flag_holder_register Fholder(CNZ_flag_in, Resetn, Clock, F_in, CNZ_flag_out);

module flag_holder_register (D, Resetn, Clock, Enable, Q);
	input [2:0] D;
	input Resetn, Clock, Enable;
	output [2:0] Q;
	reg [2:0] Q;	
	
	always @(posedge Clock)
		if (!Resetn)
			Q <= 3'b0;
		else if(Enable)
			Q <= D;
endmodule


   
// Assigning a few specific bits of IR to make it easier to identify/use them
    assign III = IR[15:13];
    assign Imm = IR[12];
    assign rX = IR[11:9];
    assign rY = IR[2:0];

// Decoder for the register enable signals (when a register enable is 1, we can write a value into that specific register)
    dec3to8 decX (rX_in, rX, R_in); // produce r0 - r7 register enables

/*********************************************************************************************************************/

// States for FSM
    parameter T0 = 3'b000, T1 = 3'b001, T2 = 3'b010, T3 = 3'b011, T4 = 3'b100, T5 = 3'b101;

    // Control FSM state table (based on the state diagram)
    // This is used to control which state the FSM is currently in.
    // Based on the conditions, the state will change (6 states total)
    always @(Tstep_Q, Run, Done)
        case (Tstep_Q)
            T0: // instruction fetch
                if (~Run) Tstep_D = T0;
                else Tstep_D = T1;
            T1: // wait cycle for synchronous memory
                Tstep_D = T2;
            T2: // this time step stores the instruction word in IR
                Tstep_D = T3;
            T3: if (Done) Tstep_D = T0;
                else Tstep_D = T4;
            T4: if (Done) Tstep_D = T0;
                else Tstep_D = T5;
            T5: // instructions end after this time step
                Tstep_D = T0;
            default: Tstep_D = 3'bxxx;
        endcase

/*********************************************************************************************************************/

    /* OPCODE format: III M XXX DDDDDDDDD, where 
    *     III = instruction, M = Immediate, XXX = rX. If M = 0, DDDDDDDDD = 000000YYY = rY
    *     If M = 1, DDDDDDDDD = #D is the immediate operand 
    *
    *  III M  Instruction   Description
    *  --- -  -----------   -----------
    *  000 0: mv   rX,rY    rX <- rY
    *  000 1: mv   rX,#D    rX <- D (sign extended)
    *  001 1: mvt  rX,#D    rX <- D << 8
    *  010 0: add  rX,rY    rX <- rX + rY
    *  010 1: add  rX,#D    rX <- rX + D
    *  011 0: sub  rX,rY    rX <- rX - rY
    *  011 1: sub  rX,#D    rX <- rX - D
    *  100 0: ld   rX,[rY]  rX <- [rY]
    *  101 0: st   rX,[rY]  [rY] <- rX
    *  110 0: and  rX,rY    rX <- rX & rY
    *  110 1: and  rX,#D    rX <- rX & D */

/*********************************************************************************************************************/

    // instructions
    parameter mv = 3'b000, mvt = 3'b001, add = 3'b010, sub = 3'b011, ld = 3'b100, st = 3'b101,
	     and_ = 3'b110, b_ = 3'b001;

    // selectors for the BusWires multiplexer
    parameter R0_SELECT = 4'b0000, R1_SELECT = 4'b0001, R2_SELECT = 4'b0010, 
        R3_SELECT = 4'b0011, R4_SELECT = 4'b0100, R5_SELECT = 4'b0101, R6_SELECT = 4'b0110, 
        PC_SELECT = 4'b0111, G_SELECT = 4'b1000, 
        SGN_IR8_0_SELECT /* signed-extended immediate data */ = 4'b1001, 
        IR7_0_0_0_SELECT /* immediate data << 8 */ = 4'b1010,
        DIN_SELECT /* data-in from memory */ = 4'b1011;

/*********************************************************************************************************************/

    // Control FSM outputs
    always @(*) begin
        // default values for control signals
        rX_in = 1'b0; A_in = 1'b0; G_in = 1'b0; IR_in = 1'b0; DOUT_in = 1'b0; ADDR_in = 1'b0; 
        Select = 4'bxxxx; AddSub = 1'b0; ALU_and = 1'b0; W_D = 1'b0; Done = 1'b0;
        pc_in = R_in[7] /* default pc enable */; pc_incr = 1'b0;

        case (Tstep_Q)
            T0: begin // fetch the instruction
                Select = PC_SELECT;  // put pc onto the internal bus
                ADDR_in = 1'b1;
                pc_incr = Run; // to increment pc
            end


            T1: // wait cycle for synchronous memory
		;


            T2: // store instruction on DIN in IR 
                IR_in = 1'b1;	


            T3: // define signals in T3 (old T1)
                case (III)
                   mv: begin
                        // mov operation will work by setting the Select signal based on the
			// operand we wish to move. This operand can either be a register
			// or immediate data (based on Imm)
			if(!Imm)  // not immediate data
				Select = rY;
			else // yes immediate data
				Select = SGN_IR8_0_SELECT; // sign extend to the 16 bits
			
			rX_in = 1'b1; // decoder enable correct register
			Done = 1'b1; // done, go back to T0
                    end

                    mvt: if(Imm) begin
                       	    // mov top operation only works with immediate data (9 bits shifted to msb of 16 bits total)
			    Select = IR7_0_0_0_SELECT; // Select signal for immediate data
			    rX_in = 1'b1; // decoder enable correct register
			    Done = 1'b1; // done, go back to T0
                    end
					

                    add, sub, and_: begin
                        // in state T3, the add/sub operation simply sets Select to rX
			// to put the contents into register A for future use (future clock cycles)
			Select = rX;
			A_in = 1'b1; // enable for A register (to store value for future addition)
			//not done, since we need more clock cycles for add/sub (go to next states)
                    end

                    ld, st: begin
                        Select = rY;
			ADDR_in = 1'b1;
                    end
			
		    b_: if(!Imm) begin // branch instruction
			     Select = PC_SELECT;
			     A_in = 1'b1;
		    end	

                    default: ;
                endcase


            T4: // define signals T4 (old T2)
               case (III)
               add: begin
                        // Set ALU_and to zero, Set AddSub to zero (for adding) and set Select signal based on
			// the operand to be added (either a register or immediate data)
			if(Imm == 0)  // not immediate data
				Select = rY;
			else // yes immediate data
				Select = SGN_IR8_0_SELECT; // sign extend to the 16 bits Select signal
			
			ALU_and = 1'b0; // DONT do and operation
			AddSub = 1'b0; // 0 means add , 1 means sub
			G_in = 1'b1; // enable G_in register
			F_in = 1'b1; //enable flag changes
               end

               sub: begin
                        // Set ALU_and to zero, Set AddSub to one (for subtracting) and make select signal
			// the operand to be subtracted (either a register or immediate data)
			if(Imm == 0)  // not immediate data
				Select = rY;
			else // yes immediate data
				Select = SGN_IR8_0_SELECT; // sign extend to the 16 bits Select signal
			
			ALU_and = 1'b0; // DONT do and operation
			AddSub = 1'b1; // 0 means add , 1 means sub
			G_in = 1'b1; // enable G_in register
			F_in = 1'b1; //enable flag changes
               end

               and_: begin
			// Set ALU_and to one,and set Select signal based on
			// the operand to be added (either a register or immediate data)
			if(Imm == 0)  // not immediate data
				Select = rY;
			else // yes immediate data
				Select = SGN_IR8_0_SELECT; // sign extend to the 16 bits Select signal
			ALU_and = 1'b1; // yes, do and operation
			G_in = 1'b1; // enable G_in register
			F_in = 1'b1; //enable flag changes
                end

                ld: // wait cycle for synchronous memory (do nothing)
               	    F_in = 1'b0; //disable flag changes

                st: begin
               		Select = rX;
			DOUT_in = 1'b1;
	       		W_D = 1'b1; // write signal enable
                end

   		b_: if(!Imm) begin
                	Select = SGN_IR8_0_SELECT;
	    		ALU_and = 1'b0;
			AddSub = 1'b0;
			G_in = 1'b1;
			F_in = 1'b0; //disable flag changes
		end

                default: ; 
                endcase


            T5: // define T5 (old T3)
                case (III)

                add, sub, and_: begin
                        // Set Select to G_SELECT, since we have the sum in G register
			// Done signal set to 1.
			Select = G_SELECT;
			rX_in = 1'b1; // enable decoder to store result in appropriate register
			Done = 1'b1; // done, go back to T0
                end

                ld: begin
                        Select = DIN_SELECT;
			rX_in = 1'b1; // load into appropriate register
			Done = 1'b1;
                end

                st: // wait cycle for synhronous memory
        	        Done = 1'b1;

		b_:   if(!Imm) begin
                       	    Select = G_SELECT;
			    case(rX) // the 3 bits of rX is where the specific branch condition resides
			    000: pc_in = 1'b1; // 000 is for none     
			    001: if(z) pc_in = 1'b1; // 001 is for eq (equal)
			    010: if(!z) pc_in = 1'b1; // 010 is for ne (not equal)	
			    011: if(!c) pc_in = 1'b1; // 011 is for cc (carry clear) 
			    100: if(c) pc_in = 1'b1; // 100 is for cs (carry set)
			    101: if(!n) pc_in = 1'b1;// 101 is for pl (positive)
			    110: if(n) pc_in = 1'b1; // 110 is for mi (negative)
			    default: ;
			    endcase // end of checking for branch conditions		
                    	    Done = 1'b1;
			end
                default: ;
                endcase
            default: ; // default for entire cases
        endcase
    end   

/*********************************************************************************************************************/
   
    // Control FSM flip-flops
    always @(posedge Clock)
        if (!Resetn)
            Tstep_Q <= T0;
        else
            Tstep_Q <= Tstep_D;   

/*********************************************************************************************************************/
   
    regn reg_0 (BusWires, Resetn, R_in[0], Clock, r0);
    regn reg_1 (BusWires, Resetn, R_in[1], Clock, r1);
    regn reg_2 (BusWires, Resetn, R_in[2], Clock, r2);
    regn reg_3 (BusWires, Resetn, R_in[3], Clock, r3);
    regn reg_4 (BusWires, Resetn, R_in[4], Clock, r4);
    regn reg_5 (BusWires, Resetn, R_in[5], Clock, r5);
    regn reg_6 (BusWires, Resetn, R_in[6], Clock, r6);

    // r7 is program counter
    // module pc_count(R, Resetn, Clock, E, L, Q);
    pc_count reg_pc (BusWires, Resetn, Clock, pc_incr, pc_in, pc);

    regn reg_A (BusWires, Resetn, A_in, Clock, A);
    regn reg_DOUT (BusWires, Resetn, DOUT_in, Clock, DOUT);
    regn reg_ADDR (BusWires, Resetn, ADDR_in, Clock, ADDR);
    regn reg_IR (DIN, Resetn, IR_in, Clock, IR);

    flipflop reg_W (W_D, Resetn, Clock, W);
    
/*********************************************************************************************************************/

    // alu
    always @(*)
        if (!ALU_and) begin
            if (!AddSub) begin
                Sum = A + BusWires;
	    end
	    else begin
                Sum = A + ~BusWires + 16'b1;
		
	    end
        end
	else
            Sum = A & BusWires;

    regn reg_G (Sum, Resetn, G_in, Clock, G);

/*********************************************************************************************************************/

    // define the internal processor bus
    always @(*)
        case (Select)
            R0_SELECT: BusWires = r0;
            R1_SELECT: BusWires = r1;
            R2_SELECT: BusWires = r2;
            R3_SELECT: BusWires = r3;
            R4_SELECT: BusWires = r4;
            R5_SELECT: BusWires = r5;
            R6_SELECT: BusWires = r6;
            PC_SELECT: BusWires = pc;
            G_SELECT: BusWires = G;
            SGN_IR8_0_SELECT: BusWires = {{7{IR[8]}}, IR[8:0]}; // sign extended
            IR7_0_0_0_SELECT: BusWires = {IR[7:0], 8'b0};
            DIN_SELECT: BusWires = DIN;
            default: BusWires = 16'bx;
        endcase
endmodule

/*********************************************************************************************************************/
// submodules

module pc_count(R, Resetn, Clock, E, L, Q);
    input [15:0] R;
    input Resetn, Clock, E, L;
    output [15:0] Q;
    reg [15:0] Q;
   
    always @(posedge Clock)
        if (!Resetn)
            Q <= 16'b0;
        else if (L)
            Q <= R;
        else if (E)
            Q <= Q + 1'b1;
endmodule

module dec3to8(E, W, Y);
    input E; // enable
    input [2:0] W;
    output [0:7] Y;
    reg [0:7] Y;
   
    always @(*)
        if (E == 0)
            Y = 8'b00000000;
        else
            case (W)
                3'b000: Y = 8'b10000000;
                3'b001: Y = 8'b01000000;
                3'b010: Y = 8'b00100000;
                3'b011: Y = 8'b00010000;
                3'b100: Y = 8'b00001000;
                3'b101: Y = 8'b00000100;
                3'b110: Y = 8'b00000010;
                3'b111: Y = 8'b00000001;
            endcase
endmodule

module regn(R, Resetn, E, Clock, Q);
    parameter n = 16;
    input [n-1:0] R;
    input Resetn, E, Clock;
    output [n-1:0] Q;
    reg [n-1:0] Q;

    always @(posedge Clock)
        if (!Resetn)
            Q <= 0;
        else if (E)
            Q <= R;
endmodule
