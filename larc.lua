--
-- one record head
-- three play heads
-- arc control
--

local a = arc.connect(1)

local tau = math.pi * 2

local alt = false
local recording = false
local settings_mode = false
local pre_speed = 1
local last_arc = -1
local last_arc_time = -1
local pop_up_timeout = 1
local start_time = util.time()

local filter_options = {
  "none",
  "lowpass",
  "highpass",
  "bandpass",
  "band reject"
}

local arc_choices = {
  "amplitude",
  "speed",
  "pan",
  "cutoff"
}


-- WAVEFORMS
local interval = 0
local waveform_samples = {}
local scale = 25
local level = .75


function on_render(ch, start, i, s)
  waveform_samples = s
  interval = i
end


function update_content()
  softcut.render_buffer(1, params:get("loop_in"), params:get("loop_out") - params:get("loop_in"), 128)
end


-- softcut polls
local positions = { -1, -1, -1, -1}


local function update_positions(i, pos)
  positions[i] = pos  
end


-- keep everything inside the loop points
local function set_loop_in(v)
  if params:get("loop_out") == 0.1 then
    v = 0
  else
    v = util.clamp(v, 0, params:get("loop_out") - 0.1)
  end
  for i = 1, 4 do
    softcut.loop_start(i, v)
  end
  params:set("loop_in", v)
end


local function set_loop_out(v)
  if v == params:get("loop_in") then
    v = v + 0.1
  else
    v = util.clamp(v, params:get("loop_in") + 0.1, 16)
  end
  for i = 1, 4 do
    softcut.loop_end(i, v)
  end
  params:set("loop_out", v)
  if positions[4] >= v then
    softcut.position(4, params:get("loop_in"))
    positions[4] = params:get("loop_in")
  end
end

-- toggle recording
local function toggle_record()
  local fdbk = params:get("feedback")
  if recording then
    softcut.rec_level(4, 0)
    softcut.pre_level(4, 1)
  else
    softcut.rec_level(4, 1)
    softcut.pre_level(4, fdbk)
  end
  recording = not recording
end

-- softcut filter mode selection
local function set_filter_mode(voice, mode)
  if mode == 1 then
    -- none
    softcut.post_filter_dry(voice, 1)
    softcut.post_filter_lp(voice, 0)
    softcut.post_filter_hp(voice, 0)
    softcut.post_filter_bp(voice, 0)
    softcut.post_filter_br(voice, 0)
  elseif mode == 2 then
    -- lowpass
    softcut.post_filter_dry(voice, 0)
    softcut.post_filter_lp(voice, 1)
    softcut.post_filter_hp(voice, 0)
    softcut.post_filter_bp(voice, 0)
    softcut.post_filter_br(voice, 0)
  elseif mode == 3 then
    -- highpass
    softcut.post_filter_dry(voice, 0)
    softcut.post_filter_lp(voice, 0)
    softcut.post_filter_hp(voice, 1)
    softcut.post_filter_bp(voice, 0)
    softcut.post_filter_br(voice, 0)
  elseif mode == 4 then
    -- bandpass
    softcut.post_filter_dry(voice, 0)
    softcut.post_filter_lp(voice, 0)
    softcut.post_filter_hp(voice, 0)
    softcut.post_filter_bp(voice, 1)
    softcut.post_filter_br(voice, 0)
  elseif mode == 5 then
    -- band reject
    softcut.post_filter_dry(voice, 0)
    softcut.post_filter_lp(voice, 0)
    softcut.post_filter_hp(voice, 0)
    softcut.post_filter_bp(voice, 0)
    softcut.post_filter_br(voice, 1)
  end
end

