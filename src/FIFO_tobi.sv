module FIFO_tobi
  #(
  parameter int WIDTH = 32,
  parameter int DEPTH_EXP = 2,
  parameter int PASSTHRU_COMB = 1,
  parameter int PASSTHRU_Q = 1
  )(
  input logic clk,
  input logic rst,

  // Write
  input logic valid_i,
  output logic ready_o,
  input logic [WIDTH-1:0] data_i,

  // Read
  output logic valid_o,
  input logic ready_i,
  output logic [WIDTH-1:0] data_o
  );

  logic [WIDTH-1:0] mem_q[2**DEPTH_EXP];
  logic [DEPTH_EXP:0] write_ptr_q;
  logic [DEPTH_EXP:0] read_ptr_q;

  logic valid_q;
  logic [WIDTH-1:0] data_q;

  logic [DEPTH_EXP-1:0] write_idx;
  logic [DEPTH_EXP-1:0] read_idx;
  logic write_msb;
  logic read_msb;
  logic empty;
  logic full;
  logic can_write;
  logic can_read;

  logic passthru_comb;

  always_comb begin
    write_idx = write_ptr_q[DEPTH_EXP-1:0];
    read_idx = read_ptr_q[DEPTH_EXP-1:0];
    write_msb = write_ptr_q[DEPTH_EXP];
    read_msb = read_ptr_q[DEPTH_EXP];

    empty = write_ptr_q == read_ptr_q;
    full = write_idx == read_idx && write_msb != read_msb;
    can_write = !full;
    can_read = !empty;

    ready_o = can_write;
    valid_o = valid_q;
    data_o = data_q;

    passthru_comb = empty && !valid_q && 1'(PASSTHRU_COMB);

    if (passthru_comb) begin
      valid_o = valid_i;
      data_o = data_i;
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      write_ptr_q <= '0;
      read_ptr_q <= '0;
      valid_q <= '0;
      data_q <= 'x;
    end else begin
      if (passthru_comb && ready_i) begin
      end else if (empty && (ready_i || !valid_q) && 1'(PASSTHRU_Q)) begin
        valid_q <= valid_i;
        data_q <= data_i;
      end else begin
        // Write
        if (valid_i && can_write) begin
          mem_q[write_idx] <= data_i;
          write_ptr_q <= write_ptr_q + 1;
        end

        // Read
        if (ready_i || !valid_q) begin
          valid_q <= '0;
          data_q <= 'x;
          if (can_read) begin
            data_q <= mem_q[read_idx];
            read_ptr_q <= read_ptr_q + 1;
            valid_q <= '1;
          end
        end
      end
    end
  end

endmodule
