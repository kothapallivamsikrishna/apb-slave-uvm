`timescale 1ns / 1ps
`include "uvm_macros.svh"
 import uvm_pkg::*;

////////////////////////////////////////////////////////////////////////////////////
class abp_config extends uvm_object;
  `uvm_object_utils(abp_config)
  function new(string name = "abp_config"); super.new(name); endfunction
  uvm_active_passive_enum is_active = UVM_ACTIVE;
endclass

///////////////////////////////////////////////////////
typedef enum bit [1:0]   {readd = 0, writed = 1, rst = 2} oper_mode;

//////////////////////////////////////////////////////////////////////////////////
class transaction extends uvm_sequence_item;
    rand oper_mode      op;
    rand logic [31:0]   PWDATA;
    rand logic [31:0]   PADDR;

    logic               PREADY;
    logic               PSLVERR;
    logic [31: 0]       PRDATA;

    `uvm_object_utils(transaction)

  constraint valid_addr_c { PADDR < 32; }
  constraint invalid_addr_c { PADDR >= 32; }

  function new(string name = "transaction");
    super.new(name);
  endfunction
endclass : transaction

//////////////////////////////////////////////////////////////////
class write_data extends uvm_sequence#(transaction);
  `uvm_object_utils(write_data)
  transaction tr;
  function new(string name = "write_data"); super.new(name); endfunction
  virtual task body();
    repeat(15) begin
      tr = transaction::type_id::create("tr");
      start_item(tr);
      assert(tr.randomize() with {op == writed; valid_addr_c;});
      finish_item(tr);
    end
  endtask
endclass

//////////////////////////////////////////////////////////
class read_data extends uvm_sequence#(transaction);
  `uvm_object_utils(read_data)
  transaction tr;
  function new(string name = "read_data"); super.new(name); endfunction
  virtual task body();
    repeat(15) begin
      tr = transaction::type_id::create("tr");
      start_item(tr);
      assert(tr.randomize() with {op == readd; valid_addr_c;});
      finish_item(tr);
    end
  endtask
endclass

///////////////////////////////////////////////////////
class writeb_readb extends uvm_sequence#(transaction);
  `uvm_object_utils(writeb_readb)
  function new(string name = "writeb_readb"); super.new(name); endfunction
  virtual task body();
    write_data w_seq = write_data::type_id::create("w_seq");
    read_data r_seq = read_data::type_id::create("r_seq");
    w_seq.start(m_sequencer);
    r_seq.start(m_sequencer);
  endtask
endclass

/////////////////////////////////////////////////////////////////
class write_err extends uvm_sequence#(transaction);
  `uvm_object_utils(write_err)
  transaction tr;
  function new(string name = "write_err"); super.new(name); endfunction
  virtual task body();
    repeat(5) begin
      tr = transaction::type_id::create("tr");
      start_item(tr);
      assert(tr.randomize() with {op == writed; invalid_addr_c;});
      finish_item(tr);
    end
  endtask
endclass

