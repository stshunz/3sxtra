--[[
  FBNeo Replay Input Dumper v3.1
  ==============================

  Captures P1/P2 inputs and full game state during Fightcade/FBNeo
  replay playback.

  Features:
  - Automatic replay detection via emu.isreplay()
  - Bit-packed input serialization (matches rl_bridge.h format)
  - Full game-state observation: HP, meter, stun, positions, parry,
    charge timers, animation IDs, RNG seeds, etc.
  - Game state machine (MENU → INTRO → PLAYING → ROUND_END)
  - Auto-save with matchup-based filenames
  - Outputs CSV for training / parity analysis
  - Batch-processing support (auto-turbo, auto-exit)

  Usage:
  1. Load a replay in Fightcade/FBNeo
  2. Load this script (Game > Lua Scripting > New Lua Script Window)
  3. Script auto-detects replay and starts capturing
  4. Press F12 to force-save, or wait for replay end

  Output:
  - CSV: frame, p1_input, p2_input, full game state columns
]]--

print("============================================")
print("  FBNeo Replay Input Dumper v3.1")
print("  SF3:3S Input Capture")
print("============================================")

-- Configuration
local CONFIG = {
    output_dir = "",                 -- Empty = same directory as script
    auto_save_on_end = true,
    turbo_mode = true,               -- F1 toggles turbo speed
    auto_turbo = true,               -- Auto-enable turbo on start (batch processing)
    auto_exit_on_end = true,         -- Exit emulator when replay ends (batch processing)
    write_status_file = true,        -- Write status file for orchestration
    show_hud = true,
}

-- SF3:3S Memory Addresses
local GAME_ADDRS = {
    -- Match/Round state
    timer = 0x2011377,
    match_state_byte = 0x020154A7,   -- 0x02 = round active, players can move
    p1_locked = 0x020154C6,          -- 0xFF when in match
    p2_locked = 0x020154C8,
    frame_number = 0x02007F00,       -- Global frame counter

    -- Player object bases
    p1_base = 0x02068C6C,
    p2_base = 0x02069104,

    -- Offsets from player base
    pos_x_off = 0x64,
    pos_y_off = 0x68,
    char_id_off = 0x3C0,
    action_off = 0xAC,
    animation_off = 0x202,
    anim_frame_off = 0x21A,
    posture_off = 0x20E,             -- Standing/crouch/jump/knockdown
    recovery_off = 0x187,            -- Frames until recoverable
    recovery_flag_off = 0x3B,        -- Recovery flag
    freeze_off = 0x45,               -- Hitstop/freeze frames remaining
    attacking_off = 0x428,
    attacking_ext_off = 0x429,       -- Extended attacking flag
    thrown_off = 0x3CF,
    blocking_off = 0x3D3,
    hit_count_off = 0x189,
    standing_state_off = 0x297,      -- Ground/air state
    movement_type2_off = 0x0AF,      -- Basic movement state
    busy_off = 0x3D1,
    input_capacity_off = 0x46C,
    velocity_off = 0x1AC,
    throw_countdown_off = 0x434,
    action_count_off = 0x459,
    damage_bonus_off = 0x43A,        -- word
    stun_bonus_off = 0x43E,          -- word
    defense_bonus_off = 0x440,       -- word

    -- Direct addresses
    p1_health = 0x2068D0B,           -- Max 0xA0 (160)
    p2_health = 0x20691A3,
    p1_direction = 0x2068C76,        -- 0=left, 1=right
    p2_direction = 0x2068C77,

    -- Meter
    p1_meter = 0x020695BF,
    p2_meter = 0x020695EB,
    p1_meter_gauge = 0x020695B5,
    p2_meter_gauge = 0x020695E1,
    p1_meter_max = 0x020695BD,
    p2_meter_max = 0x020695E9,

    -- Stun (derived from stun_max: +2=timer, +6=bar)
    p1_stun_max = 0x020695F7,
    p1_stun_timer = 0x020695F9,
    p1_stun_bar = 0x020695FD,
    p2_stun_max = 0x0206960B,
    p2_stun_timer = 0x0206960D,
    p2_stun_bar = 0x02069611,

    -- Combo counters (absolute, NOT offsets)
    p1_combo_count = 0x020696C5,
    p2_combo_count = 0x0206961D,

    -- SA Selection (value + 1 = SA number)
    p1_sa = 0x0201138B,
    p2_sa = 0x0201138C,

    -- Parry timing
    p1_parry_fwd_validity = 0x02026335,
    p1_parry_fwd_cooldown = 0x02025731,
    p1_parry_down_validity = 0x02026337,
    p1_parry_down_cooldown = 0x0202574D,
    p2_parry_fwd_validity = 0x0202673B,
    p2_parry_fwd_cooldown = 0x02025D51,
    p2_parry_down_validity = 0x0202673D,
    p2_parry_down_cooldown = 0x02025D6D,

    -- Charge move timers (character-specific)
    p1_charge_1 = 0x02025A49,
    p1_charge_2 = 0x02025A2D,
    p1_charge_3 = 0x020259D9,
    p2_charge_1 = 0x02025FF9,
    p2_charge_2 = 0x02026031,
    p2_charge_3 = 0x02026069,

    -- Screen position
    screen_x = 0x02026CB0,
    screen_y = 0x02026CB4,
}

