--
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~~~~~~~~ k2z ~~~~~~~~~~~~~~
-- ~~~~~~~~~ by zbs ~~~~~~~~~~~~
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~ kria port native to lua ~~~
-- 0.1 ~~~~~~~~~~~~~~~~~~~~~~~~~
-- 
-- k2: reset
-- k3: play
-- k1+k2: time overlay (ansible k1)
-- k1:k3: config overlay (ansible k2)
--
-- thanks for everything, @tehn

screen_graphics = include('lib/screen_graphics')
grid_graphics = include('lib/grid_graphics')
Prms = include('lib/prms')
Onboard = include('lib/onboard')
gkeys = include('lib/gkeys')
meta = include('lib/meta')
nb = include("lib/nb/nb")
mu = require 'musicutil'


-- grid level macros
OFF=0
LOW=2
MED=5
HIGH=12

-- other globals
NUM_TRACKS = 4
NUM_PATTERNS = 16
NUM_SCALES = 16

post_buffer = 'k2z v0.1'

scale_defaults = {
	{0,2,2,1,2,2,2}
,	{0,2,1,2,2,2,1}
,	{0,1,2,2,2,1,2}
,	{0,2,2,2,1,2,2}
,	{0,2,2,1,2,2,1}
,	{0,2,1,2,2,1,2}
,	{0,1,2,2,1,2,2}
,	{0,0,1,0,1,1,1}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
}

page_ranges = {
	{0,1,0} -- trig
,	{1,7,1} -- note
,	{1,7,3} -- octave
,	{1,7,1} -- gate
,	{-1,6,1} -- retrig
,	{1,7,1} -- transpose
,	{1,7,1} -- slide
}
page_map = {
	[6] = 1
,	[7] = 2
,	[8] = 3
,	[9] = 4
,	[15] = 5
,	[16] = 6
}
page_names = {'trig', 'note', 'octave', 'gate','scale','patterns'}
alt_page_names = {'retrig', 'transpose', 'slide'}
combined_page_list = {'trig','note','octave','gate','retrig','transpose','slide','scale','patterns'}
mod_names = {'none','loop','time','prob'}
play_modes = {'forward', 'reverse', 'triangle', 'drunk', 'random'}
prob_map = {0, 25, 50, 100}
div_sync_modes = {'none','track','all'}

time_desc = {
	{	
		'all divs independent'
	},{
		'most divs independent'
	,	'trig & note divs synced'
	},{
		'divs synced in track'
	,	'but tracks independent'
	},{
		'trig & note divs synced'
	,	'other divs synced separate'
	},{
		'all divs synced'
	},{		
		'most divs globally synced'
	,	'trig & note synced separate'
	}
}
config_desc = {
	{
		'note & trig edits free'
	,	'trig & note edits synced'
	},{
		'all loops independent'
	,	'loops synced inside tracks'
	,	'all loops synced'
	}
}

loop_first = -1
loop_last = -1
wavery_light = MED
waver_dir = 1
shift = false

pulse_indicator = 1 -- todo implement
global_clock_counter = 1

kbuf = {} -- key state buffer, true/false
rbuf = {} -- render buffer, states 0-15 on all 128 positions

g = grid.connect()
m = midi.connect()

function init_grid_buffers()
	for x=1,16 do
		table.insert(kbuf,{})
		table.insert(rbuf,{})
		for y=1,8 do
			kbuf[x][y] = false -- key buffer
			rbuf[x][y] = OFF -- rendering
		end
	end
end

function post(str)
	post_buffer = str
	-- print('post:',str)
end

function intro()
	clock.sleep(2)
	post('by @zbs')
	clock.sleep(2)
	post('based on kria by @tehn')
	clock.sleep(2)
	post(':-)')
end

function key(n,d) Onboard:key(n,d) end
function enc(n,d) Onboard:enc(n,d) end
function g.key(x,y,z) gkeys:key(x,y,z) end

val_buffers = {}
function init_val_buffers()
	for i=1,NUM_TRACKS do
		table.insert(val_buffers,{})
		for k,v in ipairs(combined_page_list) do
			if v == 'scale' or v == 'patterns' then break end
			val_buffers[i][v] = 
				params:get('data_'..v..'_'..params:get('pos_'..v..'_t'..i)..'_t'..i)
		end
	end
end

function clock.transport.start() params:set('playing',1); post('play') end
function clock.transport.stop() params:set('playing',0); post('stop') end

function init()
	nb:init()
	init_grid_buffers()
	Prms:add()
	init_val_buffers()
	clock.run(visual_ticker)
	clock.run(step_ticker)
	clock.run(intro)
end

function reset()
	for t=1,NUM_TRACKS do
		for k,v in ipairs(combined_page_list) do
			if v == 'scale' or v == 'patterns' then break end
			params:set('pos_'..v..'_t'..t, params:get('loop_last_'..v..'_t'..t))
		end
	end
	pulse_indicator = 1
	post('reset')
