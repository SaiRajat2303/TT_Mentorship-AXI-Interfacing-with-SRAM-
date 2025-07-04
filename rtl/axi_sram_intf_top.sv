module axi_sram_intf_top
#(
    parameter AXI_ADDR_WIDTH = 8;
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ID_WIDTH = 4,
    parameter AXI_SIZE_WIDTH = 3,
    parameter SRAM_DATA_WIDTH = 8,
    parameter SRAM_ADDR_WIDTH = 8,
    parameter FIFO_DEPTH = 8,
    parameter FIFO_ADDR_WIDTH = $clog2(FIFO_DEPTH)
)
(
    input clk,
    input reset,

    // AXI AW channel
    input logic [AXI_ADDR_WIDTH-1:0] axi_aw_addr,
    input logic axi_aw_valid,
    input logic [AXI_ID_WIDTH-1:0] axi_aw_id,
    input logic [AXI_SIZE_WIDTH-1:0] axi_aw_size,
    output logic axi_aw_ready,

    // AXI W channel
    input logic axi_w_valid,
    input logic [AXI_DATA_WIDTH-1:0] axi_w_data,
    output logic axi_w_ready,

    // AXI B channel
    output logic axi_b_valid,
    output logic [AXI_ID_WIDTH-1:0] axi_b_id,
    output loigc axi_b_resp,
    input logic axi_b_ready 
    // Can keep this channel tied to 1 ? We can always receive a completion response which can help free up the FIFOs
    // In what case can we not be ready to receive a completion ? - Get this clarified by Mijat
);

// AW FIFO signals
logic aw_push;
logic aw_pop;
logic aw_pop_d1; // Delayed version of pop signal to handle timing issues
logic [AXI_ID_WIDTH-1:0] aw_id_pop;
logic aw_full;
logic aw_empty;

// W FIFO signals
logic w_push;
logic w_pop;
logic w_full;
logic w_empty;

assign axi_b_ready = 1'b1; // Always ready to receive B channel response

// After Popping from AW and W - FIFOs -> push it into B - FIFO and wait for completion
// This is an IN-ORDER AXI write completion setup.

// Possible Enhancement is to use Round-Robin Arbiters to handle requests out of order.

// FIFO instantiations
fifo #(
    .DATA_WIDTH(AXI_ADDR_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH)
) aw_addr_fifo
(
    .clk(clk),
    .reset(reset),
    .push_i(aw_push),
    .push_data_i(axi_aw_addr),
    .pop_i(aw_addr_pop),
    .pop_data_o(), // leave unconnected -> not required
    .full_o(aw_full),
    .empty_o(aw_empty)
);

fifo #(
    .DATA_WIDTH(AXI_ID_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH)
) aw_id_fifo
(
    .clk(clk),
    .reset(reset),
    .push_i(aw_push),
    .push_data_i(axi_aw_id),
    .pop_i(aw_pop),
    .pop_data_o(aw_id_pop), // need the popped data to signal completion on B channel
    .full_o(),
    .empty_o()
);

fifo #(
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH)
) w_data_fifo
(
    .clk(clk),
    .reset(reset),
    .push_i(w_push),
    .push_data_i(axi_w_data),
    .pop_i(w_pop),
    .pop_data_o(), // leave unconnected -> not required
    .full_o(w_full),
    .empty_o(w_empty)
);


assign axi_aw_ready = !aw_full; // Ready to accept new AW requests if not full
assign axi_w_ready = !w_full; // Ready to accept new W requests if not full

// SRAM handling signals
logic sram_txn_in_progress; // Signal to indicate SRAM is being written into 
logic sram_txn_in_progress_d1; // Delayed version of the signal to detect changes
logic [SRAM_DATA_WIDTH-1:0] sram_data_in;
logic sram_ready; // Signal to indicate SRAM is ready for a new transaction


// Dont need a B-FIFO as only 1 transaction is in progress at a time   
// Use Buffer signal for holding B -ID 
logic [AXI_ID_WIDTH-1:0] b_id; // ID to push into B channel after write completion into SRAM
// Can use negedge detector of sram_txn_in_progress to trigger B channel response