-- remaining softcut set up
local function sc_init()
  audio.level_cut(1.0)
  audio.level_adc_cut(1)
  audio.level_eng_cut(1)
  softcut.level_slew_time(1,0.25)
  softcut.level_input_cut(1, 4, 1.0)
  softcut.level_input_cut(2, 4, 1.0)

  for i = 1, 4 do
    softcut.buffer(i, 1)
    softcut.pan(i, 0.0)
    softcut.enable(i, 1)
    softcut.level(i, i == 4 and 0 or 1.0)
    softcut.play(i, 1)
    softcut.rate(i, i == 4 and 1 or 1 / i)
    softcut.rate_slew_time(i, 0.25)
    softcut.loop_start(i, 0)
    softcut.loop_end(i, 8)
    softcut.loop(i, 1)
    softcut.fade_time(i, 0.2)
    softcut.position(i, 0)
    -- filters
    softcut.filter_dry(i, i == 4 and 1 or 0);
    softcut.filter_fc(i, 1200);
    softcut.filter_lp(i, 0);
    softcut.filter_bp(i, 0);
    softcut.filter_rq(i, 8);
   end
  -- use voice 4 for recording. records at speed == 1, no playback?
  softcut.rec(4, 1)
  softcut.rec_level(4, 0)
  softcut.pre_level(4, 0.15)
  softcut.level(4, 0)
end


function v_scale(old_value, old_min, old_max, new_min, new_max)
  -- scale ranges
  -- only used in redraw
  -- should probably use util.linlin but i couldn't get it to work
  local old_range = old_max - old_min

  if old_range == 0 then
    old_range = new_min
  end

  local new_range = new_max - new_min
  local new_value = (((old_value - old_min) * new_range) / old_range) + new_min

  return new_value
end


function init()
  -- init softcut
  sc_init()
  -- set up softcut position polls
  for i = 1, 4 do
    softcut.phase_quant(i, .001)
    softcut.event_phase(update_positions)
    softcut.poll_start_phase()
  end
  softcut.event_render(on_render)

  params:add_separator()
  
  params:add_control('loop_in', 'loop in', controlspec.new(0, 15.5, "lin", 0.01, 0))
  params:set_action('loop_in', function(v) set_loop_in(v) end)

  params:add_control('loop_out', 'loop out', controlspec.new(0.1, 16, "lin", 0.01, 8))
  params:set_action('loop_out', function(v) set_loop_out(v) end)

  params:add_control('rec_speed', 'rec speed', controlspec.new(-2, 2, "lin", 0.01, 1))
  params:set_action('rec_speed', function(v) softcut.rate(4, v) end)

  params:add_control('feedback', 'feedback', controlspec.new(0, 1, "lin", 0.01, .30))
  params:set_action('feedback', function(v) softcut.pre_level(4, v) end)
  
  params:add_option("arc_focus", "arc focus", arc_choices)
  params:hide("arc_focus")
  
  params:add_separator()
  
  for i = 1, 3 do
    params:add_group("playhead " .. i, 9)
    params:add_control(i .. "amp", i .. " amp", controlspec.new(0, 1, "lin", 0, i == 1 and .5 or 0))
    params:set_action(i .. "amp", function(v) softcut.level(i, v) end)

    params:add_control(i .. "speed", i .. " speed", controlspec.new(-2, 2, "lin", 0, 1/i))
    params:set_action(i .. "speed", function(v) softcut.rate(i, v) end)

    -- tape speed slew controls
    params:add_control(i .. "speed_slew", i .. " speed slew", controlspec.new(0, 1, "lin", 0, 0.1, ""))
    params:set_action(i .. "speed_slew", function(x) softcut.rate_slew_time(i, x) end)

    params:add_control(i .. "pan", i .. " pan", controlspec.new(-1, 1, "lin", 0.01, 0))
    params:set_action(i .. "pan", function(v) softcut.pan(i, v) end)
    
    params:add_control(i .. "pan_slew", i.. " pan slew", controlspec.new(0, 1, "lin", 0.01, 0, ""))
    params:set_action(i .. "pan_slew", function(x) softcut.pan_slew_time(i, x) end)
    -- filter mode
    params:add_option(i .. "filter_mode", i .. " filter mode", filter_options, 2)
    params:set_action(i .. "filter_mode", function(v) set_filter_mode(i, v) end)
    -- filter cut off
    params:add_control(i .. "filter_cutoff", i .. " filter cutoff", controlspec.new(10, 12000, 'exp', 1, 12000, "Hz"))
    params:set_action(i .. "filter_cutoff", function(x) softcut.post_filter_fc(i, x) softcut.pre_filter_fc(i, x) end)
    -- filter q
    params:add_control(i .. "filter_q", i .. " filter q", controlspec.new(0.0005, 8.0, 'exp', 0, 8.0, ""))
    params:set_action(i .. "filter_q", function(x) softcut.post_filter_rq(i, x) softcut.pre_filter_rq(i, x) end)
    -- dry signal
    params:add_control(i .. "dry_signal", i .. " dry signal", controlspec.new(0, 1, 'lin', 0, 0.1, ""))
    params:set_action(i .. "dry_signal", function(x) softcut.pre_filter_dry(i, x) softcut.post_filter_dry(i, x) end)
    
  end

  params:bang()

  local arc_redraw_timer = metro.init()
  arc_redraw_timer.time = 1/30
  arc_redraw_timer.event = function() arc_redraw() end
  arc_redraw_timer:start()

  local redraw_timer = metro.init()
  redraw_timer.time = 1/30
  redraw_timer.event = function() redraw() end
  redraw_timer:start()
