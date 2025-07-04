module axi_sram_data_chunk_breaker
#(
    AXI_SIZE_WIDTH = 3,
    AXI_DATA_WIDTH = 64,
    SRAM_DATA_WIDTH = 8
)
(
    input logic clk,
    input logic reset,
    input logic [AXI_SIZE_WIDTH-1:0] axi_size,
    input logic [AXI_DATA_WIDTH-1:0] axi_data_in,
    output logic [SRAM_DATA_WIDTH-1:0] sram_data_in, // input data to the SRAM
    output logic [AXI_ADDR_WIDTH-1:0] sram_addr_in;
    output logic sram_txn_in_progress
);
// FSM based handling for writing Data chunks correctly into SRAM

typedef enum logic [1:0] {
    IDLE,
    DATA_CHUNK_START,
    DATA_CHUNK_IN_PROGRESS,
    DONE
  } state_t;


logic [SRAM_DATA_WIDTH-1:0] data_chunk;
logic [SRAM_ADDR_WIDTH-1:0] sram_addr; 
logic [SRAM_DATA_WIDTH-1:0] chunk_counter;
logic [SRAM_DATA_WIDTH-1:0] num_chunks;
logic chunk_taken;
logic chunk_clear;

assign num_chunks = (axi_size == 4) ? 8 : (axi_size == 3) ? 4 : (axi_size == 2) ? 2 : 1; // Calculate number of chunks based on AXI size

state_t current_state, next_state;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        current_state <= IDLE;
    end 
    else begin
        current_state <= next_state;
    end
end

always_ff @(posedge clk) begin
    if (chunk_taken) begin
        sram_data_in <= data_chunk; // Load the data chunk into SRAM input
        sram_addr_in <= sram_addr; // Set the address for SRAM
        chunk_counter <= chunk_counter + 1; // Increment the chunk counter
        sram_txn_in_progress <= 1; // Indicate that a transaction is in progress
    end 
    else begin
        sram_data_in <= '0; // Clear SRAM input when not taking a chunk
        sram_txn_in_progress <= 0; // No transaction in progress
    end
end


always_comb begin
    case(current_state) 
        IDLE: begin
            next_state = (axi_size > 0) ? DATA_CHUNK_START : IDLE;
            chunk_taken = 0;
            chunk_clear = 1;
        end
        DATA_CHUNK_START: begin
            data_chunk = axi_data_in[SRAM_DATA_WIDTH-1:0]; // Load first chunk
            chunk_taken = 1;
            sram_addr = axi_start_addr; // Set the starting address for SRAM
            chunk_clear = 0; // Clear chunk flag
            next_state = DATA_CHUNK_IN_PROGRESS;
        end
        DATA_CHUNK_IN_PROGRESS: begin
            if (chunk_counter < num_chunks) begin
                data_chunk = axi_data_in[SRAM_DATA_WIDTH*chunk_counter +: SRAM_DATA_WIDTH]; // Load next chunk
                sram_addr = axi_start_addr + chunk_counter[SRAM_ADDR_WIDTH-1:0]; // Increment the address for next chunk
                chunk_taken = 1;
                next_state = DATA_CHUNK_IN_PROGRESS;
            end 
            else begin
                next_state = DONE;
            end
        end
        DONE: begin
            data_chunk = '0; // Clear the data chunk
            next_state = IDLE; // Go back to IDLE state
        end
    endcase
end




endmodule

/*
Encoding for AXI Sizes : 
Size = 1 -> 1 byte (8 bits) 
Size = 2 -> 2 bytes (16 bits)
Size = 3 -> 4 bytes (32 bits)
Size = 4 -> 8 bytes (64 bits)
May not be aligned to Spec Values
*/
