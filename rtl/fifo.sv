module fifo #(
  parameter DATA_WIDTH = 64,
  parameter FIFO_DEPTH = 32
)(
    
  input wire clk,
  input wire reset,
  
  // Push interface
  input wire push_i,
  input wire [DATA_WIDTH-1:0] push_data_i,
  
  // Pop interface
  input wire pop_i,
  output wire [DATA_WIDTH-1:0] pop_data_o,
  
  // Flags
  output wire full_o,
  output wire empty_o
  
);
  
  typedef enum reg [1:0] {
    ST_PUSH = 2'b10,
    ST_POP = 2'b01,
    ST_BOTH = 2'b11
  } state_t;
  
  // The states have been chose carefully such that 
  // state = {push_i,pop_i} , concatenation of both the bits
  
  // Using SRAM cell for FIFO memory
  
  localparam PTR_W = $clog2(FIFO_DEPTH);
  
  reg [DATA_WIDTH-1:0] fifo_data_q [FIFO_DEPTH-1:0];
  
  reg [PTR_W-1:0] rd_ptr_q;
  reg [PTR_W-1:0] wr_ptr_q;

  reg wrapped_rd_ptr_q;
  reg wrapped_wr_ptr_q;
	
  // Using re data type since they are present within procedural always block

  reg nxt_wrapped_rd_ptr;
  reg nxt_wrapped_wr_ptr;
 
  reg [PTR_W-1:0] nxt_rd_ptr;
  reg [PTR_W-1:0] nxt_wr_ptr;
  
  reg [DATA_WIDTH-1:0] nxt_fifo_data;
  reg [DATA_WIDTH-1:0] pop_data ;
  
  // Driven via assigns combinatorially
  wire empty;
  wire full;
  
  // Using reg since they are present withing always block
 
  reg [DATA_WIDTH-1:0] rd_fifo_data;

  // Note You can drive registers as input ports to an instantiated module , but you cannot drive them in the child module 
    /*
    When you connect a reg to a module input, it?s totally fine because the port itself is just a wire by default, and you're driving that input from the outside.
    What you can?t do is try to assign to that input inside the submodule if it?s not declared as an output
    TLDR : Can you connect a reg to an input port? | ? Yes | | Can the submodule assign to that input? | ? No (unless it's an inout or output) |
    */
  
  //In old verilog , the equivalent of always_comb is always@(*) -> basic point

  // Flops for FIFO pointers
  
  always_ff @(posedge clk or posedge reset) begin
    if(reset) begin
      rd_ptr_q <= PTR_W'(1'b0);
      wr_ptr_q <= PTR_W'(1'b0);
      // When in reset wrapped pointers driven to 0
      wrapped_rd_ptr_q <= 1'b0;
      wrapped_wr_ptr_q <= 1'b0;
    end
  
  	else begin
      rd_ptr_q <= nxt_rd_ptr;
      wr_ptr_q <= nxt_wr_ptr;
      wrapped_rd_ptr_q <= nxt_wrapped_rd_ptr;
      wrapped_wr_ptr_q <= nxt_wrapped_wr_ptr;
    end
  end
  
  // Pointer logic for Push and Pop
  // Will use an FSM for the pointer logic
  
  always@(*) begin
    // Always good to drive these signals to default values
    // This is to avoid latches (inferred latches)
    nxt_fifo_data = fifo_data_q[rd_ptr_q[PTR_W-1:0]];
    nxt_rd_ptr = rd_ptr_q;
    nxt_wr_ptr = wr_ptr_q;
    nxt_wrapped_rd_ptr = wrapped_rd_ptr_q;
    nxt_wrapped_wr_ptr = wrapped_wr_ptr_q;
    case({push_i,pop_i}) // 2-bit signal with push as MSB and pop as LSB
      ST_PUSH: begin
        nxt_fifo_data = push_data_i;
        //Manipulate the write pointer
        /*
        Need to take care of the case where WRITE Pointer is at max value
        One must reset write pointer to 0 in such a case
        Problem occurs when depth is not a multiple of 2
        Example : Depth of Fifo = 6 and write_ptr = 5
        5 -> 3'b101 , if you blindly increment write pointer by 1 
        write_ptr becomes 6 -> 3'b110 , whereas it should've become 3'b000
        */

        // Handling the Wrapped Pointers too
        nxt_wr_ptr = (wr_ptr_q == PTR_W'(FIFO_DEPTH-1)) ? (PTR_W'(1'b0)) : (wr_ptr_q + PTR_W'(1'b1));
        nxt_wrapped_wr_ptr = (wr_ptr_q == PTR_W'(FIFO_DEPTH-1)) ? (~wrapped_wr_ptr_q) : wrapped_wr_ptr_q;
        // Using conditional assignment instead of if else blocks
      end

      ST_POP: begin
        // Read the FIFO location pointed out by the read pointer
        pop_data = fifo_data_q[rd_ptr_q[PTR_W-1:0]];
        // Manipulate the read pointer
        // Similar to write pointer case , if rd_ptr is at PTR_W-1 , next state , it should go to 0
        nxt_rd_ptr = (rd_ptr_q == PTR_W'(FIFO_DEPTH-1)) ? (PTR_W'(1'b0)) : (rd_ptr_q + PTR_W'(1'b1));
        nxt_wrapped_rd_ptr = (rd_ptr_q == PTR_W'(FIFO_DEPTH-1)) ? (~wrapped_rd_ptr_q) : wrapped_rd_ptr_q;
      end

      ST_BOTH: begin
        // In this case both rd and write pointers have to get incremented by 1
        // We need to give out data pointed to by Read pointer and Write into location pointed by write pointer
        // However we'll need to manipulate both the pointers in this case

        // Even if the read pointer and write pointer are same , the write happens one cycle later
        // Read pointer would read in that cycle and write will occur in next cycle

        nxt_fifo_data = push_data_i;
        nxt_wr_ptr = (wr_ptr_q == PTR_W'(FIFO_DEPTH-1)) ? (PTR_W'(1'b0)) : (wr_ptr_q + PTR_W'(1'b1));
        nxt_wrapped_wr_ptr = (wr_ptr_q == PTR_W'(FIFO_DEPTH-1)) ? (~wrapped_wr_ptr_q) : wrapped_wr_ptr_q;

        pop_data = fifo_data_q[rd_ptr_q[PTR_W-1:0]];
        nxt_rd_ptr = (rd_ptr_q == PTR_W'(FIFO_DEPTH-1)) ? (PTR_W'(1'b0)) : (rd_ptr_q + PTR_W'(1'b1));
        nxt_wrapped_rd_ptr = (rd_ptr_q == PTR_W'(FIFO_DEPTH-1)) ? (~wrapped_rd_ptr_q) : wrapped_rd_ptr_q;
        
      end
      default: begin
        // We shall enter here whenever one of our signals goes into an Unkown state 
        // We can enter here if both push = 0 and pop = 0 too!
        // In this case we shouldnt change anything and keep the configuration as is
        nxt_fifo_data = fifo_data_q[rd_ptr_q[PTR_W-1:0]];
        nxt_rd_ptr = rd_ptr_q;
        nxt_wr_ptr = wr_ptr_q;
      end

    endcase
  end
      
      
   // Flops for FIFO Data -> Other implementation makes use of sram cell
   // We generally dont reset the entire memory array of the FIFO to 0s
   // This is because if the FIFO is reset , the empty flag would indicate that.
   // So there is no real need to reset the data elements
   // Data pointed by a read pointer in NON EMPTY CONDITION , would always be valid
   // Reset Flops generally taking up more area than non reset flops
   // So we shall avoid resetting FIFO DATA
        
   always_ff@(posedge clk) begin
     fifo_data_q[wr_ptr_q[PTR_W-1:0]] <= nxt_fifo_data;
   end
          
         
  
  // Understanding the logic for Full and Empty flags

  /*
  Consider a FIFO of depth 4
  Possible states for the 2 pointers 
     wr_ptr   rd_ptr
      00        00
      01        01
      10        10
      11        11
  Need to know whether empty or full
  For both scenarios , the condition is (rd_ptr == wr_ptr) -> HOW DO YOU DIFFERENTIATE
  Consider the following case : 
  Out of reset : Both rd_ptr and wr_ptr are 0
  Here : rd_ptr == wr_ptr -> empty = 1 , full = 0
  Then as a result of 4 writes , the wr_ptr would have to written to 4 locations and would be present at 00
  In this case (wr_ptr == rd_ptr) !! -> but full = 1, empty = 0

  In order to tackle this situation , we make use of WRAPPED POINTERS
  Wrapped pointers reset to 0.
  Whenever read or write pointers of the FIFO cross the terminal location i.e. PTR_W - 1 -> the pointers are toggled

  So in the case where we have 4 writes (pushes) post reset and 0 reads (pops) ->
  
    wr_ptr    rd_ptr
    0  00       0 00
    0  01       0 00
    0  10       0 00
    0  11       0 00
---------------------------> Write pointer would now wrap !! Wrap bit would toggle
    1  00       0 00

    The MSB Wrap bit can be separately called as a Wrap pointer -> We shall be having wrap_wr_ptr and wrap_rd_ptr

    So we now have the conditions to compute empty and full flags as follows : 
    Full if   -> wr_ptr == rd_ptr && (wrap_wr_ptr != wrap_rd_ptr)
    Emtpy if  -> wr_ptr == rd_ptr && (wrap_wr_ptr == wrap_rd_ptr)
  */

  assign empty = (rd_ptr_q == wr_ptr_q) && (wrapped_rd_ptr_q == wrapped_wr_ptr_q);
  assign full = (rd_ptr_q == wr_ptr_q) && (wrapped_rd_ptr_q != wrapped_wr_ptr_q);

  // Output Assignments
  assign pop_data_o = pop_data;
  assign full_o = full;
  assign empty_o = empty;
  
endmodule