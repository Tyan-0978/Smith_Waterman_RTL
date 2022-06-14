module SW #(parameter WIDTH_SCORE = 8, parameter WIDTH_POS_REF = 7, parameter WIDTH_POS_QUERY = 6)
(
    input           clk,
    input           reset,
    input           valid,
    input [1:0]     data_ref,
    input [1:0]     data_query,
    output          finish,
    output [WIDTH_SCORE - 1:0]   max,
    output [WIDTH_POS_REF - 1:0]   pos_ref,
    output [WIDTH_POS_QUERY - 1:0]   pos_query
);

//------------------------------------------------------------------
// parameter
//------------------------------------------------------------------

    // states
    //parameter RESET = 2'b00;
    //parameter INPUT = 2'b01;
    //parameter FILL  = 2'b01;
    //parameter COMP  = 2'b10
    //parameter DONE  = 2'b11;
    parameter WAIT  = 2'b00;
    parameter START = 2'b01;
    parameter CONT  = 2'b10;

    // constants
    parameter MATCH    = 2;
    parameter MISMATCH = -1;
    parameter G_OPEN   = 2;
    parameter G_EXTEND = 1;

//------------------------------------------------------------------
// reg & wire
//------------------------------------------------------------------

    // input ---------------------------------------------
    reg  [1:0] ref   [0:63];
    reg  [1:0] query [0:47];

    // output --------------------------------------------
    reg  finish;
    reg  [WIDTH_SCORE-1:0]     max;
    reg  [WIDTH_POS_REF-1:0]   pos_ref;
    reg  [WIDTH_POS_QUERY-1:0] pos_query;

    wire next_finish;
    reg  [WIDTH_SCORE-1:0]     new_max;
    reg  [WIDTH_POS_REF-1:0]   new_pos_ref;
    reg  [WIDTH_POS_QUERY-1:0] new_pos_query;

    reg  [WIDTH_SCORE-1:0]     max_tmp       [0:15];
    reg  [WIDTH_POS_REF-1:0]   pos_ref_tmp   [0:15];
    reg  [WIDTH_POS_QUERY-1:0] pos_query_tmp [0:15];

    reg  [WIDTH_SCORE-1:0]     next_max_tmp       [0:15];
    reg  [WIDTH_POS_REF-1:0]   next_pos_ref_tmp   [0:15];
    reg  [WIDTH_POS_QUERY-1:0] next_pos_query_tmp [0:15];

    // states
    reg  [1:0] fill_state, next_fill_state;
    reg        comp_state, next_comp_state; // comparison state

    // indices -------------------------------------------
    reg  [WIDTH_POS_REF  -1:0] i [0:15];
    reg  [WIDTH_POS_QUERY-1:0] j [0:15];
    wire [WIDTH_POS_REF  -1:0] i_sub1 [0:15];
    wire [WIDTH_POS_QUERY-1:0] j_sub1 [0:15];
    reg  [WIDTH_POS_REF  -1:0] delay_i [0:15];
    reg  [WIDTH_POS_QUERY-1:0] delay_j [0:15];
    wire [WIDTH_POS_REF  -1:0] delay_i_sub1 [0:15];
    wire [WIDTH_POS_QUERY-1:0] delay_j_sub1 [0:15];
    reg  [WIDTH_POS_REF  -1:0] next_i [0:15];
    reg  [WIDTH_POS_QUERY-1:0] next_j [0:15];
    reg  [5:0] cyc_count, next_cyc_count;

    // tables --------------------------------------------
    reg  signed [7:0]             match [0:63][0:47];
    reg  signed [WIDTH_SCORE-1:0] ins   [0:64][0:48];
    reg  signed [WIDTH_SCORE-1:0] del   [0:64][0:48];
    reg  signed [WIDTH_SCORE-1:0] high  [0:64][0:48];

    // new cell values -----------------------------------
    //wire signed [2:0]             next_match [0:15];
    //wire signed [WIDTH_SCORE-1:0] next_ins   [0:15];
    //wire signed [WIDTH_SCORE-1:0] next_del   [0:15];
    //reg  signed [WIDTH_SCORE-1:0] next_high  [0:15];
    reg  signed [7:0]             next_match [0:63][0:47];
    reg  signed [WIDTH_SCORE-1:0] next_ins   [0:64][0:48];
    reg  signed [WIDTH_SCORE-1:0] next_del   [0:64][0:48];
    reg  signed [WIDTH_SCORE-1:0] next_high  [0:64][0:48];

    // values for comparisons ----------------------------
    wire signed [WIDTH_SCORE-1:0] high_ins_open [0:15];
    wire signed [WIDTH_SCORE-1:0] high_del_open [0:15];
    wire signed [WIDTH_SCORE-1:0] ins_ext       [0:15];
    wire signed [WIDTH_SCORE-1:0] del_ext       [0:15];
    wire signed [WIDTH_SCORE-1:0] high_match    [0:15];

    // for loops indices
    genvar u, v, w;
    integer x, y, z;

    // signals for debugging