end

function edit_divisor(track,page,new_val)
	if params:get('div_cue') == 1 then
		params:set('cued_divisor_'..page..'_t'..track,new_val)
		post('cued: '..page..' divisor: '..new_val)
	else
		params:set('divisor_'..page..'_t'..track,new_val)
		post(page..' divisor: '..new_val)
	end
end

function edit_loop(track, first, last)
	local f = math.min(first,last)
	local l = math.max(first,last)
	local p = get_page_name()

	if params:get('loop_sync') == 1 then
		if p == 'trig' or p == 'note' and params:get('note_sync') == 1 then
			params:set('loop_first_note_t'..track,f)
			params:set('loop_last_note_t'..track,l)
			params:set('loop_first_trig_t'..track,f)
			params:set('loop_last_trig_t'..track,l)
			post('t'..track..' trig & note loops: ['..f..'-'..l..']')
		else
			params:set('loop_first_'..p..'_t'..track,f)
			params:set('loop_last_'..p..'_t'..track,l)
			post('t'..track..' '..p..' loop: ['..f..'-'..l..']')
		end
	elseif params:get('loop_sync') == 2 then
		for k,v in ipairs(combined_page_list) do
			if v == 'scale' or v == 'patterns' then break end
			params:set('loop_first_'..v..'_t'..track,f)
			params:set('loop_last_'..v..'_t'..track,l)
		end
		post('t'..track..' loops: ['..f..'-'..l..']')
	elseif params:get('loop_sync') == 3 then
		for t=1,NUM_TRACKS do
			for k,v in ipairs(combined_page_list) do
				if v == 'scale' or v == 'patterns' then break end
				params:set('loop_first_'..v..'_t'..t,f)
				params:set('loop_last_'..v..'_t'..t,l)
			end
		end
		post('all loops: ['..f..'-'..l..']')
	end
end

function toggle_subtrig(track,step,subtrig)
	params:delta('data_subtrig_'..subtrig..'_step_'..step..'_t'..track,1)
	for i=params:get('data_subtrig_count_'..step..'_t'..track),1,-1 do
		if params:get('data_subtrig_'..i..'_step_'..step..'_t'..track) == 0 then
			-- print('decrementing subtrig count')
			delta_subtrig_count(track,step,-1)
		else
			break
		end
	end
end

function delta_subtrig_count(track,step,delta)
	edit_subtrig_count(track,step,params:get('data_subtrig_count_'..step..'_t'..track) + delta)
end

function edit_subtrig_count(track,step,new_val)
	params:set('data_subtrig_count_'..step..'_t'..track,new_val)
	for i=1,5 do
		if	params:get('data_subtrig_'..i..'_step_'..step..'_t'..track) == 1 and i > new_val then
			params:set('data_subtrig_'..i..'_step_'..step..'_t'..track,0)
		end
	end
	post('subtrig count s'..step..'t'..track..' '.. params:get('data_subtrig_count_'..step..'_t'..track))
end

function advance_page(t,p) -- track,page
	local old_pos = params:get('pos_'..p..'_t'..t)
	local first = params:get('loop_first_'..p..'_t'..t)
	local last = params:get('loop_last_'..p..'_t'..t)
	local mode = play_modes[params:get('playmode_t'..t)]
	local new_pos;
	local resetting = false

	if mode == 'forward' then
		new_pos = old_pos + 1
		if out_of_bounds(t,p,new_pos) then
			new_pos = first
			resetting = true
		end
	elseif mode == 'reverse' then
		new_pos = old_pos - 1
		if out_of_bounds(t,p,new_pos) then
			new_pos = last
			resetting = true
		end
	elseif mode == 'triangle' then
		local delta = params:get('pipo_dir_t'..t) == 1 and 1 or -1
		new_pos = old_pos + delta
		if out_of_bounds(t,p,new_pos) then 
			--print(delta)
			new_pos = (delta == -1) and last-1 or first+1
			print('new pos is',new_pos,'first is',first,'last is',last)
			params:delta('pipo_dir_t'..t,1)
			resetting = true
		end
	elseif mode == 'drunk' then 
		local delta
		if new_pos == first then delta = 1
		elseif new_pos == last then delta = -1
		else delta = math.random() > 0.5 and 1 or -1
		end
		new_pos = old_pos + delta
		if new_pos > last then 
			new_pos = last
		elseif new_pos < first then
			new_pos = first
		end
		-- ^ have to do it this way vs out_of_bounds() because we want to get to the closest boundary, not necessarily first or last step in loop.

	elseif mode == 'random' then 
		new_pos = util.round(math.random(first,last))
	end

	if resetting and params:get('cued_divisor_'..p..'_t'..t) ~= 0 then
		params:set('divisor_'..p..'_t'..t, params:get('cued_divisor_'..p..'_t'..t))
		params:set('cued_divisor_'..p..'_t'..t,0)
	end

	params:set('pos_'..p..'_t'..t,new_pos)