end


-- norns hardware
function key(n, z)
  if n == 1 then alt = z == 1 and true or false end
  if n == 2 and z == 1 then 
    if alt then 
      softcut.buffer_clear()
    else
      settings_mode = not settings_mode
    end
  end
  if n == 3 and z == 1 then toggle_record() end
end


function enc(n, d)
  last_arc_time = pop_up_timeout + 1
  if settings_mode then
    -- feedback, loop start, loop end
    if n == 1 then
      if alt then
        params:delta("rec_speed", d)
      else
        params:delta("feedback", d)
      end
    elseif n == 2 then
      params:delta("loop_in", d)
    elseif n == 3 then
      params:delta("loop_out", d)
    end
  else
    -- follow arc focus
  end
  last_enc_ = n
  last_enc_time = util.time()
end


-- arc
function a.delta(n, d)
  last_enc_time = pop_up_timeout + 1
  local focus = params:get("arc_focus")
  if settings_mode then
    if n == 1 then
      if alt then
        params:delta("rec_speed", d / 100)
      else
        params:delta("feedback", d / 10)
      end
    elseif n == 2 then
      params:delta("loop_in", d / 100)
    elseif n == 3 then
      params:delta("loop_out", d / 100)
    elseif n == 4 then
      params:delta("loop_in", d / 100)
      params:delta("loop_out", d / 100)
    end
  else
    if alt then
      params:set("arc_focus", n)
    else
      if focus == 1 and n < 4 then
        -- amplitude
        params:delta(n .. "amp", d/10)
      elseif focus == 2 then
        -- speed
        if n == 4 then
          if alt then d = d/10000 else d = d/500 end
          -- select a pre_speed value
          pre_speed = util.clamp(pre_speed + d, 0.0000, 2.0000)
        else
          -- set voice speed to pre_speed on touched ring/voice
          if d > 0 then
            params:set(n .. 'speed', pre_speed)
          else
            params:set(n .. 'speed', -pre_speed)
          end
        end
      -- panning
      elseif focus == 3 then
        d = d/10
        if n <= 3 then
          params:delta(n .. "pan", d)
        elseif n == 4 then
          
        end
      elseif focus == 4 then
        d = d/20
        -- cutoff
        if n <= 3 then
          params:delta(n .. "filter_cutoff", d)
        else
          -- ring 4
        end
      end
    end
  end
  last_arc = n
  last_arc_time = util.time()
end


local function arc_draw_amp(bool)
  if bool then
    for i = 1, 3 do
      a:segment(i, util.degs_to_rads(180), util.degs_to_rads(util.linlin(0, 1, 0, 359, params:get(i .. "amp")) - 180), 15)
    end
  else
    a:segment(1, util.degs_to_rads(180), util.degs_to_rads(360), 15)
  end
end


