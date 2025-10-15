`timescale 1ns / 1ps

module apb_ram (
  input presetn,
  input pclk,
  input psel,
  input penable,
  input pwrite,
  input [31:0] paddr, pwdata,
  output reg [31:0] prdata,
  output reg pready, pslverr
);

  reg [31:0] mem [0:31];

  typedef enum {idle = 0, setup = 1, access = 2} state_type;
  state_type state = idle;

  always@(posedge pclk or negedge presetn)
    begin
      if(presetn == 1'b0) //active low reset
        begin
          state <= idle;
          prdata <= 32'h0;
          pready <= 1'b0;
          pslverr <= 1'b0;
          for(int i = 0; i < 32; i++)
            mem[i] <= 32'h0;
        end
      else
        begin
          case(state)
            idle :
            begin
              pready <= 1'b0;
              pslverr <= 1'b0;
              if (psel)
                state <= setup;
              else
                state <= idle;
            end

            setup:
            begin
                if (penable) begin
                    state <= access;
                    pready <= 1'b1; // PREADY is asserted in the access phase
                    if (paddr[4:0] >= 32) begin // Check for invalid address
                        pslverr <= 1'b1;
                        if (!pwrite)
                          prdata <= 32'hxxxxxxxx;
                    end
                    else begin // Valid address
                        pslverr <= 1'b0;
                        if (pwrite)
                            mem[paddr[4:0]] <= pwdata;
                        else
                            prdata <= mem[paddr[4:0]];
                    end
                end
                else begin
                    // Remain in setup if not enabled
                    state <= setup;
                end
            end

            access: begin
                state <= idle;
                pready <= 1'b0;
            end

            default : state <= idle;
          endcase
        end
    end
endmodule

//////////////////////////////////////////////////
interface apb_if ();
  // Signals
  logic             pclk;
  logic             presetn;
  logic [31:0]      paddr;
  logic             pwrite;
  logic [31:0]      pwdata;
  logic             penable;
  logic             psel;
  logic [31:0]      prdata;
  logic             pslverr;
  logic             pready;

endinterface : apb_if