-- CPS3 RNG addresses (confirmed via differential memory scan)
-- Random_ix16 = 0x020155E8 (CONFIRMED: stays in [0,63], wraps at 64)
-- TODO: ix32, ix16_ex, ix32_ex are NOT adjacent — need wider scan
local RNG_ADDRS = {
    ix16    = 0x020155E8,  -- CONFIRMED Random_ix16
    stage   = 0x0201138A,
}

-- Memory read helpers (FBNeo Lua API)
local rb  = memory.readbyte
local rw  = function(addr) return memory.readword(addr) end
local rww = function(addr) return memory.readword(addr) end  -- word from offset (same API)
local rws = memory.readwordsigned
local rd  = memory.readdword

-- Read complete game state
local function read_game_state()
    local p1b = GAME_ADDRS.p1_base
    local p2b = GAME_ADDRS.p2_base

    -- Match state detection
    local match_state_byte = rb(GAME_ADDRS.match_state_byte)
    local p1_locked = rb(GAME_ADDRS.p1_locked)
    local p2_locked = rb(GAME_ADDRS.p2_locked)
    local is_in_match = ((p1_locked == 0xFF or p2_locked == 0xFF) and match_state_byte == 0x02)

    return {
        -- Match/Round state
        match_state = match_state_byte,
        is_in_match = is_in_match and 1 or 0,

        -- Core state
        timer = rb(GAME_ADDRS.timer),
        frame_num = rd(GAME_ADDRS.frame_number),

        -- Health
        p1_hp = rb(GAME_ADDRS.p1_health),
        p2_hp = rb(GAME_ADDRS.p2_health),

        -- Positions
        p1_x = rws(p1b + GAME_ADDRS.pos_x_off),
        p1_y = rws(p1b + GAME_ADDRS.pos_y_off),
        p2_x = rws(p2b + GAME_ADDRS.pos_x_off),
        p2_y = rws(p2b + GAME_ADDRS.pos_y_off),

        -- Facing
        p1_facing = rb(GAME_ADDRS.p1_direction),
        p2_facing = rb(GAME_ADDRS.p2_direction),

        -- Meter
        p1_meter = rb(GAME_ADDRS.p1_meter),
        p2_meter = rb(GAME_ADDRS.p2_meter),
        p1_meter_gauge = rb(GAME_ADDRS.p1_meter_gauge),
        p2_meter_gauge = rb(GAME_ADDRS.p2_meter_gauge),

        -- Stun
        p1_stun_bar = rb(GAME_ADDRS.p1_stun_bar),
        p2_stun_bar = rb(GAME_ADDRS.p2_stun_bar),
        p1_stun_timer = rb(GAME_ADDRS.p1_stun_timer),
        p2_stun_timer = rb(GAME_ADDRS.p2_stun_timer),

        -- Combo counters (absolute addresses)
        p1_combo_count = rb(GAME_ADDRS.p1_combo_count),
        p2_combo_count = rb(GAME_ADDRS.p2_combo_count),

        -- Character IDs
        p1_char = rw(p1b + GAME_ADDRS.char_id_off),
        p2_char = rw(p2b + GAME_ADDRS.char_id_off),

        -- SA Selection (1-indexed)
        p1_sa = rb(GAME_ADDRS.p1_sa) + 1,
        p2_sa = rb(GAME_ADDRS.p2_sa) + 1,

        -- Action/Animation
        p1_action = rd(p1b + GAME_ADDRS.action_off),
        p2_action = rd(p2b + GAME_ADDRS.action_off),
        p1_animation = rw(p1b + GAME_ADDRS.animation_off),
        p2_animation = rw(p2b + GAME_ADDRS.animation_off),
        p1_anim_frame = rw(p1b + GAME_ADDRS.anim_frame_off),
        p2_anim_frame = rw(p2b + GAME_ADDRS.anim_frame_off),

        -- Essential state
        p1_posture = rb(p1b + GAME_ADDRS.posture_off),
        p2_posture = rb(p2b + GAME_ADDRS.posture_off),
        p1_recovery = rb(p1b + GAME_ADDRS.recovery_off),
        p2_recovery = rb(p2b + GAME_ADDRS.recovery_off),
        p1_recovery_flag = rb(p1b + GAME_ADDRS.recovery_flag_off),
        p2_recovery_flag = rb(p2b + GAME_ADDRS.recovery_flag_off),
        p1_attacking = rb(p1b + GAME_ADDRS.attacking_off),
        p2_attacking = rb(p2b + GAME_ADDRS.attacking_off),
        p1_attacking_ext = rb(p1b + GAME_ADDRS.attacking_ext_off),
        p2_attacking_ext = rb(p2b + GAME_ADDRS.attacking_ext_off),
        p1_movement_type2 = rb(p1b + GAME_ADDRS.movement_type2_off),
        p2_movement_type2 = rb(p2b + GAME_ADDRS.movement_type2_off),

        -- Combat state
        p1_freeze = rb(p1b + GAME_ADDRS.freeze_off),
        p2_freeze = rb(p2b + GAME_ADDRS.freeze_off),
        p1_thrown = rb(p1b + GAME_ADDRS.thrown_off),
        p2_thrown = rb(p2b + GAME_ADDRS.thrown_off),
        p1_blocking = rb(p1b + GAME_ADDRS.blocking_off),
        p2_blocking = rb(p2b + GAME_ADDRS.blocking_off),
        p1_combo = rb(p1b + GAME_ADDRS.hit_count_off),
        p2_combo = rb(p2b + GAME_ADDRS.hit_count_off),
        p1_standing = rb(p1b + GAME_ADDRS.standing_state_off),
        p2_standing = rb(p2b + GAME_ADDRS.standing_state_off),

        -- Parry timing
        p1_parry_fwd = rb(GAME_ADDRS.p1_parry_fwd_validity),
        p1_parry_down = rb(GAME_ADDRS.p1_parry_down_validity),
        p2_parry_fwd = rb(GAME_ADDRS.p2_parry_fwd_validity),
        p2_parry_down = rb(GAME_ADDRS.p2_parry_down_validity),

        -- Charge timers
        p1_charge1 = rb(GAME_ADDRS.p1_charge_1),
        p1_charge2 = rb(GAME_ADDRS.p1_charge_2),
        p1_charge3 = rb(GAME_ADDRS.p1_charge_3),
        p2_charge1 = rb(GAME_ADDRS.p2_charge_1),
        p2_charge2 = rb(GAME_ADDRS.p2_charge_2),
        p2_charge3 = rb(GAME_ADDRS.p2_charge_3),

        -- Velocity / busy / input capacity
        p1_velocity = rws(p1b + GAME_ADDRS.velocity_off),
        p2_velocity = rws(p2b + GAME_ADDRS.velocity_off),
        p1_busy = rb(p1b + GAME_ADDRS.busy_off),
        p2_busy = rb(p2b + GAME_ADDRS.busy_off),
        p1_input_cap = rb(p1b + GAME_ADDRS.input_capacity_off),
        p2_input_cap = rb(p2b + GAME_ADDRS.input_capacity_off),

        -- Throw / action count
        p1_throw_countdown = rb(p1b + GAME_ADDRS.throw_countdown_off),
        p2_throw_countdown = rb(p2b + GAME_ADDRS.throw_countdown_off),
        p1_action_count = rb(p1b + GAME_ADDRS.action_count_off),
        p2_action_count = rb(p2b + GAME_ADDRS.action_count_off),

        -- Damage / stun / defense bonuses (word-sized)
        p1_dmg_bonus = rww(p1b + GAME_ADDRS.damage_bonus_off),
        p2_dmg_bonus = rww(p2b + GAME_ADDRS.damage_bonus_off),
        p1_stun_bonus = rww(p1b + GAME_ADDRS.stun_bonus_off),
        p2_stun_bonus = rww(p2b + GAME_ADDRS.stun_bonus_off),
        p1_def_bonus = rww(p1b + GAME_ADDRS.defense_bonus_off),
        p2_def_bonus = rww(p2b + GAME_ADDRS.defense_bonus_off),

        -- Screen scroll
        screen_x = rws(GAME_ADDRS.screen_x),
        screen_y = rws(GAME_ADDRS.screen_y),

        -- RNG (confirmed ix16) + stage
        rng_16  = rw(RNG_ADDRS.ix16),
        stage   = rb(RNG_ADDRS.stage),
    }