local function arc_draw_speed(bool)
  -- if true, draw speed as the arc focus
  -- if false, draw one speed ring to be the focus selector
  if bool then
    for i = 1, 3 do
      a:segment(i, positions[i] * tau/params:get("loop_out"), tau * positions[i]/params:get("loop_out") + 0.2, 15)
    end
    local r = util.linlin(0, 2, 0, tau - 0.4, pre_speed)
    a:segment(4, math.pi + 0.2, (math.pi + 0.2) + r, 5)
    a:led(4, 0, 15)
    a:led(4, 30, 15)
    a:led(4, 42, 15)
    a:led(4, 49, 15)
  else
    -- arc focus selection thing
    a:segment(2, positions[1] * tau/params:get("loop_out"), tau * positions[1]/params:get("loop_out") + 0.2, 15)
  end
end


local function arc_draw_pan(bool)
  -- if true, draw panning as the arc focus
  if bool then
    for i = 1, 3 do
      local r = (util.linlin( -1, 1, -2, 2, params:get(i .. "pan")))
      a:segment(i, r - .3, r + 0.4 , 8)
      a:led(i, 41, 15)
      a:led(i, 1, 15)
      a:led(i, 25, 15)
    end
  else
    local r = util.linlin(-1, 1, -2, 2, 0)
    a:segment(3, r - .3, r + 0.4 , 8)
    a:led(3, 41, 15)
    a:led(3, 1, 15)
    a:led(3, 25, 15)
  end
end


local function arc_draw_cutoff(bool)
  if bool then
    for i = 1, 3 do
      a:segment(i, util.degs_to_rads(270), util.degs_to_rads(util.linlin(10, 12000, 0, 180, params:get(i .. "filter_cutoff")) - 90), 15)
    end
  else
    a:segment(4, util.degs_to_rads(270), util.degs_to_rads(33), 15)
  end
end



function arc_redraw()
  a:all(0)
  local focus = params:get("arc_focus")
  -- rings 1-3: 
  --for i = 1, 3 do
  if alt and not settings_mode then
    arc_draw_amp(false)
    arc_draw_speed(false)
    arc_draw_pan(false)
    arc_draw_cutoff(false)
  elseif not settings_mode then
    if focus == 1 then
      arc_draw_amp(true)
    elseif focus == 2 then
      arc_draw_speed(true)
    elseif focus == 3 then
      arc_draw_pan(true)
    elseif focus == 4 then
      arc_draw_cutoff(true)
    end
  else
    -- settings mode
    
  end
  
  a:refresh()
end


-- for making window things
local function window(x, y, w, h, header)
  if not header then header = " --- " end
  -- draw a popup window
  screen.blend_mode(0)
  screen.level(0)
  screen.rect(x , y - 1, w  , h - 1 ) -- border
  screen.stroke()
  screen.blend_mode(6)
  screen.rect(x + 1, y, w + 1, h + 1) -- make it float
  screen.fill()
  screen.stroke()
  screen.blend_mode(0)
  screen.level(10)
  screen.rect(x + 1, y, w - 1, h - 3) -- window
  screen.stroke()

  screen.level(10)
  screen.rect(x, y , w - 1 , 8) -- title bar
  screen.fill()
  screen.stroke()
    
  screen.level(0)
  screen.move(x + (w / 2), y + 6)
  screen.text_center(header) -- title

end


local function draw_amp()
  window(8, 15, 40, 25, "amp 1")
  window(40, 34, 40, 25, "amp 2")
  window(84, 30, 40, 25, " amp 3")
  screen.level(8)
  screen.move(28, 32)
  screen.text_center(params:get("1amp"))
  screen.move(60, 51)
  screen.text_center(params:get("2amp"))
  screen.move(105, 47)
  screen.text_center(params:get("3amp"))
end


local function draw_speed()
  window(17, 14, 55, 45, "cur-speed")
  window(68, 37, 50, 25, "pre-speed")
  screen.level(8)
  screen.move(29, 32)
  screen.text("1: " .. string.format("%.3f", params:get("1speed")))
  screen.move(29, 42)
  screen.text("2: " .. string.format("%.3f", params:get("2speed")))
  screen.move(29, 52)
  screen.text("3: " .. string.format("%.3f", params:get("3speed")))
  screen.move(92, 55)
  screen.text_center(string.format("%.3f", pre_speed))