///////////////////////////////////////////////////////////////
class read_err extends uvm_sequence#(transaction);
  `uvm_object_utils(read_err)
  transaction tr;
  function new(string name = "read_err"); super.new(name); endfunction
  virtual task body();
    repeat(5) begin
      tr = transaction::type_id::create("tr");
      start_item(tr);
      assert(tr.randomize() with {op == readd; invalid_addr_c;});
      finish_item(tr);
    end
  endtask
endclass

////////////////////////////////////////////////////////////
class driver extends uvm_driver #(transaction);
  `uvm_component_utils(driver)
  virtual apb_if vif;
  transaction tr;

  function new(input string path = "drv", uvm_component parent = null);
    super.new(path,parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual apb_if)::get(this,"","vif",vif))
      `uvm_error("drv","Unable to access Interface");
  endfunction

  task reset_dut();
    vif.presetn  <= 1'b0; // Assert active-low reset
    vif.psel     <= 1'b0;
    vif.penable  <= 1'b0;
    `uvm_info("DRV", "System Reset Asserted", UVM_MEDIUM);
    repeat(5) @(posedge vif.pclk);
    vif.presetn  <= 1'b1; // De-assert reset
    `uvm_info("DRV", "System Reset De-asserted", UVM_MEDIUM);
  endtask

  virtual task run_phase(uvm_phase phase);
    reset_dut();
    forever begin
      seq_item_port.get_next_item(tr);
      // SETUP phase
      vif.psel    <= 1'b1;
      vif.paddr   <= tr.PADDR;
      vif.pwrite  <= (tr.op == writed);
      vif.pwdata  <= (tr.op == writed) ? tr.PWDATA : 32'hz;
      `uvm_info("DRV", $sformatf("SETUP: OP=%s ADDR=%0h WDATA=%0h", tr.op.name(), tr.PADDR, tr.PWDATA), UVM_NONE);
      @(posedge vif.pclk);

      // ACCESS phase
      vif.penable <= 1'b1;
      @(posedge vif.pclk);
      
      // Wait for PREADY
      while (!vif.pready) begin
        @(posedge vif.pclk);
      end
      
      // Capture outputs on PREADY
      tr.PRDATA = vif.prdata;
      tr.PSLVERR = vif.pslverr;
      `uvm_info("DRV", $sformatf("ACCESS: RDATA=%0h PSLVERR=%0b", tr.PRDATA, tr.PSLVERR), UVM_NONE);

      // End transaction
      vif.psel    <= 1'b0;
      vif.penable <= 1'b0;
      seq_item_port.item_done();
    end
  endtask
endclass

//////////////////////////////////////////////////////////////////
class mon extends uvm_monitor;
  `uvm_component_utils(mon)
  uvm_analysis_port#(transaction) send;
  transaction tr;
  virtual apb_if vif;

  function new(string inst = "mon", uvm_component parent = null);
    super.new(inst,parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tr = transaction::type_id::create("tr");
    send = new("send", this);
    if(!uvm_config_db#(virtual apb_if)::get(this,"","vif",vif))
      `uvm_error("MON","Unable to access Interface");
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.pclk);
      // Capture transaction when PSEL, PENABLE and PREADY are high
      if (vif.psel && vif.penable && vif.pready) begin
        tr.PADDR   = vif.paddr;
        tr.PWDATA  = vif.pwdata;
        tr.PRDATA  = vif.prdata;
        tr.PSLVERR = vif.pslverr;
        tr.op      = vif.pwrite ? writed : readd;
        `uvm_info("MON", $sformatf("Captured transaction: OP=%s ADDR=%0h", tr.op.name(), tr.PADDR), UVM_NONE);
        send.write(tr);
      end
    end
  endtask
endclass

/////////////////////////////////////////////////////////////////////
class sco extends uvm_scoreboard;
  `uvm_component_utils(sco)
  uvm_analysis_imp#(transaction,sco) recv;
  bit [31:0] mem_model[32];

  function new(input string inst = "sco", uvm_component parent = null);
    super.new(inst,parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    recv = new("recv", this);
  endfunction

  virtual function void write(transaction tr);
    if (tr.PADDR < 32) begin // Valid Address
      if (tr.op == writed) begin
        if (tr.PSLVERR)
          `uvm_error("SCO", $sformatf("FAIL: Slave flagged error on valid WRITE to ADDR %0h", tr.PADDR));
        else begin
          mem_model[tr.PADDR] = tr.PWDATA;
          `uvm_info("SCO", $sformatf("MODEL: Stored %0h at ADDR %0h", tr.PWDATA, tr.PADDR), UVM_NONE);
        end
      end
      else begin // READ
        if (tr.PSLVERR)
          `uvm_error("SCO", $sformatf("FAIL: Slave flagged error on valid READ from ADDR %0h", tr.PADDR));
        else if (mem_model[tr.PADDR] == tr.PRDATA)
          `uvm_info("SCO", $sformatf("PASS: Data matched for ADDR %0h. Got %0h", tr.PADDR, tr.PRDATA), UVM_NONE);
        else
          `uvm_error("SCO", $sformatf("FAIL: Data mismatch for ADDR %0h. Expected %0h, Got %0h", tr.PADDR, mem_model[tr.PADDR], tr.PRDATA));
      end
    end
    else begin // Invalid Address
      if(tr.PSLVERR)
        `uvm_info("SCO", $sformatf("PASS: Slave correctly flagged error for invalid ADDR %0h", tr.PADDR), UVM_NONE);
      else
        `uvm_error("SCO", $sformatf("FAIL: Slave did NOT flag error for invalid ADDR %0h", tr.PADDR));
    end
    $display("----------------------------------------------------------------");
  endfunction
endclass

/////////////////////////////////////////////////////////////////////
class agent extends uvm_agent;
  `uvm_component_utils(agent)
  abp_config cfg;
  function new(string inst = "agent", uvm_component parent = null); super(inst,parent); endfunction
  driver d;
  uvm_sequencer#(transaction) seqr;
  mon m;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg =  abp_config::type_id::create("cfg");
    m = mon::type_id::create("m",this);
    if(cfg.is_active == UVM_ACTIVE) begin
      d = driver::type_id::create("d",this);
      seqr = uvm_sequencer#(transaction)::type_id::create("seqr", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if(cfg.is_active == UVM_ACTIVE) begin
      d.seq_item_port.connect(seqr.seq_item_export);
    end
  endfunction
endclass

//////////////////////////////////////////////////////////////////////////////////
class env extends uvm_env;
  `uvm_component_utils(env)
  function new(input string inst = "env", uvm_component c); super(inst,c); endfunction
  agent a;
  sco s;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    a = agent::type_id::create("a",this);
    s = sco::type_id::create("s", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    a.m.send.connect(s.recv);
  endfunction
endclass

//////////////////////////////////////////////////////////////////////////
class base_test extends uvm_test;
    `uvm_component_utils(base_test)
    env e;
    function new(string name="base_test", uvm_component parent=null); super.new(name,parent); endfunction
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        e = env::type_id::create("env", this);
    endfunction
endclass

class sanity_test extends base_test;
    `uvm_component_utils(sanity_test)
    function new(string name="sanity_test", uvm_component parent=null); super.new(name,parent); endfunction
    virtual task run_phase(uvm_phase phase);
        writeb_readb seq = writeb_readb::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(e.a.seqr);
        #40000;
        phase.drop_objection(this);
    endtask
endclass

class error_test extends base_test;
    `uvm_component_utils(error_test)
    function new(string name="error_test", uvm_component parent=null); super.new(name,parent); endfunction
    virtual task run_phase(uvm_phase phase);
        write_err w_err_seq = write_err::type_id::create("w_err_seq");
        read_err r_err_seq = read_err::type_id::create("r_err_seq");
        phase.raise_objection(this);
        w_err_seq.start(e.a.seqr);
        #20000;
        r_err_seq.start(e.a.seqr);
        #20000;
        phase.drop_objection(this);
    endtask
endclass

//////////////////////////////////////////////////////////////////////
module tb;
  apb_if vif();
  apb_ram dut (.presetn(vif.presetn), .pclk(vif.pclk), .psel(vif.psel), .penable(vif.penable), .pwrite(vif.pwrite), .paddr(vif.paddr), .pwdata(vif.pwdata), .prdata(vif.prdata), .pready(vif.pready), .pslverr(vif.pslverr));

  initial begin
    vif.pclk <= 0;
  end
  always #10 vif.pclk <= ~vif.pclk;

  initial begin
    uvm_config_db#(virtual apb_if)::set(null, "*", "vif", vif);
    run_test("sanity_test"); // Can be changed to "error_test"
   end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
endmodule