end

-- Character ID → name mapping
local CHAR_NAMES = {
    [0] = "Gill", [1] = "Alex", [2] = "Ryu", [3] = "Yun", [4] = "Dudley",
    [5] = "Necro", [6] = "Hugo", [7] = "Ibuki", [8] = "Elena", [9] = "Oro",
    [10] = "Yang", [11] = "Ken", [12] = "Sean", [13] = "Urien", [14] = "Akuma",
    [15] = "Q", [16] = "ChunLi", [17] = "Makoto", [18] = "Twelve", [19] = "Remy",
}

local function get_char_name(id)
    return CHAR_NAMES[id] or string.format("Char%d", id)
end

-- Find next available file number for a matchup
local function get_next_file_number(base_path)
    local num = 1
    while true do
        local test_path = string.format("%s_%03d_full.csv", base_path, num)
        local f = io.open(test_path, "r")
        if f then
            f:close()
            num = num + 1
        else
            return num
        end
    end
end

-- Captured frame storage
local captured = {}

-- =============================================================================
-- GAME STATE MACHINE
-- Tracks: MENU → FIGHT_INTRO → PLAYING → ROUND_END → cycle
-- Timer=99 + full HP = new round intro
-- Timer 1-98 with valid HP = active gameplay
-- HP=0 or Timer=0 = round ended (KO or timeout)
-- =============================================================================