always_ff@(posedge clk) begin
    // 1 cycle delay variants
    sram_txn_in_progress_d1 <= sram_txn_in_progress;
    aw_pop_d1 <= aw_pop;
end

// AW FIFO Handling

always_ff@(posedge clk or posedge reset) begin
    if(reset) begin
        aw_push <= 1'b0;
        aw_pop <= 1'b0;
    end 
    else begin
        if(axi_aw_valid && axi_aw_ready) begin
            aw_push <= 1'b1; // Push AW request into FIFO
        end 
        else begin
            aw_push <= 1'b0; // Not pushing if not valid or full
        end
        
        if(!aw_empty && sram_ready) begin
            aw_pop <= 1'b1; // Pop from AW FIFO when B channel is ready
        end 
        else begin
            aw_pop <= 1'b0; // Not popping if empty or B channel not ready
        end
    end
end

// W FIFO Handling

always_ff@(posedge clk) begin
    if(reset) begin
        w_push <= 1'b0;
        w_pop <= 1'b0;
    end 
    else begin
        if(axi_w_valid && axi_w_ready) begin
            w_push <= 1'b1; // Push W request into FIFO
        end 
        else begin
            w_push <= 1'b0; // Not pushing if not valid or full
        end
        
        if(!w_empty && sram_ready) begin
            w_pop <= 1'b1; // Pop from W FIFO when B channel is ready
        end 
        else begin
            w_pop <= 1'b0; // Not popping if empty or B channel not ready
        end
    end
end

axi_sram_data_chunk_breaker #(
    .AXI_SIZE_WIDTH(AXI_SIZE_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .SRAM_DATA_WIDTH(SRAM_DATA_WIDTH)
)(
    .clk(clk),
    .reset(reset),
    .axi_size(axi_aw_size),
    .axi_data_in(axi_w_data),
    .axi_start_addr(aw_addr_pop), // Address from AW FIFO
    .sram_data_in(sram_data_in), // Connect to SRAM input
    .sram_addr_in(sram_addr_in), // Address from AW FIFO
    .sram_txn_in_progress(sram_txn_in_progress)
);

assign sram_ready = !sram_txn_in_progress; // SRAM is ready when not in transaction

// B - ID and B Channel response handling

always_ff@(posedge clk) begin
    if(sram_txn_in_progress & !sram_txn_in_progress_d1) begin
        b_id <= aw_id_pop; // Capture the ID from AW FIFO when transaction starts
    end
    else if(sram_txn_in_progress_d1 & !sram_txn_in_progress & axi_b_ready) begin
        axi_b_valid <= 1'b1; // Signal B channel valid when transaction completes
        axi_b_id <= b_id; // Push the captured ID into B channel
    end     
    else begin
        b_id <= b_id; // Hold the ID if no new transaction
    end
end

// Instantiate SRAM cell here 

sram_cell #(
    .SRAM_DEPTH(SRAM_DEPTH),
    .DATA_WIDTH(SRAM_DATA_WIDTH),
    .MASK_WIDTH(SRAM_DATA_WIDTH/8) // Assuming 1 byte mask for each 8 bits of data
    .RAM_INDEX_WIDTH(SRAM_ADDR_WIDTH)
)(
    .chip_en_i(sram_txn_in_progress), // Enable chip when transaction is in progress
    .wr_en_i(sram_txn_in_progress), // Write enable when transaction is in progress
    .addr_i(sram_addr_in), // Address from AW FIFO
    .wr_data_i(sram_data_in), // Data from SRAM data chunk breaker
    .wr_mask_en_i(1'b1), // Assuming mask is always enabled for simplicity
    .wr_mask_i(8'hFF), // Assuming full mask for simplicity, can be modified based on requirements
    .rd_en_i(1'b0), // No read operation in this design
    .rd_data_o(), // Not used in this design, leave unconnected

    .clk(clk),
    .reset(reset) // Reset signal for SRAM cell
);


endmodule