//------------------------------------------------------------------
// submodule
//------------------------------------------------------------------

//------------------------------------------------------------------
// combinational part
//------------------------------------------------------------------

    // debug ---------------------------------------------

    // index -1 values
    for (u = 0; u <= 15; u = u + 1) begin
        assign i_sub1[u] = i[u] - 1;
        assign j_sub1[u] = j[u] - 1;
        assign delay_i_sub1[u] = delay_i[u] - 1;
        assign delay_j_sub1[u] = delay_j[u] - 1;
    end

    // compute values for comparisons --------------------
    for (u = 0; u <= 15; u = u + 1) begin
        // highest cell value is computed in the next cycle,
	// so in some cases I use the current next_high cell value
        if (u == 0)
	    // first PE: use upper highest cell value
	    assign high_ins_open[u] = high[i[u]][j_sub1[u]] - G_OPEN;
	else
	    // other PE: use next_high cell value from previous PE
	    assign high_ins_open[u] = next_high[i[u]][j_sub1[u]] - G_OPEN;

	assign high_del_open[u] = (i[u] == 1) ? - G_OPEN : next_high[i_sub1[u]][j[u]] - G_OPEN;

	assign ins_ext[u] = ins[i[u]][j_sub1[u]] - G_EXTEND;
	assign del_ext[u] = del[i_sub1[u]][j[u]] - G_EXTEND;
	assign high_match[u] = high[delay_i_sub1[u]][delay_j_sub1[u]] + match[delay_i_sub1[u]][delay_j_sub1[u]];
    end

    // output --------------------------------------------
    assign next_finish = (comp_state && cyc_count == 15) ? 1 : 0;

    always @(*) begin
	// next state logic ------------------------------
	// table filling state
	case(fill_state)
	    WAIT: begin
	        if (cyc_count == 63) // input finished
		    next_fill_state = START;
		else
		    next_fill_state = fill_state;
	    end
	    START: begin
	        if (cyc_count == 15) // all PEs started to work
		    next_fill_state = CONT;
		else
		    next_fill_state = fill_state;
	    end
	    CONT: begin
	        if (delay_i[15] == 64 && delay_j[15] == 48) // filling finished
		    next_fill_state = WAIT;
		else
		    next_fill_state = fill_state;
	    end
	    default: next_fill_state = fill_state;
	endcase

	// comparison state
	case(comp_state)
	    0: begin
	        if (delay_i[0] == 64 && delay_j[0] == 33) // first PE finished
		    next_comp_state = 1; // start comparisons
		else
		    next_comp_state = comp_state;
	    end
	    1: begin
	        if (cyc_count == 15) // comparisons finished
		    next_comp_state = 0;
		else
		    next_comp_state = comp_state;
	    end
	    default: 
	        next_comp_state = comp_state;
	endcase

	// indices logic ---------------------------------
	case(fill_state)
	    START: begin // PE control
	        for (x = 0; x <= 15; x = x + 1) begin
		    if (x <= cyc_count + 1)
		        next_i[x] = i[x] + 1;
		    else
		        next_i[x] = 0;
		    next_j[x] = j[x];
		end
	    end
	    CONT: begin
	        for (x = 0; x <= 15; x = x + 1) begin
		    case(i[x])
		        0 : begin // PE finished
			    next_i[x] = 0;
			    next_j[x] = 0;
			end
		        64: begin // last cell of current row
			    if (j[x] > 32) begin // last cell of this PE, end PE
			        next_i[x] = 0;
			        next_j[x] = 0;
			    end
			    else begin // switch to row + 16
			        next_i[x] = 1;
			        next_j[x] = j[x] + 16;
			    end
			end
			default: begin
			    next_i[x] = i[x] + 1;
			    next_j[x] = j[x];
			end
		    endcase
		end
	    end
	    default: begin
	        for (x = 0; x <= 15; x = x + 1) begin
	            next_i[x] = i[x];
		    next_j[x] = j[x];
		end
	    end
	endcase

	// cycle count logic -----------------------------
	if ((valid && cyc_count != 63) || ((fill_state == START || comp_state) && cyc_count != 15))
	    // count for input, PE control and comparisons
	    next_cyc_count = cyc_count + 1;
	else
	    next_cyc_count = 0;

	// cell value logic ------------------------------
	// boundary conditions
	// row 0
        for (x = 1; x <= 64; x = x + 1) begin
            next_ins[x][0] = -8;
            next_del[x][0] = -8;
            next_high[x][0] = 0;
        end
	// column 0
        for (y = 0; y <= 48; y = y + 1) begin
            next_ins[0][y] = -8;
            next_del[0][y] = -8;
            next_high[0][y] = 0;
        end

        // cell update logic
	for (x = 1; x <= 64; x = x + 1) begin
	for (y = 1; y <= 48; y = y + 1) begin
	    // next match, ins, del
	    if (x == i[0] && y == j[0]) begin
	        next_match[x-1][y-1] = (ref[i[0]-1] == query[j[0]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[0] >= ins_ext[0]) ? high_ins_open[0] : ins_ext[0];
		next_del[x][y] = (high_del_open[0] >= del_ext[0]) ? high_del_open[0] : del_ext[0];
	    end
	    else if (x == i[1] && y == j[1]) begin
	        next_match[x-1][y-1] = (ref[i[1]-1] == query[j[1]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[1] >= ins_ext[1]) ? high_ins_open[1] : ins_ext[1];
		next_del[x][y] = (high_del_open[1] >= del_ext[1]) ? high_del_open[1] : del_ext[1];
	    end
	    else if (x == i[2] && y == j[2]) begin
	        next_match[x-1][y-1] = (ref[i[2]-1] == query[j[2]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[2] >= ins_ext[2]) ? high_ins_open[2] : ins_ext[2];
		next_del[x][y] = (high_del_open[2] >= del_ext[2]) ? high_del_open[2] : del_ext[2];
	    end
	    else if (x == i[3] && y == j[3]) begin
	        next_match[x-1][y-1] = (ref[i[3]-1] == query[j[3]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[3] >= ins_ext[3]) ? high_ins_open[3] : ins_ext[3];
		next_del[x][y] = (high_del_open[3] >= del_ext[3]) ? high_del_open[3] : del_ext[3];
	    end
	    else if (x == i[4] && y == j[4]) begin
	        next_match[x-1][y-1] = (ref[i[4]-1] == query[j[4]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[4] >= ins_ext[4]) ? high_ins_open[4] : ins_ext[4];
		next_del[x][y] = (high_del_open[4] >= del_ext[4]) ? high_del_open[4] : del_ext[4];
	    end
	    else if (x == i[5] && y == j[5]) begin
	        next_match[x-1][y-1] = (ref[i[5]-1] == query[j[5]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[5] >= ins_ext[5]) ? high_ins_open[5] : ins_ext[5];
		next_del[x][y] = (high_del_open[5] >= del_ext[5]) ? high_del_open[5] : del_ext[5];
	    end
	    else if (x == i[6] && y == j[6]) begin
	        next_match[x-1][y-1] = (ref[i[6]-1] == query[j[6]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[6] >= ins_ext[6]) ? high_ins_open[6] : ins_ext[6];
		next_del[x][y] = (high_del_open[6] >= del_ext[6]) ? high_del_open[6] : del_ext[6];
	    end
	    else if (x == i[7] && y == j[7]) begin
	        next_match[x-1][y-1] = (ref[i[7]-1] == query[j[7]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[7] >= ins_ext[7]) ? high_ins_open[7] : ins_ext[7];
		next_del[x][y] = (high_del_open[7] >= del_ext[7]) ? high_del_open[7] : del_ext[7];
	    end
	    else if (x == i[8] && y == j[8]) begin
	        next_match[x-1][y-1] = (ref[i[8]-1] == query[j[8]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[8] >= ins_ext[8]) ? high_ins_open[8] : ins_ext[8];
		next_del[x][y] = (high_del_open[8] >= del_ext[8]) ? high_del_open[8] : del_ext[8];
	    end
	    else if (x == i[9] && y == j[9]) begin
	        next_match[x-1][y-1] = (ref[i[9]-1] == query[j[9]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[9] >= ins_ext[9]) ? high_ins_open[9] : ins_ext[9];
		next_del[x][y] = (high_del_open[9] >= del_ext[9]) ? high_del_open[9] : del_ext[9];
	    end
	    else if (x == i[10] && y == j[10]) begin
	        next_match[x-1][y-1] = (ref[i[10]-1] == query[j[10]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[10] >= ins_ext[10]) ? high_ins_open[10] : ins_ext[10];
		next_del[x][y] = (high_del_open[10] >= del_ext[10]) ? high_del_open[10] : del_ext[10];
	    end
	    else if (x == i[11] && y == j[11]) begin
	        next_match[x-1][y-1] = (ref[i[11]-1] == query[j[11]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[11] >= ins_ext[11]) ? high_ins_open[11] : ins_ext[11];
		next_del[x][y] = (high_del_open[11] >= del_ext[11]) ? high_del_open[11] : del_ext[11];
	    end
	    else if (x == i[12] && y == j[12]) begin
	        next_match[x-1][y-1] = (ref[i[12]-1] == query[j[12]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[12] >= ins_ext[12]) ? high_ins_open[12] : ins_ext[12];
		next_del[x][y] = (high_del_open[12] >= del_ext[12]) ? high_del_open[12] : del_ext[12];
	    end
	    else if (x == i[13] && y == j[13]) begin
	        next_match[x-1][y-1] = (ref[i[13]-1] == query[j[13]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[13] >= ins_ext[13]) ? high_ins_open[13] : ins_ext[13];
		next_del[x][y] = (high_del_open[13] >= del_ext[13]) ? high_del_open[13] : del_ext[13];
	    end
	    else if (x == i[14] && y == j[14]) begin
	        next_match[x-1][y-1] = (ref[i[14]-1] == query[j[14]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[14] >= ins_ext[14]) ? high_ins_open[14] : ins_ext[14];
		next_del[x][y] = (high_del_open[14] >= del_ext[14]) ? high_del_open[14] : del_ext[14];
	    end
	    else if (x == i[15] && y == j[15]) begin
	        next_match[x-1][y-1] = (ref[i[15]-1] == query[j[15]-1]) ? MATCH : MISMATCH;
		next_ins[x][y] = (high_ins_open[15] >= ins_ext[15]) ? high_ins_open[15] : ins_ext[15];
		next_del[x][y] = (high_del_open[15] >= del_ext[15]) ? high_del_open[15] : del_ext[15];
	    end
	    else begin // not updated in this cycle
	        next_match[x-1][y-1] = match[x-1][y-1];
		next_ins[x][y] = ins[x][y];
		next_del[x][y] = del[x][y];
	    end

	    // next high
	    if (delay_i[0] == x && delay_j[0] == y) begin
	        if (high_match[0] >= ins[x][y]) begin
                    if (high_match[0] >= del[x][y]) begin
                        if (high_match[0] >= 0)
                            next_high[x][y] = high_match[0];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[1] == x && delay_j[1] == y) begin
	        if (high_match[1] >= ins[x][y]) begin
                    if (high_match[1] >= del[x][y]) begin
                        if (high_match[1] >= 0)
                            next_high[x][y] = high_match[1];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[2] == x && delay_j[2] == y) begin
	        if (high_match[2] >= ins[x][y]) begin
                    if (high_match[2] >= del[x][y]) begin
                        if (high_match[2] >= 0)
                            next_high[x][y] = high_match[2];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[3] == x && delay_j[3] == y) begin
	        if (high_match[3] >= ins[x][y]) begin
                    if (high_match[3] >= del[x][y]) begin
                        if (high_match[3] >= 0)
                            next_high[x][y] = high_match[3];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[4] == x && delay_j[4] == y) begin
	        if (high_match[4] >= ins[x][y]) begin
                    if (high_match[4] >= del[x][y]) begin
                        if (high_match[4] >= 0)
                            next_high[x][y] = high_match[4];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[5] == x && delay_j[5] == y) begin
	        if (high_match[5] >= ins[x][y]) begin
                    if (high_match[5] >= del[x][y]) begin
                        if (high_match[5] >= 0)
                            next_high[x][y] = high_match[5];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[6] == x && delay_j[6] == y) begin
	        if (high_match[6] >= ins[x][y]) begin
                    if (high_match[6] >= del[x][y]) begin
                        if (high_match[6] >= 0)
                            next_high[x][y] = high_match[6];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[7] == x && delay_j[7] == y) begin
	        if (high_match[7] >= ins[x][y]) begin
                    if (high_match[7] >= del[x][y]) begin
                        if (high_match[7] >= 0)
                            next_high[x][y] = high_match[7];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[8] == x && delay_j[8] == y) begin
	        if (high_match[8] >= ins[x][y]) begin
                    if (high_match[8] >= del[x][y]) begin
                        if (high_match[8] >= 0)
                            next_high[x][y] = high_match[8];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[9] == x && delay_j[9] == y) begin
	        if (high_match[9] >= ins[x][y]) begin
                    if (high_match[9] >= del[x][y]) begin
                        if (high_match[9] >= 0)
                            next_high[x][y] = high_match[9];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[10] == x && delay_j[10] == y) begin
	        if (high_match[10] >= ins[x][y]) begin
                    if (high_match[10] >= del[x][y]) begin
                        if (high_match[10] >= 0)
                            next_high[x][y] = high_match[10];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[11] == x && delay_j[11] == y) begin
	        if (high_match[11] >= ins[x][y]) begin
                    if (high_match[11] >= del[x][y]) begin
                        if (high_match[11] >= 0)
                            next_high[x][y] = high_match[11];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[12] == x && delay_j[12] == y) begin
	        if (high_match[12] >= ins[x][y]) begin
                    if (high_match[12] >= del[x][y]) begin
                        if (high_match[12] >= 0)
                            next_high[x][y] = high_match[12];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[13] == x && delay_j[13] == y) begin
	        if (high_match[13] >= ins[x][y]) begin
                    if (high_match[13] >= del[x][y]) begin
                        if (high_match[13] >= 0)
                            next_high[x][y] = high_match[13];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[14] == x && delay_j[14] == y) begin
	        if (high_match[14] >= ins[x][y]) begin
                    if (high_match[14] >= del[x][y]) begin
                        if (high_match[14] >= 0)
                            next_high[x][y] = high_match[14];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else if (delay_i[15] == x && delay_j[15] == y) begin
	        if (high_match[15] >= ins[x][y]) begin
                    if (high_match[15] >= del[x][y]) begin
                        if (high_match[15] >= 0)
                            next_high[x][y] = high_match[15];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
                else begin
                    if (ins[x][y] >= del[x][y]) begin
                        if (ins[x][y] >= 0)
                            next_high[x][y] = ins[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                    else begin
                        if (del[x][y] >= 0)
                            next_high[x][y] = del[x][y];
                        else
                            next_high[x][y] = 0;
                    end
                end
	    end
	    else 
	        next_high[x][y] = high[x][y];
	end
	end

	// output logic ----------------------------------
	// temporary max
	for (x = 0; x <= 15; x = x + 1) begin
	    if (next_high[delay_i[x]][delay_j[x]] > max_tmp[x] && fill_state != WAIT) begin
	        next_max_tmp      [x] = next_high[delay_i[x]][delay_j[x]];
		next_pos_ref_tmp  [x] = delay_i [x];
		next_pos_query_tmp[x] = delay_j [x];
	    end
	    else begin
	        next_max_tmp      [x] = max_tmp      [x];
		next_pos_ref_tmp  [x] = pos_ref_tmp  [x];
		next_pos_query_tmp[x] = pos_query_tmp[x];
	    end
	end

	// final max
	if (comp_state) begin
	    if (max_tmp[cyc_count] > max) begin // cycle count from 0 to 15
	        new_max       = max_tmp      [cyc_count];
	        new_pos_ref   = pos_ref_tmp  [cyc_count];
	        new_pos_query = pos_query_tmp[cyc_count];
	    end
	    else begin
	        new_max       = max;
	        new_pos_ref   = pos_ref;
	        new_pos_query = pos_query;
	    end
	end
	else begin
	    new_max       = max;
	    new_pos_ref   = pos_ref;
	    new_pos_query = pos_query;
	end
    end

//------------------------------------------------------------------
// sequential part
//------------------------------------------------------------------

    always@(posedge clk or posedge reset) begin
    if(reset) begin // reset
        fill_state <= WAIT;
	comp_state <= 0;
	cyc_count <= 0;
	// input
	for (x = 0; x <= 63; x = x + 1)
	    ref[x] <= 0;
	for (y = 0; y <= 47; y = y + 1)
	    query[y] <= 0;
	// output
	finish <= 0;
	max       <= 0;
	pos_ref   <= 0;
	pos_query <= 0;
	for (x = 0; x <= 15; x = x + 1) begin
	    max_tmp      [x] <= 0;
	    pos_ref_tmp  [x] <= 0;
	    pos_query_tmp[x] <= 0;
	end
	// indices
	for (x = 0; x <= 15; x = x + 1) begin
	    if (x == 0) // first PE
	        i[x] <= 1; 
	    else
	        i[x] <= 0; // PE with i[x] = 0 will not work
	    j[x] <= x + 1; // 1 to 16
	    delay_i[x] <= 0;
	    delay_j[x] <= 0;
	end
	// cells
	for (x = 0; x <= 63; x = x + 1) begin
	for (y = 0; y <= 47; y = y + 1) begin
	    match[x][y] = MISMATCH;
	end
	end
	for (x = 0; x <= 64; x = x + 1) begin
	for (y = 0; y <= 48; y = y + 1) begin
	    ins[x][y] = -8;
	    del[x][y] = -8;
	    high[x][y] = 0;
	end
	end
    end
    else begin // not reset
        fill_state <= next_fill_state;
	comp_state <= next_comp_state;
	cyc_count <= next_cyc_count;
        // input -----------------------------------------
	if (valid) begin
	    for (x = 0; x <= 63; x = x + 1) begin
	        if (x == cyc_count)
		    ref[x] <= data_ref;
		else
		    ref[x] <= ref[x];
	    end
	    for (y = 0; y <= 47; y = y + 1) begin
	        if (y == cyc_count)
		    query[y] <= data_query;
		else
		    query[y] <= query[y];
	    end
	end
	else begin
	    for (x = 0; x <= 63; x = x + 1)
	        ref[x] <= ref[x];
	    for (y = 0; y <= 47; y = y + 1)
	        query[y] <= query[y];
	end
	// output -----------------------------------------
	finish    <= next_finish;
	max       <= new_max;
	pos_ref   <= new_pos_ref;
	pos_query <= new_pos_query;
	for (x = 0; x <= 15; x = x + 1) begin
	    max_tmp      [x] <= next_max_tmp      [x];
	    pos_ref_tmp  [x] <= next_pos_ref_tmp  [x];
	    pos_query_tmp[x] <= next_pos_query_tmp[x];
	end
	// indices ----------------------------------------
	for (x = 0; x <= 15; x = x + 1) begin
	    i[x] <= next_i[x];
	    j[x] <= next_j[x];
	    case(fill_state)
	        WAIT: begin
		    delay_i[x] <= delay_i[x];
		    delay_j[x] <= delay_j[x];
	        end
	        default: begin // filling
		    delay_i[x] <= i[x];
		    delay_j[x] <= j[x];
	        end
	    endcase
	end
	// cells ------------------------------------------
	for (x = 0; x <= 64; x = x + 1) begin
	for (y = 0; y <= 48; y = y + 1) begin
	    match[x][y] = next_match[x][y];
	end
	end

	for (x = 0; x <= 64; x = x + 1) begin
	for (y = 0; y <= 48; y = y + 1) begin
	    ins[x][y] = next_ins[x][y];
	    del[x][y] = next_del[x][y];
	    high[x][y] = next_high[x][y];
	end 
	end
    end
    end
    
endmodule

//------------------------------------------------------------------
// end
//------------------------------------------------------------------