local PHASE_MENU = 1
local PHASE_FIGHT_INTRO = 2
local PHASE_PLAYING = 3
local PHASE_ROUND_END = 4

local current_phase = PHASE_MENU
local prev_timer = 0
local rounds_seen = 0
local match_num = 1
local menu_frames = 0
local MAX_HP = 160  -- 0xA0
local timer_started_counting = false

-- Win tracking (SF3 is best-of-3 rounds per game)
local p1_wins = 0
local p2_wins = 0
local last_valid_hp = {p1 = MAX_HP, p2 = MAX_HP}

local function get_game_phase()
    local timer = rb(GAME_ADDRS.timer)
    local p1_hp = rb(GAME_ADDRS.p1_health)
    local p2_hp = rb(GAME_ADDRS.p2_health)
    local hp_valid = (p1_hp <= MAX_HP) and (p2_hp <= MAX_HP)

    -- Timer 1-98, valid HP, both alive = active gameplay
    if timer >= 1 and timer <= 98 and hp_valid and p1_hp > 0 and p2_hp > 0 then
        return PHASE_PLAYING, timer, p1_hp, p2_hp, true
    end

    -- Timer=99, full HP = FIGHT! intro
    if timer == 99 and hp_valid and p1_hp >= MAX_HP and p2_hp >= MAX_HP then
        return PHASE_FIGHT_INTRO, timer, p1_hp, p2_hp, false
    end

    -- Timer=99, HP damaged but both alive = combat started at T=99 edge
    if timer == 99 and hp_valid and (p1_hp < MAX_HP or p2_hp < MAX_HP) and p1_hp > 0 and p2_hp > 0 then
        return PHASE_PLAYING, timer, p1_hp, p2_hp, true
    end

    -- Valid HP, someone has 0 HP = KO
    if timer >= 1 and timer <= 99 and hp_valid and (p1_hp == 0 or p2_hp == 0) then
        return PHASE_ROUND_END, timer, p1_hp, p2_hp, false
    end

    -- Timer=0, valid HP, both alive = timeout
    if timer == 0 and hp_valid and p1_hp > 0 and p2_hp > 0 then
        return PHASE_ROUND_END, timer, p1_hp, p2_hp, false
    end

    -- Everything else = menu / transition
    return PHASE_MENU, timer, p1_hp, p2_hp, false
end

