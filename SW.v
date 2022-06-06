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
    parameter MATCH    = 3'b010;
    parameter MISMATCH = 3'b111;
    parameter G_OPEN   = 4'b0010;
    parameter G_EXTEND = 5'b00001;

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
    reg  [5:0] i [0:15];
    reg  [5:0] j [0:15];
    reg  [5:0] delay_i [0:15];
    reg  [5:0] delay_j [0:15];
    reg  [5:0] next_i [0:15];
    reg  [5:0] next_j [0:15];
    reg  [5:0] cyc_count, next_cyc_count;

    // tables --------------------------------------------
    reg  signed [2:0] match [0:63][0:47];
    reg  signed [3:0] ins   [0:64][0:48];
    reg  signed [3:0] del   [0:64][0:48];
    reg  signed [4:0] high  [0:64][0:48];

    // new cell values -----------------------------------
    wire signed [2:0] next_match [0:15];
    wire signed [3:0] next_ins   [0:15];
    wire signed [3:0] next_del   [0:15];
    reg  signed [4:0] next_high  [0:15];

    // values for comparisons ----------------------------
    wire signed [3:0] high_ins_open [0:15];
    wire signed [3:0] high_del_open [0:15];
    wire signed [3:0] ins_ext       [0:15];
    wire signed [3:0] del_ext       [0:15];
    wire signed [4:0] high_match    [0:15];

    // for loops indices
    integer x, y, z;

    // for debugging

//------------------------------------------------------------------
// submodule
//------------------------------------------------------------------

//------------------------------------------------------------------
// combinational part
//------------------------------------------------------------------

    // compute values for comparisons --------------------
    for (integer x = 0; x <= 15; x = x + 1) begin
	assign high_ins_open[x] = high[i[x]  ][j[x]-1] - G_OPEN;
	assign high_del_open[x] = high[i[x]-1][j[x]  ] - G_OPEN;
	assign ins_ext[x]       = ins [i[x]  ][j[x]-1] - G_EXTEND;
	assign del_ext[x]       = del [i[x]-1][j[x]  ] - G_EXTEND;
	assign high_match[x] = high[delay_i[x]-1][delay_j[x]-1] + match[delay_i[x]-1][delay_j[x]-1];
    end

    // match, ins, del cell logic
    // highest cell logic is in the always block for multiple comparisons
    for (integer x = 0; x <= 15; x = x + 1) begin
        assign next_match[x] = (ref[i[x]-1] == query[j[x]-1]) ? MATCH : MISMATCH;
	assign next_ins  [x] = (high_ins_open[x] >= ins_ext[x]) ? high_ins_open[x] : ins_ext[x];
	assign next_del  [x] = (high_del_open[x] >= del_ext[x]) ? high_del_open[x] : del_ext[x];
    end

    // output --------------------------------------------
    assign next_finish = (comp_state && cyc_count == 15) ? 1 : 0;

    always @(*) begin
        // initialize ins, del, high tables --------------
	// row 0
        for (x = 1; x <= 64; x = x + 1) begin
            ins[x][0] = 4'b1001; // -7
            del[x][0] = 4'b1001;
            high[x][0] = 0;
        end
	// column 0
        for (y = 0; y <= 48; y = y + 1) begin
            ins[0][y] = 4'b1001;
            del[0][y] = 4'b1001;
            high[0][y] = 0;
        end

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
	        if (delay_i[15] == 64 && delay_j[15] == 33) // filling finished
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
		end
		next_j = j;
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
	        next_i = i;
		next_j = j;
	    end
	endcase

	// cycle count logic -----------------------------
	if ((valid && cyc_count != 63) || ((fill_state == START || comp_state) && cyc_count != 15))
	    // count for input, PE control and comparisons
	    next_cyc_count = cyc_count + 1;
	else
	    next_cyc_count = 0;

	// highest cell value logic ------------------------------
	for (x = 0; x <= 15; x = x + 1) begin
	    if (high_match[x] >= ins[delay_i[x]][delay_j[x]]) begin
                if (high_match[x] >= del[delay_i[x]][delay_j[x]]) begin
                    if (high_match[x] >= 0)
                        next_high[x] = high_match[x];
                    else
                        next_high[x] = 0;
                end
                else begin
                    if (del[delay_i[x]][delay_j[x]] >= 0)
                        next_high[x] = del[delay_i[x]][delay_j[x]];
                    else
                        next_high[x] = 0;
                end
            end
            else begin
                if (ins[delay_i[x]][delay_j[x]] >= del[delay_i[x]][delay_j[x]]) begin
                    if (ins[delay_i[x]][delay_j[x]] >= 0)
                        next_high[x] = ins[delay_i[x]][delay_j[x]];
                    else
                        next_high[x] = 0;
                end
                else begin
                    if (next_del >= 0)
                        next_high[x] = del[delay_i[x]][delay_j[x]];
                    else
                        next_high[x] = 0;
                end
            end
	end

	// output logic ----------------------------------
	// temporary max
	for (x = 0; x <= 15; x = x + 1) begin
	    if (next_high[x] > max_tmp[x]) begin
	        next_max_tmp      [x] = next_high[x];
		next_pos_ref_tmp  [x] = delay_i  [x];
		next_pos_query_tmp[x] = delay_j  [x]
	    end
	    else
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
	for (x = 1; x <= 64; x = x + 1) begin
	    for (y = 1; y <= 48; y = y + 1) begin
	        match [x-1][y-1] <= 0;
	        ins   [x][y] <= 0;
		del   [x][y] <= 0;
		high  [x][y] <= 0;
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
	i <= next_i;
	j <= next_j;
	case(fill_state)
	    WAIT: begin
	        delay_i <= delay_i;
	        delay_j <= delay_j;
	    end
	    default: begin // filling
	        delay_i <= i;
	        delay_j <= j;
	    end
	endcase
	// cells ------------------------------------------
	for (x = 1; x <= 64; x = x + 1) begin
	    for (y = 1; y <= 48; y = y + 1) begin
	        for (z = 0; z <= 15; z = z + 1) begin
		    // match, ins, del cells
		    if (x == i[z] && y == j[z]) begin
			match[x-1][y-1] <= next_match[z];
			ins  [x][y] <= next_ins[z];
			del  [x][y] <= next_del[z];
		    end
		    else begin
			match[x-1][y-1] <= match[x-1][y-1];
			ins  [x][y] <= ins[x][y];
			del  [x][y] <= del[x][y];
		    end
		    // highest cells, use delayed indices
		    if (x == delay_i[z] && y == delay_j[z])
			high[x][y] <= next_high[z];
		    else
		        high[x][y] <= high[x][y];
		end
	    end
	end
    end
    end
    
endmodule

//------------------------------------------------------------------
// end
//------------------------------------------------------------------
