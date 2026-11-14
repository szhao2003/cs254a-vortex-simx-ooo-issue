module issue_window #(
    parameter bit OOO = 1'b0
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        push_valid,
    output logic        push_ready,
    input  logic [23:0] push_regs,
    input  logic [3:0]  push_mask,
    input  logic [1:0]  push_kind,
    input  logic [3:0]  entry_ready,
    input  logic        accept,
    output logic        selected_valid,
    output logic [1:0]  selected_index,
    output logic [23:0] selected_regs,
    output logic [3:0]  selected_mask,
    output logic [1:0]  selected_kind,
    output logic [2:0]  occupancy
);
    localparam logic [1:0] ALU = 2'd0, LOAD = 2'd1;
    logic [29:0] entries [0:3];
    logic [3:0] eligible;
    logic pop, push;

    // Three sources occupy the low 18 bits. Zero denotes no dependency.
    function automatic logic reads_reg(input logic [17:0] sources,
                                       input logic [5:0] reg_id);
        reads_reg = reg_id != 0 && (sources[5:0] == reg_id
                 || sources[11:6] == reg_id || sources[17:12] == reg_id);
    endfunction

    // Readiness is indexed by current queue position. Selection is recomputed
    // each cycle and consumed only when accept and selected_valid are high.
    always_comb begin
        eligible = '0;
        for (int i = 0; i < 4; i++) begin
            eligible[i] = i < int'(occupancy) && entry_ready[i];
            if (i != 0) begin
                eligible[i] &= OOO && entries[i][29:28] == ALU;
                for (int j = 0; j < i; j++) begin
                    eligible[i] &= (entries[j][29:28] == ALU || entries[j][29:28] == LOAD)
                        && !reads_reg(entries[i][17:0], entries[j][23:18])
                        && !reads_reg(entries[j][17:0], entries[i][23:18])
                        && !(entries[i][23:18] != 0 && entries[i][23:18] == entries[j][23:18]);
                end
            end
        end
        selected_valid = |eligible;
        selected_index = eligible[0] ? 2'd0 : eligible[1] ? 2'd1 : eligible[2] ? 2'd2 : 2'd3;
        {selected_kind, selected_mask, selected_regs} = entries[selected_index];
    end

    assign pop = selected_valid && accept;
    assign push_ready = occupancy < 4 || pop;
    assign push = push_valid && push_ready;

    always_ff @(posedge clk) begin
        if (reset) begin
            occupancy <= 0;
        end else begin
            occupancy <= occupancy + {2'b0, push} - {2'b0, pop};
            for (int i = 0; i < 4; i++) begin
                if (push && i == int'(occupancy) - int'(pop))
                    entries[i] <= {push_kind, push_mask, push_regs};
                else if (pop && i >= int'(selected_index) && i < 3)
                    entries[i] <= entries[(i + 1) % 4];
            end
        end
    end
endmodule