local function update_game_phase()
    local new_phase, timer, p1_hp, p2_hp, live = get_game_phase()

    -- Detect gameplay-active moment via match_state (more accurate than timer < 99)
    local gs = read_game_state()
    if gs.is_in_match == 1 and not timer_started_counting then
        timer_started_counting = true
        print(string.format("Gameplay active at frame %d (T:%d, match_state=0x02)", #captured, timer))
    end

    -- Phase transitions
    if new_phase ~= current_phase then
        -- New round starting
        if new_phase == PHASE_FIGHT_INTRO or new_phase == PHASE_PLAYING then
            if current_phase == PHASE_MENU or current_phase == PHASE_ROUND_END then
                rounds_seen = rounds_seen + 1
                timer_started_counting = false

                local p1_name = get_char_name(gs.p1_char)
                local p2_name = get_char_name(gs.p2_char)
                print(string.format("=== MATCH %d ROUND %d: %s (P1:%d) vs %s (P2:%d) T:%d frame:%d ===",
                      match_num, rounds_seen, p1_name, gs.p1_char, p2_name, gs.p2_char, timer, #captured))
            end
        end

        -- Round ended (KO or timeout)
        if new_phase == PHASE_ROUND_END then
            local winner, reason
            if p1_hp == 0 then
                winner = "P2"
                reason = "KO"
                p2_wins = p2_wins + 1
            elseif p2_hp == 0 then
                winner = "P1"
                reason = "KO"
                p1_wins = p1_wins + 1
            elseif timer == 0 then
                if p1_hp > p2_hp then
                    winner = "P1"
                    p1_wins = p1_wins + 1
                elseif p2_hp > p1_hp then
                    winner = "P2"
                    p2_wins = p2_wins + 1
                else
                    winner = "DRAW"
                end
                reason = "TIMEOUT"
            else
                winner = p1_hp > p2_hp and "P1" or "P2"
                reason = "?"
            end
            print(string.format("Round ended: %s wins by %s (T:%d, HP:%d/%d, Score:%d-%d) at frame %d",
                  winner, reason, timer, p1_hp, p2_hp, p1_wins, p2_wins, #captured))

            -- Match end (first to 2 wins)
            if p1_wins >= 2 or p2_wins >= 2 then
                local match_winner = p1_wins >= 2 and "P1" or "P2"
                print(string.format("=== MATCH %d OVER: %s wins %d-%d ===", match_num, match_winner, p1_wins, p2_wins))
                p1_wins = 0
                p2_wins = 0
                rounds_seen = 0
                match_num = match_num + 1
            end
        end

        -- Missed round end: went straight from PLAYING → MENU
        if new_phase == PHASE_MENU and current_phase == PHASE_PLAYING then
            local use_p1_hp, use_p2_hp = gs.p1_hp, gs.p2_hp

            if gs.p1_hp > MAX_HP or gs.p2_hp > MAX_HP then
                use_p1_hp = last_valid_hp.p1
                use_p2_hp = last_valid_hp.p2
                print(string.format("Using fallback HP: %d/%d (current invalid: %d/%d)",
                      use_p1_hp, use_p2_hp, gs.p1_hp, gs.p2_hp))
            end

            if use_p1_hp > use_p2_hp or use_p2_hp == 0 then
                p1_wins = p1_wins + 1
                print(string.format("Round ended (inferred): P1 wins (HP:%d/%d, Score:%d-%d) at frame %d",
                      use_p1_hp, use_p2_hp, p1_wins, p2_wins, #captured))
            elseif use_p2_hp > use_p1_hp or use_p1_hp == 0 then
                p2_wins = p2_wins + 1
                print(string.format("Round ended (inferred): P2 wins (HP:%d/%d, Score:%d-%d) at frame %d",
                      use_p1_hp, use_p2_hp, p1_wins, p2_wins, #captured))
            end

            if p1_wins >= 2 or p2_wins >= 2 then
                local match_winner = p1_wins >= 2 and "P1" or "P2"
                print(string.format("=== MATCH %d OVER: %s wins %d-%d ===", match_num, match_winner, p1_wins, p2_wins))
                p1_wins = 0
                p2_wins = 0
                rounds_seen = 0
                match_num = match_num + 1
            end
        end

        if new_phase == PHASE_MENU then
            print(string.format("Menu/transition state entered at frame %d", #captured))
        end

        current_phase = new_phase
    end

    -- Track menu dwell time and last valid HP
    if current_phase == PHASE_MENU then
        menu_frames = menu_frames + 1
    else
        menu_frames = 0
        if current_phase == PHASE_PLAYING then
            if gs.p1_hp <= MAX_HP and gs.p2_hp <= MAX_HP then
                last_valid_hp = {p1 = gs.p1_hp, p2 = gs.p2_hp}
            end
        end
    end

    prev_timer = timer
    return current_phase
end

local function get_game_state_str()
    local phase, timer, p1_hp, p2_hp, live = get_game_phase()
    local live_str = live and "LIVE" or "WAIT"

    if phase == PHASE_PLAYING then
        return string.format("R%d %s T:%d HP:%d/%d", rounds_seen, live_str, timer, p1_hp, p2_hp)
    elseif phase == PHASE_FIGHT_INTRO then
        return string.format("R%d INTRO T:%d", rounds_seen, timer)
    elseif phase == PHASE_ROUND_END then
        return string.format("KO T:%d HP:%d/%d", timer, p1_hp, p2_hp)
    else
        return "MENU"
    end
end

-- Detect replay mode
local IS_REPLAY = false
if emu.isreplay then
    IS_REPLAY = emu.isreplay()
    print("Replay mode: " .. (IS_REPLAY and "YES" or "NO"))
else
    print("Note: emu.isreplay() not available, assuming live capture")
end

-- Input mapping for SF3:3S (CPS3)
local INPUTS = {
    up    = " Up",
    down  = " Down",
    left  = " Left",
    right = " Right",
    lp    = " Weak Punch",
    mp    = " Medium Punch",
    hp    = " Strong Punch",
    lk    = " Weak Kick",
    mk    = " Medium Kick",
    hk    = " Strong Kick",
    start = " Start",
    coin  = " Coin",
}

-- Pack inputs to 16-bit value (matches rl_bridge.h / core.py)
-- Bits: 0-3 = U,D,L,R | 4-6 = LP,MP,HP | 7 = unused | 8-10 = LK,MK,HK | 11 = Start
local function pack_inputs(prefix, inputs)
    local value = 0
    if inputs[prefix .. INPUTS.up]    then value = value + 0x0001 end  -- bit 0
    if inputs[prefix .. INPUTS.down]  then value = value + 0x0002 end  -- bit 1
    if inputs[prefix .. INPUTS.left]  then value = value + 0x0004 end  -- bit 2
    if inputs[prefix .. INPUTS.right] then value = value + 0x0008 end  -- bit 3
    if inputs[prefix .. INPUTS.lp]    then value = value + 0x0010 end  -- bit 4
    if inputs[prefix .. INPUTS.mp]    then value = value + 0x0020 end  -- bit 5
    if inputs[prefix .. INPUTS.hp]    then value = value + 0x0040 end  -- bit 6
    -- bit 7 unused
    if inputs[prefix .. INPUTS.lk]    then value = value + 0x0100 end  -- bit 8
    if inputs[prefix .. INPUTS.mk]    then value = value + 0x0200 end  -- bit 9
    if inputs[prefix .. INPUTS.hk]    then value = value + 0x0400 end  -- bit 10
    if inputs[prefix .. INPUTS.start] then value = value + 0x0800 end  -- bit 11
    return value
end

-- Frame capture state
local start_frame = -1
local last_frame = -1
local is_done = false
local stall_count = 0

-- Hit detection (HP deltas)
local prev_p1_hp = MAX_HP
local prev_p2_hp = MAX_HP

-- Capture current frame's inputs and game state
local function capture_frame()
    local frame = emu.framecount()
    if frame == last_frame then return end
    last_frame = frame

    if start_frame == -1 then start_frame = frame end
    local rel_frame = frame - start_frame

    local inputs = joypad.get()
    local p1 = pack_inputs("P1", inputs)
    local p2 = pack_inputs("P2", inputs)

    local gs = read_game_state()
    local _, _, _, _, live = get_game_phase()

    -- Hit confirmation: detect HP decreases
    local p1_hit = (prev_p1_hp > gs.p1_hp) and (prev_p1_hp - gs.p1_hp) or 0
    local p2_hit = (prev_p2_hp > gs.p2_hp) and (prev_p2_hp - gs.p2_hp) or 0
    prev_p1_hp = gs.p1_hp
    prev_p2_hp = gs.p2_hp

    table.insert(captured, {
        frame = rel_frame,
        p1 = p1, p2 = p2,
        match_num = match_num,
        round_num = rounds_seen,
        match_state = gs.match_state,
        is_in_match = gs.is_in_match,
        timer = gs.timer,
        p1_hp = gs.p1_hp, p2_hp = gs.p2_hp,
        p1_x = gs.p1_x, p1_y = gs.p1_y,
        p2_x = gs.p2_x, p2_y = gs.p2_y,
        p1_facing = gs.p1_facing, p2_facing = gs.p2_facing,
        p1_meter = gs.p1_meter, p2_meter = gs.p2_meter,
        p1_meter_gauge = gs.p1_meter_gauge, p2_meter_gauge = gs.p2_meter_gauge,
        p1_stun_bar = gs.p1_stun_bar, p2_stun_bar = gs.p2_stun_bar,
        p1_stun_timer = gs.p1_stun_timer, p2_stun_timer = gs.p2_stun_timer,
        p1_combo_count = gs.p1_combo_count, p2_combo_count = gs.p2_combo_count,
        p1_char = gs.p1_char, p2_char = gs.p2_char,
        live = live and 1 or 0,
        p1_sa = gs.p1_sa, p2_sa = gs.p2_sa,
        p1_action = gs.p1_action, p2_action = gs.p2_action,
        p1_posture = gs.p1_posture, p2_posture = gs.p2_posture,
        p1_recovery = gs.p1_recovery, p2_recovery = gs.p2_recovery,
        p1_recovery_flag = gs.p1_recovery_flag, p2_recovery_flag = gs.p2_recovery_flag,
        p1_attacking = gs.p1_attacking, p2_attacking = gs.p2_attacking,
        p1_attacking_ext = gs.p1_attacking_ext, p2_attacking_ext = gs.p2_attacking_ext,
        p1_movement_type2 = gs.p1_movement_type2, p2_movement_type2 = gs.p2_movement_type2,
        p1_animation = gs.p1_animation, p2_animation = gs.p2_animation,
        p1_anim_frame = gs.p1_anim_frame, p2_anim_frame = gs.p2_anim_frame,
        p1_freeze = gs.p1_freeze, p2_freeze = gs.p2_freeze,
        p1_thrown = gs.p1_thrown, p2_thrown = gs.p2_thrown,
        p1_blocking = gs.p1_blocking, p2_blocking = gs.p2_blocking,
        p1_combo = gs.p1_combo, p2_combo = gs.p2_combo,
        p1_standing = gs.p1_standing, p2_standing = gs.p2_standing,
        p1_parry_fwd = gs.p1_parry_fwd, p1_parry_down = gs.p1_parry_down,
        p2_parry_fwd = gs.p2_parry_fwd, p2_parry_down = gs.p2_parry_down,
        p1_charge1 = gs.p1_charge1, p1_charge2 = gs.p1_charge2, p1_charge3 = gs.p1_charge3,
        p2_charge1 = gs.p2_charge1, p2_charge2 = gs.p2_charge2, p2_charge3 = gs.p2_charge3,
        p1_velocity = gs.p1_velocity, p2_velocity = gs.p2_velocity,
        p1_busy = gs.p1_busy, p2_busy = gs.p2_busy,
        p1_input_cap = gs.p1_input_cap, p2_input_cap = gs.p2_input_cap,
        p1_throw_countdown = gs.p1_throw_countdown, p2_throw_countdown = gs.p2_throw_countdown,
        p1_action_count = gs.p1_action_count, p2_action_count = gs.p2_action_count,
        p1_dmg_bonus = gs.p1_dmg_bonus, p2_dmg_bonus = gs.p2_dmg_bonus,
        p1_stun_bonus = gs.p1_stun_bonus, p2_stun_bonus = gs.p2_stun_bonus,
        p1_def_bonus = gs.p1_def_bonus, p2_def_bonus = gs.p2_def_bonus,
        screen_x = gs.screen_x, screen_y = gs.screen_y,
        p1_hit = p1_hit, p2_hit = p2_hit,
        rng_16 = gs.rng_16,
        stage = gs.stage,
    })

    -- Progress report every 3000 frames (~50 sec)
    if rel_frame % 3000 == 0 and rel_frame > 0 then
        print(string.format("Captured %d frames (%.0fs)", rel_frame, rel_frame / 60))
    end
end

-- Save captured data
local function save_data()
    if is_done or #captured == 0 then return end
    is_done = true

    -- Get character names from first live gameplay frame
    local p1_char_id, p2_char_id = 0, 0
    for _, f in ipairs(captured) do
        if f.live == 1 and f.p1_char and f.p2_char then
            p1_char_id = f.p1_char
            p2_char_id = f.p2_char
            break
        end
    end

    local p1_name = get_char_name(p1_char_id)
    local p2_name = get_char_name(p2_char_id)
    local matchup_base = CONFIG.output_dir .. p1_name .. "_vs_" .. p2_name

    local file_num = get_next_file_number(matchup_base)
    local csv_path = string.format("%s_%03d_full.csv", matchup_base, file_num)

    local csv = io.open(csv_path, "w")
    csv:write("frame,p1_input,p2_input,match,round,match_state,is_in_match,timer,"
        .. "p1_hp,p2_hp,p1_x,p1_y,p2_x,p2_y,p1_facing,p2_facing,"
        .. "p1_meter,p2_meter,p1_meter_gauge,p2_meter_gauge,"
        .. "p1_stun_bar,p2_stun_bar,p1_stun_timer,p2_stun_timer,"
        .. "p1_combo_count,p2_combo_count,"
        .. "p1_char,p2_char,live,p1_sa,p2_sa,"
        .. "p1_action,p2_action,p1_animation,p2_animation,p1_anim_frame,p2_anim_frame,"
        .. "p1_posture,p2_posture,p1_recovery,p2_recovery,"
        .. "p1_recovery_flag,p2_recovery_flag,"
        .. "p1_attacking,p2_attacking,p1_attacking_ext,p2_attacking_ext,"
        .. "p1_movement_type2,p2_movement_type2,"
        .. "p1_freeze,p2_freeze,p1_thrown,p2_thrown,p1_blocking,p2_blocking,"
        .. "p1_combo,p2_combo,p1_standing,p2_standing,"
        .. "p1_parry_fwd,p1_parry_down,p2_parry_fwd,p2_parry_down,"
        .. "p1_charge1,p1_charge2,p1_charge3,p2_charge1,p2_charge2,p2_charge3,"
        .. "p1_velocity,p2_velocity,p1_busy,p2_busy,p1_input_cap,p2_input_cap,"
        .. "p1_throw_countdown,p2_throw_countdown,p1_action_count,p2_action_count,"
        .. "p1_dmg_bonus,p2_dmg_bonus,p1_stun_bonus,p2_stun_bonus,p1_def_bonus,p2_def_bonus,"
        .. "screen_x,screen_y,"
        .. "p1_hit,p2_hit,rng_16,stage\n")

    for _, f in ipairs(captured) do
        local vals = {
            f.frame, f.p1, f.p2,
            f.match_num, f.round_num,
            f.match_state, f.is_in_match,
            f.timer,
            f.p1_hp, f.p2_hp,
            f.p1_x, f.p1_y, f.p2_x, f.p2_y,
            f.p1_facing, f.p2_facing,
            f.p1_meter, f.p2_meter,
            f.p1_meter_gauge, f.p2_meter_gauge,
            f.p1_stun_bar, f.p2_stun_bar,
            f.p1_stun_timer, f.p2_stun_timer,
            f.p1_combo_count, f.p2_combo_count,
            f.p1_char, f.p2_char,
            f.live,
            f.p1_sa, f.p2_sa,
            f.p1_action, f.p2_action,
            f.p1_posture, f.p2_posture,
            f.p1_recovery, f.p2_recovery,
            f.p1_recovery_flag, f.p2_recovery_flag,
            f.p1_attacking, f.p2_attacking,
            f.p1_attacking_ext, f.p2_attacking_ext,
            f.p1_movement_type2, f.p2_movement_type2,
            f.p1_animation, f.p2_animation,
            f.p1_anim_frame, f.p2_anim_frame,
            f.p1_freeze, f.p2_freeze,
            f.p1_thrown, f.p2_thrown,
            f.p1_blocking, f.p2_blocking,
            f.p1_combo, f.p2_combo,
            f.p1_standing, f.p2_standing,
            f.p1_parry_fwd, f.p1_parry_down, f.p2_parry_fwd, f.p2_parry_down,
            f.p1_charge1, f.p1_charge2, f.p1_charge3,
            f.p2_charge1, f.p2_charge2, f.p2_charge3,
            f.p1_velocity, f.p2_velocity,
            f.p1_busy, f.p2_busy,
            f.p1_input_cap, f.p2_input_cap,
            f.p1_throw_countdown, f.p2_throw_countdown,
            f.p1_action_count, f.p2_action_count,
            f.p1_dmg_bonus, f.p2_dmg_bonus,
            f.p1_stun_bonus, f.p2_stun_bonus,
            f.p1_def_bonus, f.p2_def_bonus,
            f.screen_x, f.screen_y,
            f.p1_hit, f.p2_hit,
            f.rng_16, f.stage
        }
        for i = 1, #vals do vals[i] = tostring(vals[i] or 0) end
        csv:write(table.concat(vals, ",") .. "\n")
    end
    csv:close()

    print("")
    print("============================================")
    print("  SAVED!")
    print("  CSV: " .. csv_path)
    print("  Frames: " .. #captured)
    print("  Duration: " .. string.format("%.1f", #captured / 60) .. " seconds")
    print("============================================")

    local p1_active, p2_active = 0, 0
    for _, f in ipairs(captured) do
        if f.p1 > 0 then p1_active = p1_active + 1 end
        if f.p2 > 0 then p2_active = p2_active + 1 end
    end
    print(string.format("P1 active: %d (%.1f%%)", p1_active, p1_active / #captured * 100))
    print(string.format("P2 active: %d (%.1f%%)", p2_active, p2_active / #captured * 100))

    -- Write status file for batch orchestration
    if CONFIG.write_status_file then
        local status_path = string.format("%s_%03d_status.txt", matchup_base, file_num)
        local status_file = io.open(status_path, "w")
        if status_file then
            status_file:write("COMPLETE\n")
            status_file:write("frames=" .. #captured .. "\n")
            status_file:write("csv=" .. csv_path .. "\n")
            status_file:write("p1=" .. p1_name .. "\n")
            status_file:write("p2=" .. p2_name .. "\n")
            status_file:close()
            print("Status file: " .. status_path)
        end
    end

    -- Auto-exit emulator for batch processing
    if CONFIG.auto_exit_on_end then
        print("Auto-exiting emulator...")
        for i = 1, 60 do end  -- Brief delay for file writes
        os.execute("taskkill /F /IM fcadefbneo.exe")
    end
end

-- Replay end detection
local MIN_FRAMES_BEFORE_END_CHECK = 1000   -- ~17 seconds before checking
local MENU_TIMEOUT_FRAMES = 3600           -- 60 seconds in MENU = replay ended
local prev_check_frame = 0

local function check_replay_end()
    if #captured < MIN_FRAMES_BEFORE_END_CHECK then return end

    -- Stuck in MENU for too long = replay is over
    if current_phase == PHASE_MENU and menu_frames > MENU_TIMEOUT_FRAMES then
        print(string.format("Replay ended (in menu for %ds after %d frames, %d rounds)",
              math.floor(menu_frames / 60), #captured, rounds_seen))
        save_data()
        return
    end

    -- Emulator frame stall detection
    local frame = emu.framecount()
    if frame == prev_check_frame then
        stall_count = stall_count + 1
        if stall_count > 7200 then  -- 2 minutes of no frame progress
            print(string.format("Replay ended (emulator stalled after %d frames)", #captured))
            save_data()
        end
    else
        stall_count = 0
    end
    prev_check_frame = frame
end

-- Main frame callback
local function on_frame()
    if is_done then return end
    update_game_phase()
    capture_frame()
    if CONFIG.auto_save_on_end then check_replay_end() end

    if CONFIG.show_hud then
        local state = get_game_state_str()
        gui.text(2, 2, string.format("REC: %d (%.1fm) | %s",
                 #captured, #captured/3600, state), 0x00FF00)
    end
end

emu.registerafter(on_frame)

-- Auto-save on script stop/close
if emu.registerexit then
    emu.registerexit(function()
        if not is_done and #captured > 0 then
            print("Script stopping - auto-saving...")
            save_data()
        end
    end)
end

-- Hotkeys and turbo mode
local prev_keys = {}
local turbo_active = false
gui.register(function()
    local keys = input.get()

    -- F12: Force save
    if keys.F12 and not prev_keys.F12 then
        save_data()
    end

    -- F1: Toggle turbo mode
    if CONFIG.turbo_mode then
        if keys.F1 and not prev_keys.F1 then
            turbo_active = not turbo_active
            if turbo_active then
                if emu.speedmode then
                    emu.speedmode("turbo")
                elseif fba and fba.speedmode then
                    fba.speedmode("turbo")
                end
                print("Turbo: ON")
            else
                if emu.speedmode then
                    emu.speedmode("normal")
                elseif fba and fba.speedmode then
                    fba.speedmode("normal")
                end
                print("Turbo: OFF")
            end
        end
    end

    prev_keys = keys
end)

-- Startup
print("")
if IS_REPLAY then
    print("Replay detected - capturing inputs automatically")
else
    print("Live mode - capturing inputs for training")
end
print("Press F12 to force-save at any time")
print("Press F1 to toggle turbo speed")
if CONFIG.auto_exit_on_end then
    print("Auto-exit: ENABLED (will close emulator when done)")
end
print("")

-- Auto-enable turbo mode on startup for batch processing
if CONFIG.auto_turbo and CONFIG.turbo_mode then
    print("Auto-turbo: Enabling fast-forward...")
    if emu.speedmode then
        emu.speedmode("turbo")
    elseif fba and fba.speedmode then
        fba.speedmode("turbo")
    end
    turbo_active = true
end