end


local function draw_pan()
  window(10, 14, 90, 32, "panning")
  screen.level(8)
  screen.move(25, 34)
  screen.text_center(string.format("%.2f", params:get("1pan")))
  screen.move(55, 34)
  screen.text_center(string.format("%.2f",params:get("2pan")))
  screen.move(85, 34)
  screen.text_center(string.format("%.2f",params:get("3pan")))
end


local function draw_cutoff()
  window(8, 12, 42, 30, "cutoff 1")
  window(45, 24, 42, 30, "cutoff 2")
  window(82, 36, 42, 30, "cutoff 3")
  screen.level(8)
  screen.move(30, 32)
  screen.text_center(params:get("1filter_cutoff"))
  screen.move(65, 44)
  screen.text_center(params:get("2filter_cutoff"))
  screen.move(103, 55)
  screen.text_center(params:get("3filter_cutoff"))
end


function redraw()
  -- update waveform content
  update_content()
  local loop_in = params:get("loop_in")
  local loop_out = params:get("loop_out")
  -- start drawing stuff
  screen.clear()
  screen.level(6)
  screen.font_size(8)
  screen.font_face(0)
  -- top of screen. recording/looping indicator and record head position
  screen.move (2, 10) -- recording or looping 
  screen.text(recording and "R" or "L")
  screen.move(126, 8) -- record head position
  screen.text_right(string.format("%.2f", positions[4]))
  -- wave drawing
  screen.level(8)
  local x_pos = 0
  for i,s in ipairs(waveform_samples) do
    local height = util.round(math.abs(s) * (scale*level))
    screen.move(v_scale(0, loop_out - loop_in, 0, 126, x_pos), 35 - height)
    screen.line_rel(0, 2 * height)
    screen.stroke()
    x_pos = x_pos + 1 
  end
  -- play head positions
  for i = 1, 3 do
    if params:get(i .. "amp") > 0 then
      screen.level(params:get(i .. "amp") == 0 and 1 or 5)
      screen.move(util.linlin(loop_in, loop_out, 1, 126, positions[i]), 16)
      screen.line_rel(0, 40)
      screen.move_rel(-2, 8)
      screen.text(i)
      screen.stroke()
    end
  end
  -- settings mode
  -- feedback, loop start/end, panning, and record head speed
  if settings_mode then
    window(15, 12, 35, 20, "fdbk")
    window(55, 13, 60, 30, "loop")
    screen.level(8)
    screen.move(31, 27)
    screen.text_center(params:get("feedback"))
    screen.move(85, 29)
    screen.text_center("in: " .. loop_in)
    screen.move(85, 37)
    screen.text_center("out: " .. loop_out)
    screen.move(68, 56)

    if alt then
      window(6, 24, 50, 30, "rec speed")
      screen.move(30, 45)
      screen.level(8)
      screen.font_size(16)
      screen.text_center(params:get("rec_speed"))
    end
  else
    -- "regular" mode
    -- draw amp popups when encoders are touched
    if alt then
      window(30, 30, 75, 30, "arc focus")
      screen.move(66, 49)
      screen.level(8)
      screen.text_center(arc_choices[params:get("arc_focus")])
      last_arc_time = pop_up_timeout
    end
      -- popups
    if util.time() - last_arc_time < pop_up_timeout then
      local focus = params:get("arc_focus")
      if focus == 1 then
        -- amp
        draw_amp()
      elseif focus == 2 then
        -- speed
        draw_speed()
      elseif focus == 3 then
        -- pan
        draw_pan()
      elseif focus == 4 then
        -- cutoff
        draw_cutoff()
      end
    end
  end
  -- splash screen type logo thing
  if util.time() - start_time < 1.5 then
    screen.clear()
    screen.font_size(32)
    screen.level(4)
    screen.move(64, 42)
    screen.font_face(50)
    screen.text_center("larc")
  end
  screen.update()
end
