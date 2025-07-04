module sram_cell
#(
    // These are default values of parameters
    // need to compute and send from top module for different use cases
    parameter SRAM_DEPTH = 512,
    parameter DATA_WIDTH = 64,
    parameter MASK_WIDTH = 8,
    parameter RAM_INDEX_WIDTH = 9 
)(
    input   logic                            chip_en_i,
    // Write Input Ports
    input   logic                            wr_en_i,
    input   logic [RAM_INDEX_WIDTH-1:0]      addr_i,
    input   logic [DATA_WIDTH-1:0]           wr_data_i,
    input   logic                            wr_mask_en_i,
    input   logic [MASK_WIDTH-1:0]           wr_mask_i,
    // Read Input Ports
    input   logic                            rd_en_i,
    // Outputs from SRAM CELL
    output  logic [DATA_WIDTH-1:0]           rd_data_o,
    // Generic ports
    input   logic                            clk,
    input   logic                            reset 
);
    // Using an active high reset signal
    // negate and pass reset_n in the instantiation at the top
    
    // Creating a memory Array
    logic [DATA_WIDTH-1:0] sram_mem [SRAM_DEPTH - 1:0];
    logic [(MASK_WIDTH*8)-1:0] wr_bit_mask;
    // initialising memory array to zero

    // Asynchronous READ operation
    always_comb begin
    	if(chip_en_i && rd_en_i) begin
            rd_data_o = sram_mem[addr_i];
        end 
      	else begin
            rd_data_o = {DATA_WIDTH{1'b0}}; 
          // default to zero if chip is disabled or read is not enabled
        end 

        for(int i = 0 ; i < MASK_WIDTH; i++) begin
            if((wr_mask_i >> i) & 1) begin
              wr_bit_mask[i*MASK_WIDTH +: MASK_WIDTH] = {MASK_WIDTH{1'b1}};
              // Note the interesting bit slicing way 
              // i*8 +: 8 -> implies selecting 8 bits starting from i*8
            end
          	else begin
              wr_bit_mask[i*MASK_WIDTH +: MASK_WIDTH] = {MASK_WIDTH{1'b0}};
            end
        end
        // Generate a write bit mask as soon as wr_mask_i changes
    end
  

    // Synchronous Write Operation
    always_ff@(posedge clk or posedge reset) begin
        // Upon reset - need to refresh the memory array
        if(reset) begin
            for(int i = 0; i < SRAM_DEPTH; i++) begin
              sram_mem[i] <= 0; // reset memory to zero
            end
        end

        if(chip_en_i && wr_en_i) begin
            if(wr_mask_en_i) begin // for a mask operation
              sram_mem[addr_i] <= (sram_mem[addr_i] & (~wr_bit_mask)) | (wr_data_i & wr_bit_mask);
                // sram_mem[addr_i] & (~wr_bit_mask) -> will make that particular part of mask 0s in the memory entry
                // Then an OR with (write_data_i & wr_bit_mask) -> will fill it in that position
            end
            else begin
                sram_mem[addr_i] <= wr_data_i;
            end
        end
    end

endmodule