end -- todo there's something very wrong with triangle mode...

function make_scale()
	local new_scale = {0,0,0,0,0,0,0}
	local table_from_params = {}
	local output_scale = {}
	for i=1,7 do
		table.insert(table_from_params,params:get('scale_'..params:get('scale_num')..'_deg_'..i))
	end
	for i=2,7 do
		new_scale[i] = new_scale[i-1] + table_from_params[i]
	end
	return new_scale
end

function note_out(t)
	local s = make_scale()
	local n = s[current_val(t,'note')] + s[current_val(t,'transpose')]
	local up_one_octave = false
	if n > 7 then
		n = n - 7
		up_one_octave = true
	end
	n = n + 12*current_val(t,'octave')
	if up_one_octave then n = n + 12 end
	local gate_len = current_val(t,'gate') * params:get('data_gate_shift_t'..t) -- this will give you a weird range, feel free to use it however you want
	local slide_amt =  util.linlin(1,7,1,120,current_val(t,'slide')) -- to match stock kria times
	
	clock.run(note_clock,t,n,gate_len,slide_amt)
end

function note_clock(track,note,gate_len,slide_amt) 
	local player = params:lookup_param("voice_t"..track):get_player()
	local velocity = 1.0
	local pos = params:get('pos_retrig_t'..track)
	local subdivision = params:get('data_subtrig_count_'..pos..'_t'..track)
	for i=1,subdivision do
		if params:get('data_subtrig_'..i..'_step_'..pos..'_t'..track) == 1 then
			player:set_slew(slide_amt/1000)
			player:play_note(note, velocity, gate_len/subdivision)
		end
		clock.sleep((clock.get_beat_sec()/(subdivision+1))/3)
	end
end

function update_val(track,page)
	val_buffers[track][page] =
	    params:get('data_'..page..'_'..params:get('pos_'..page..'_t'..track)..'_t'..track)
	if page == 'trig' then
	    if current_val(track,'trig') == 1 then
	        note_out(track)
	    end
	end
end

function advance_all()
	global_clock_counter = global_clock_counter + 1
	if global_clock_counter > params:get('global_clock_div') then
		global_clock_counter = 1

		pulse_indicator = pulse_indicator + 1
		if pulse_indicator > 16 then pulse_indicator = 1 end
		
		for t=1,NUM_TRACKS do
			for k,v in ipairs(combined_page_list) do
				if v == 'scale' or v == 'patterns' then break end
				params:delta('data_t'..t..'_'..v..'_counter',1)
				if 		params:get('data_t'..t..'_'..v..'_counter')
					>	params:get('divisor_'..v..'_t'..t) 
				then
					params:set('data_t'..t..'_'..v..'_counter',1)
					advance_page(t,v)
					-- params:set('pos_'..v..'_t'..t,new_pos_for_track(t,v))
					if 	math.random(0,99)
					< 	prob_map[params:get('data_'..v..'_prob_'..params:get('pos_'..v..'_t'..t)..'_t'..t)]
					then
						update_val(t,v)
					end
				end
			end
		end
	end
end

function step_ticker()
	while true do
		clock.sync(1/4)
		if params:get('playing') == 1 then
			advance_all()
		end
	end
end

function visual_ticker()
	while true do
		clock.sleep(1/30)
		redraw()

		wavery_light = wavery_light + waver_dir
		if wavery_light > MED + 2 then
			waver_dir = -1
		elseif wavery_light < MED - 2 then
			waver_dir = 1
		end
		grid_graphics:render()
	end
end

function redraw()
	screen_graphics:render()
end

function at() -- get active track
	return params:get('active_track')
end

function out_of_bounds(track,p,value)
	-- returns true if value is out of bounds on page p, track
	return 	(value < params:get('loop_first_'..p..'_t'..track))
	or		(value > params:get('loop_last_'..p..'_t'..track))
end

function get_page_name()
	local p
	if params:get('alt_page') == 1 then
		p = alt_page_names[params:get('page')]
	else
		p = page_names[params:get('page')]
	end

	return p
end

function current_val(track,page)
	return val_buffers[track][page]
end

function get_mod_key()
	return mod_names[params:get('mod')]
end

function highlight(l) -- level number
	local o = 15
	if l == LOW then
		o = 3
	elseif l == MED then
		o = 7
	elseif l == HIGH then
		o = 15
	else
		o = l + 2
	end

	return util.clamp(o,0,15)
end

function dim(l) -- level number
	local o
	if l == LOW then
		o = 1
	elseif l == MED then
		o = 3
	elseif l == HIGH then
		o = 9
	else
		o = l - 1
	end

	return util.clamp(o,0,15)
end