`include "uvm_macros.svh"
import uvm_pkg::*;

////////////////////////////////////////////////////////////
class transaction extends uvm_sequence_item;
  `uvm_object_utils(transaction)

    rand bit [3:0] a;
    rand bit [3:0] b;
    rand bit [3:0] c;
    rand bit [3:0] d;
    rand bit [1:0] sel;
         bit [3:0] y;

    function new(input string path = "transaction");
      super.new(path);
    endfunction
    
    // Override the compare function for scoreboard checking
    virtual function bit compare (uvm_object rhs, uvm_comparer comparer);
        transaction rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (super.compare(rhs, comparer) && (this.y == rhs_.y));
    endfunction

endclass

////////////////////////////////////////////////////////////////////////
class generator extends uvm_sequence#(transaction);
  `uvm_object_utils(generator)
  function new(string n="generator"); super.new(n); endfunction
  virtual task body();
    repeat(15) `uvm_do(req)
  endtask
endclass

//////////////////////////////////////////////////////////////////////////////
class drv extends uvm_driver#(transaction);
  `uvm_component_utils(drv)
  virtual mux_if mif;
  function new(string n="drv", uvm_component p=null); super.new(n,p); endfunction

  virtual function void build_phase(uvm_phase phase);
    if(!uvm_config_db#(virtual mux_if)::get(this,"","mif",mif))
      `uvm_fatal("DRV","Cannot get interface");
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      mif.a   <= req.a;
      mif.b   <= req.b;
      mif.c   <= req.c;
      mif.d   <= req.d;
      mif.sel <= req.sel;
      `uvm_info("DRV", $sformatf("Driving sel=%0b", req.sel), UVM_MEDIUM);
      seq_item_port.item_done();
       #20;
    end
  endtask
endclass

//////////////////////////////////////////////////////////////////////////
// Monitor for the DUT
class mon extends uvm_monitor;
  `uvm_component_utils(mon)
  uvm_analysis_port#(transaction) send;
  virtual mux_if mif;
  function new(string n="mon", uvm_component p=null); super.new(n,p); endfunction

  virtual function void build_phase(uvm_phase phase);
    send = new("send", this);
    if(!uvm_config_db#(virtual mux_if)::get(this,"","mif",mif))
      `uvm_fatal("MON","Cannot get interface");
  endfunction

  virtual task run_phase(uvm_phase phase);
    transaction tr;
    forever begin
      #20;
      tr = transaction::type_id::create("tr");
      tr.a   = mif.a;
      tr.b   = mif.b;
      tr.c   = mif.c;
      tr.d   = mif.d;
      tr.sel = mif.sel;
      tr.y   = mif.y;
      `uvm_info("MON_DUT", $sformatf("DUT produced y=%0h for sel=%0b", tr.y, tr.sel), UVM_MEDIUM);
      send.write(tr);
    end
  endtask
endclass

////////////////////// Golden Reference Model ////////////////////////////
class ref_model extends uvm_component;
  `uvm_component_utils(ref_model)
  uvm_analysis_export #(transaction) get_input; // Gets input from driver
  uvm_analysis_port #(transaction) send_ref; // Sends predicted output
  transaction tr_in, tr_out;

  function new(string n="ref_model", uvm_component p=null); super.new(n,p); endfunction
  virtual function void build_phase(uvm_phase phase);
    get_input = new("get_input", this);
    send_ref = new("send_ref", this);
  endfunction
  
  // This is the implementation of the export
  function void write(transaction t);
    tr_in = t;
    tr_out = new t; // Copy the transaction
    predict();
    `uvm_info("REF_MODEL", $sformatf("Predicted y=%0h for sel=%0b", tr_out.y, tr_out.sel), UVM_MEDIUM);
    send_ref.write(tr_out);
  endfunction

  function void predict();
    case(tr_out.sel)
      2'b00 : tr_out.y = tr_out.a;
      2'b01 : tr_out.y = tr_out.b;
      2'b10 : tr_out.y = tr_out.c;
      2'b11 : tr_out.y = tr_out.d;
    endcase
  endfunction
endclass

////////////////////////////////////////////////////////////////////////////
class sco extends uvm_scoreboard;
  `uvm_component_utils(sco)
  uvm_tlm_analysis_fifo#(transaction) dut_fifo;
  uvm_tlm_analysis_fifo#(transaction) ref_fifo;

  function new(string n="sco", uvm_component p=null); super.new(n,p); endfunction

  virtual function void build_phase(uvm_phase phase);
    dut_fifo = new("dut_fifo", this);
    ref_fifo = new("ref_fifo", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    transaction dut_tr, ref_tr;
    forever begin
      // The get() tasks block, ensuring we have one transaction from both
      // sources before we proceed. This automatically synchronizes them.
      dut_fifo.get(dut_tr);
      ref_fifo.get(ref_tr);

      if(dut_tr.compare(ref_tr))
        `uvm_info("SCO", "PASS: DUT output matches reference model.", UVM_LOW)
      else
        `uvm_error("SCO", $sformatf("FAIL: Mismatch! DUT y=%0h, REF y=%0h", dut_tr.y, ref_tr.y))
    end
  endtask
endclass

///////////////////////////////////////////////////////////////////////////
class agent extends uvm_agent;
  `uvm_component_utils(agent)
  drv d;
  uvm_sequencer#(transaction) seqr;
  mon m;
  uvm_analysis_port#(transaction) ap; // To broadcast driver items

  function new(string n="agent", uvm_component p=null); super.new(n,p); endfunction
  virtual function void build_phase(uvm_phase phase);
    d    = drv::type_id::create("d",this);
    m    = mon::type_id::create("m",this);
    seqr = uvm_sequencer#(transaction)::type_id::create("seqr", this);
    ap   = new("ap", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    d.seq_item_port.connect(seqr.seq_item_export);
    d.ap.connect(this.ap); // Connect driver's ap to agent's ap
  endfunction
endclass

///////////////////////////////////////////////////////////////////////
class env extends uvm_env;
  `uvm_component_utils(env)
  agent a;
  sco s;
  ref_model rm;
  function new(string n="env", uvm_component p=null); super.new(n,p); endfunction

  virtual function void build_phase(uvm_phase phase);
    a = agent::type_id::create("agent",this);
    s = sco::type_id::create("sco", this);
    rm = ref_model::type_id::create("ref_model", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    // Send driver's items to the reference model
    a.ap.connect(rm.get_input);
    // Send reference model's predicted output to scoreboard
    rm.send_ref.connect(s.ref_fifo.analysis_export);
    // Send DUT monitor's output to scoreboard
    a.m.send.connect(s.dut_fifo.analysis_export);
  endfunction
endclass

//////////////////////////////////////////////////////////////////
class test extends uvm_test;
  `uvm_component_utils(test)
  env e;
  generator gen;
  function new(string n="test", uvm_component p=null); super.new(n,p); endfunction

  virtual function void build_phase(uvm_phase phase);
    e   = env::type_id::create("env",this);
    gen = generator::type_id::create("gen");
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    gen.start(e.a.seqr);
    #300;
    phase.drop_objection(this);
  endtask
endclass

////////////////////////////////////////////////////////////////////
module tb;
  mux_if mif();
  mux dut (.a(mif.a), .b(mif.b), .c(mif.c), .d(mif.d), .sel(mif.sel), .y(mif.y));

  initial begin
    uvm_config_db #(virtual mux_if)::set(null, "*", "mif", mif);
    run_test("test");
  end
endmodule
