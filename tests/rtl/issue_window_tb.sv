module issue_window_tb;
    bit clk = 0;
    always #5 clk = !clk;
    logic reset, push_valid, accept;
    logic [23:0] push_regs;
    logic [3:0] push_mask, entry_ready;
    logic [1:0] push_kind;
    wire [1:0] index [2], kind [2];
    wire [2:0] count [2];
    wire [3:0] mask [2];
    wire [23:0] regs [2];
    wire [1:0] valid, ready;

    for (genvar mode = 0; mode < 2; mode++) begin : dut
        issue_window #(.OOO(mode != 0)) window (
            .clk, .reset, .push_valid, .push_ready(ready[mode]), .push_regs,
            .push_mask, .push_kind, .entry_ready, .accept,
            .selected_valid(valid[mode]), .selected_index(index[mode]),
            .selected_regs(regs[mode]), .selected_mask(mask[mode]),
            .selected_kind(kind[mode]), .occupancy(count[mode])
        );
    end

    task automatic tick;
        @(posedge clk);
        @(negedge clk);
    endtask

    task automatic clear;
        reset = 1;
        push_valid = 0;
        accept = 0;
        entry_ready = 0;
        tick();
        reset = 0;
        assert (count[0] == 0 && count[1] == 0) else $fatal;
    endtask

    task automatic enqueue(input logic [5:0] dst, src,
                           input logic [1:0] op, input logic [3:0] lanes);
        push_regs = {dst, 12'b0, src};
        push_kind = op;
        push_mask = lanes;
        push_valid = 1;
        tick();
        push_valid = 0;
    endtask

    task automatic check_block(input logic [5:0] older_dst, older_src,
                               younger_dst, younger_src, input logic [1:0] older_kind);
        clear();
        enqueue(older_dst, older_src, older_kind, 4'hf);
        enqueue(younger_dst, younger_src, 0, 4'hf);
        entry_ready = 4'b0010;
        #1;
        assert (valid == 0) else $fatal;
    endtask

    initial begin
        clear();
        enqueue(1, 0, 1, 4'hf);
        enqueue(2, 1, 0, 4'hf);
        enqueue(3, 4, 0, 4'b0101);
        enqueue(5, 0, 0, 4'hf);
        entry_ready = 4'b1110;
        #1;
        assert (valid == 2'b10 && index[1] == 2 && mask[1] == 4'b0101) else $fatal;
        assert (ready == 0) else $fatal;
        tick();
        assert (count[1] == 4 && index[1] == 2) else $fatal;
        accept = 1;
        enqueue(6, 0, 0, 4'ha);
        #1;
        assert (count[0] == 4 && count[1] == 4 && index[1] == 2
                && regs[1][23:18] == 5) else $fatal;
        entry_ready = 4'b1001;
        #1;
        assert (index[1] == 0 && valid == 2'b11) else $fatal;
        tick();
        accept = 0;
        entry_ready = 4'b0100;
        #1;
        assert (count[1] == 3 && index[1] == 2 && regs[1][23:18] == 6
                && mask[1] == 4'ha) else $fatal;

        check_block(1, 0, 2, 1, 1); // RAW
        check_block(1, 2, 2, 0, 0); // WAR
        check_block(1, 0, 1, 0, 0); // WAW
        check_block(1, 0, 2, 0, 2); // Ordering boundary
        clear();
        enqueue(0, 0, 0, 4'hf);
        enqueue(0, 0, 0, 4'hf);
        entry_ready = 4'b0010;
        #1;
        assert (valid == 2'b10 && index[1] == 1) else $fatal;
        $display("PASS: issue-window dependencies, ordering, masks, backpressure and refill");
        $finish;
    end
endmodule
