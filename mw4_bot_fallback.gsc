// MW4 Botfix v1.2 release build (= fallback DEV 32, runtime-tested 2026-10-27; only the log prefix differs).
// MW4 Bot fallback (DEV 32). Part of the Botfix package; needs mw4_addbot (Henrik's script):
//   - waits until mw4_addbot::spawn_bots_auto has started the bot system (bots::main / bots::init),
//   - adds bots with exactly the call mw4_addbot used from v5 to v85 / Botfix v1:
//       level [[ &bots::spawn_bots ]](n, team, undefined, undefined, undefined, difficulty, undefined)
//     (DEV 22/23 rebuilt that function's inner loop with addbot(); DEV 24 calls it directly),
//   - the bots get bot_think + var_3215388132e3d9b5, so mw4_addbot's movement/combat threads drive them.
// Used only in matches where the lobby bots do not connect (every match after the first unless the
// game is fully restarted: the lobby loses its bots after a match / map_restart).
// Count = dvar mw4_botfix_fb_count, set from the Lua menu ("Ersatz-Bots"):
//   Engine.NotifyServer("splash_shown", 9175000 + n)
//   n = 100 Auto: the lobby recorded in the last match where the lobby bots DID connect
//               (mw4_botfix_lb_total / _friend / _enemy / _diff), 11 if nothing is recorded yet
//   n = 0   off
//   n = 1..99 fixed count
// Teams: the recorded host/enemy split with one call per team (as balanced_spawn in v38-v61);
// later fills in team modes go to the smaller team; FFA / no host: one "autoassign" call (as v5-v85).
// Lowering the count drops per team (stock drop_bots(n, team)), from the side with more players.
// Difficulty (DEV 27): recorded per side (host team vs. the others) because the DEV 26 lobby had
// "hardened" friends and "master" enemies; whether the lobby sets it per team or per bot is not
// established, so each side records its most frequent value (mw4_botfix_lb_diff_friend / _enemy)
// and every per-team spawn_bots call gets its side's value. "master" is not in the stock rank
// tables (bots::function_7800e57cc7b4882d knows recruit..veteran), so the stock path player_spawned
// -> rank -> bots_util::function_851f1839906b918 -> bot_get_rank_xp logs 2x DEV ERROR 0x0F307B1A
// + 2x 0xB95ABD47 per "master" bot, for the lobby bots as well; that path runs because mw4_addbot
// starts bots::main (which registers bot_get_rank_xp). Not fatal.
//
// Local variables (ACTS stores = EvalLocalVariableRefCached + SetVariableField; stock code uses
// SetLocalVariableCached):
// - After a thread resumes from `wait`, local stores are lost until the code reads an object field
//   (level.x). Confirmed by the DEV 25 wait probe in three map loads: first=undefined second=7.
// - The same happens after a builtin method call (ent method()): in DEV 25 `d = p botgetdifficulty()`
//   was lost (diff stayed -1 although the stock returns "recruit"/"regular"/"hardened"/"veteran"),
//   and so were text/secs after the loop ("recorded undefined (after undefined s)").
// - Increments (i++) and stores into fields always work.
// Rules:
//   1. functions that execute `wait` have no locals and keep their state in level fields,
//   2. every helper with locals reads a level field before its first local store,
//   3. the result of a builtin method call goes straight into a level field.
// No endon, no !== (ACTS bo7).
//
// DEV 29: standing bots with more than 6 bots. The engine (cod26-cod.exe) gives only K bots a full
// think per server frame: K = (ceil(N*A) < B) ? min(B,N) : min(ceil(N*A),C) with three unnamed engine
// dvars A (#485637e5bed4b1cd, float 0.5), B (#a4effa96d7d9c8e6, int 6), C (#6e3c5e81cd9cba88, int 200),
// so K=6 for up to 12 bots; the others replay their last usercmd and mw4_addbot's moves never reach them.
// DEV 28 A/B test (runtime-confirmed 2026-10-17, 11 bots): with B=6 clients 7-11 stood still, after
// setting B=32 all bots ran within seconds. B is now kept at 32 (K=N up to 32 bots) from module start;
// it is checked every second and set again if something resets it. slice_keep waits and has no locals.
// DEV 30: the Botfix menu (GSC DEV 23, cmd 10) can change bot difficulties; it saves each bot's lobby value in
// pers["mw4_bd_orig"] before. The lobby recording and the name log read that saved value first, so a
// difficulty picked in the menu is never recorded as the lobby difficulty for later replacement bots.
// DEV 31: on-screen messages in English.
// DEV 32 (Henrik 2026-10-25): custom bot names. Stock spawn_bots always calls addbot("") (bots.gsc:1557), so the
// engine makes the names up. With "Bot Names: Custom" in the menu (dvar mw4_botfix_bn_mode 1, list received by
// the menu GSC in mw4_botfix_bn_a.._c) the bots this module adds go through fb_add_named instead: the same steps
// and fields as stock spawn_bots (bots.gsc:1548-1624), only addbot gets a name from the list (stock FTUE bots do
// the same, script_4f2ec5e36fe18c11.gsc:250). Without a list the proven spawn_bots call stays. Lobby bots keep
// their names (a connected client cannot be renamed).
#using scripts\common\system;
#using scripts\common\utility;
#using scripts\common\ui;
#using scripts\mp\bots\bots;
#using scripts\mp\bots\bots_util;
#namespace mw4_bot_fallback;

function private autoexec __init__system__()
{
    system::register(#"mw4_bot_fallback", undefined, &__init__, undefined);
}

function __init__()
{
    level.mw4_fb_target = 0;
    level.mw4_fb_active = 0;
    level.mw4_fb_busy = 0;
    level.mw4_fb_again = 0;
    level.mw4_fb_guard_on = 0;
    level.mw4_fb_guard_t0 = 0;
    level.mw4_fb_over = 0;
    level thread [[ &slice_keep ]]();
    utility::function_fb7b1af19016b7f4("StartGameTypeCallbackFinished");
    level ui::function_96f4ffdd8248ddf3("splash_shown", &fb_carrier);
    level thread [[ &fb_main ]]();
}

// Engine bot think limit B (see the DEV 29 note): keep it at 32. Logs the first set of the match and
// at most two later re-sets.
function slice_keep()
{
    level.mw4_st_sets = 0;
    level.mw4_st_missing = 0;
    for (;;)
    {
        if (getdvarint(@"hash_a4effa96d7d9c8e6", -1) < 0)
        {
            // Never create a dvar of our own.
            if (!level.mw4_st_missing) [[ &fb_log ]]("bot think limit: engine dvar not found, unchanged");
            level.mw4_st_missing = 1;
        }
        else if (getdvarint(@"hash_a4effa96d7d9c8e6", -1) < 32)
        {
            level.mw4_st_from = getdvarint(@"hash_a4effa96d7d9c8e6", -1);
            setdvar(@"hash_a4effa96d7d9c8e6", 32);
            if (level.mw4_st_sets < 3)
                [[ &fb_log ]]("bot think limit: " + level.mw4_st_from + " -> " + getdvarint(@"hash_a4effa96d7d9c8e6", -1)
                    + " (all bots get a full think every frame)");
            level.mw4_st_sets++;
        }
        else if (level.mw4_st_sets == 0)
        {
            [[ &fb_log ]]("bot think limit: already " + getdvarint(@"hash_a4effa96d7d9c8e6", -1));
            level.mw4_st_sets = 1;
        }
        wait 1;
        if ([[ &fb_postgame ]]()) return;
    }
}

function fb_log(text)
{
    function_8b17726cc97055("MW4 Botfix v1.2 fallback: " + text);
}

// Stock ui.gsc registry callback; the registry keeps a list per event, so the menu receiver
// (mw4_botfix_menu) still gets every value. Only cmd 5 is used here.
function fb_carrier(value)
{
    if (!isdefined(level.mw4_fb_active)) return;
    if (!isdefined(value)) return;
    if (!(value >= 9175000 && value < 9176000)) return;
    arg = value - 9175000;
    if (arg > 100) return;
    setdvar(@"mw4_botfix_fb_count", arg);
    [[ &fb_log ]]("menu: replacement bots = " + [[ &fb_mode_name ]](arg) + " (active=" + level.mw4_fb_active + ")");
    if (level.mw4_fb_active) level thread [[ &fb_apply ]]();
}

function fb_mode_name(mode)
{
    if (mode <= 0) return "Off";
    if (mode >= 100) return "Auto";
    return "" + mode;
}

function fb_elapsed(t)
{
    return gettime() - t;
}

function fb_postgame()
{
    return isdefined(game["state"]) && game["state"] == "postgame";
}

function fb_bots_ready()
{
    if (!isdefined(level.var_477af87fd16c4a08) || !level.var_477af87fd16c4a08) return false;
    if (!isdefined(level.var_cc3cbaf0cb1a1b43)) return false;
    return isdefined(level.var_cc3cbaf0cb1a1b43["think"]);
}

function fb_count_bots()
{
    players = level.players;
    n = 0;
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (isdefined(p) && isbot(p)) n++;
    }
    return n;
}

// The human host once he is on a real team: allies/axis in team modes, any non-spectator team in FFA.
function fb_host()
{
    players = level.players;
    teambased = isdefined(level.teambased) && level.teambased;
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (!isdefined(p) || isbot(p) || !isdefined(p.team)) continue;
        if (teambased)
        {
            if (p.team == "allies" || p.team == "axis") return p;
        }
        else if (p.team != "" && p.team != "spectator") return p;
    }
    return undefined;
}

function fb_team_count(team, bots_only)
{
    players = level.players;
    n = 0;
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (!isdefined(p) || !isdefined(p.team) || p.team != team) continue;
        if (bots_only && !isbot(p)) continue;
        n++;
    }
    return n;
}

// Difficulty index <-> name. 0-3 = the names in the stock rank tables, 4 = mixed (stock
// bot_set_difficulty resolves it per bot), 5 = master (DEV 26 lobby), 6-8 = easy/normal/hard
// (stock maps them to recruit..veteran before the engine sees them; kept in case the engine
// reports them). A recorded value is handed back to spawn_bots unchanged.
function fb_diff_count()
{
    return 9;
}

function fb_diff_name(idx)
{
    if (idx == 0) return "recruit";
    if (idx == 1) return "regular";
    if (idx == 2) return "hardened";
    if (idx == 3) return "veteran";
    if (idx == 4) return "mixed";
    if (idx == 5) return "master";
    if (idx == 6) return "easy";
    if (idx == 7) return "normal";
    if (idx == 8) return "hard";
    return undefined;
}

// spawn_bots difficulty for a recorded index; nothing recorded -> stock default "regular".
function fb_diff_pick(idx)
{
    if (!isdefined(idx) || idx < 0 || idx >= [[ &fb_diff_count ]]()) return "regular";
    return [[ &fb_diff_name ]](idx);
}

// Most frequent difficulty index in a count array (first one on a tie), -1 if empty.
function fb_diff_majority(cnt)
{
    players = level.players;
    best = -1;
    bestn = 0;
    for (k = 0; k < cnt.size; k++)
    {
        if (cnt[k] > bestn)
        {
            best = k;
            bestn = cnt[k];
        }
    }
    return best;
}

// Waits: no locals. Every loop condition reads a level field first.
function fb_main()
{
    level.mw4_fb_t0 = gettime();
    level.mw4_fb_t1 = gettime();
    // The bot system is ready about 6.4 s after StartGameTypeCallbackFinished
    // (mw4_addbot: wait 5, bots::main, which starts bots::init after 1.4 s).
    while ([[ &fb_elapsed ]](level.mw4_fb_t0) < 30000 && !level [[ &fb_bots_ready ]]()) wait 0.05;
    if (!level [[ &fb_bots_ready ]]())
    {
        [[ &fb_log ]]("bot system not initialised after 30 s; nothing done");
        return;
    }
    // Lobby bots connect in one bot_connect_monitor pass (every 1.5 s) once the host is in.
    // Wait for the host on a team (max 90 s), then give them 2 s.
    while ([[ &fb_elapsed ]](level.mw4_fb_t0) < 90000 && !isdefined([[ &fb_host ]]()) && [[ &fb_count_bots ]]() == 0) wait 0.05;
    level.mw4_fb_t1 = gettime();
    while ([[ &fb_elapsed ]](level.mw4_fb_t1) < 2000 && [[ &fb_count_bots ]]() == 0) wait 0.05;
    if (level.mw4_fb_t1 > 0 && [[ &fb_count_bots ]]() > 0)
    {
        [[ &fb_log ]]("native lobby bots present (" + [[ &fb_count_bots ]]() + "); recording lobby");
        level thread [[ &fb_record ]]();
        return;
    }
    if (level.mw4_fb_t1 > 0 && [[ &fb_postgame ]]()) return;
    [[ &fb_log_start ]]();
    // From here on, menu changes apply to this match immediately.
    level.mw4_fb_active = 1;
    [[ &fb_apply ]]();
    level thread [[ &fb_report_later ]]();
}

function fb_log_start()
{
    players = level.players;
    mode = getdvarint(@"mw4_botfix_fb_count", 100);
    [[ &fb_log ]]("no native bots " + [[ &fb_elapsed ]](level.mw4_fb_t1) + " ms after host + bot system ready ("
        + [[ &fb_elapsed ]](level.mw4_fb_t0) + " ms after script start); mode=" + [[ &fb_mode_name ]](mode)
        + " recorded total=" + getdvarint(@"mw4_botfix_lb_total", -1)
        + " friend=" + getdvarint(@"mw4_botfix_lb_friend", -1) + " enemy=" + getdvarint(@"mw4_botfix_lb_enemy", -1)
        + " diff=" + getdvarint(@"mw4_botfix_lb_diff", -1) + " friend_diff=" + getdvarint(@"mw4_botfix_lb_diff_friend", -1)
        + " enemy_diff=" + getdvarint(@"mw4_botfix_lb_diff_enemy", -1) + " players=" + players.size
        + " botlimit=" + level [[ &bots_util::function_e8e82751e1da8206 ]]() + " maxclients=" + getmaxclients());
}

// Final names/teams once the last bots finished connecting. Waits: no locals.
function fb_report_later()
{
    wait 5;
    if (!isdefined(level.players) || [[ &fb_postgame ]]()) return;
    [[ &fb_log_names ]]();
    IPrintLn("MW4 Botfix: " + [[ &fb_count_bots ]]() + " bots in the match");
}

// A match where the native lobby bots connected: remember the lobby for the next matches.
// First write 3 s after the bots appear, then refine while late bots finish connecting.
// Waits: no locals.
function fb_record()
{
    level.mw4_fb_rec_t0 = gettime();
    level.mw4_fb_rec_last = "";
    level.mw4_fb_rec_step = 0;
    while (level.mw4_fb_rec_step < 5)
    {
        while ([[ &fb_elapsed ]](level.mw4_fb_rec_t0) < [[ &fb_record_mark ]](level.mw4_fb_rec_step)) wait 0.5;
        if (!isdefined(level.players) || [[ &fb_postgame ]]()) return;
        [[ &fb_record_once ]](level.mw4_fb_rec_step);
        level.mw4_fb_rec_step = level.mw4_fb_rec_step + 1;
    }
}

function fb_record_mark(step)
{
    if (step <= 0) return 3000;
    if (step == 1) return 6000;
    if (step == 2) return 10000;
    if (step == 3) return 20000;
    return 45000;
}

function fb_record_once(step)
{
    players = level.players;
    total = [[ &fb_count_bots ]]();
    if (total <= 0) return;
    host = [[ &fb_host ]]();
    teambased = isdefined(level.teambased) && level.teambased;
    friend = -1;
    enemy = -1;
    split = "none";
    if (!teambased) split = "ffa";
    else if (isdefined(host))
    {
        friend = [[ &fb_team_count ]](host.team, true);
        enemy = total - friend;
        split = "ok";
    }
    // Friendly = the host's team in team modes; FFA / no host: every bot counts as enemy.
    level.mw4_fb_rec_hostteam = undefined;
    if (split == "ok") level.mw4_fb_rec_hostteam = host.team;
    [[ &fb_record_diff ]](players);
    setdvar(@"mw4_botfix_lb_total", total);
    // FFA has no split; a team match without a visible host keeps the previous split.
    if (split == "ok" || split == "ffa")
    {
        setdvar(@"mw4_botfix_lb_friend", friend);
        setdvar(@"mw4_botfix_lb_enemy", enemy);
        setdvar(@"mw4_botfix_lb_diff_friend", level.mw4_fb_rec_dfriend);
        setdvar(@"mw4_botfix_lb_diff_enemy", level.mw4_fb_rec_denemy);
    }
    setdvar(@"mw4_botfix_lb_diff", level.mw4_fb_rec_diff);
    // No local store after the method calls in fb_record_diff (rule 3): text in a level field.
    level.mw4_fb_rec_text = "total=" + total + " friend=" + friend + " enemy=" + enemy + " split=" + split
        + " diff=" + level.mw4_fb_rec_diff + " friend_diff=" + level.mw4_fb_rec_dfriend
        + " enemy_diff=" + level.mw4_fb_rec_denemy + " (raw friend:" + level.mw4_fb_rec_rawf
        + " / enemy:" + level.mw4_fb_rec_rawe + ")";
    if (level.mw4_fb_rec_text != level.mw4_fb_rec_last)
        [[ &fb_log ]]("recorded " + level.mw4_fb_rec_text + " (after " + int([[ &fb_record_mark ]](step) / 1000) + " s)");
    level.mw4_fb_rec_last = level.mw4_fb_rec_text;
}

// Lobby difficulty as fb_diff_name() index (-1 = unknown): the most frequent value of all bots
// (level.mw4_fb_rec_diff) and per side (_dfriend: bots on level.mw4_fb_rec_hostteam, _denemy:
// all others); _rawf / _rawe list every raw botgetdifficulty() value per side, also names not in
// the list. Every botgetdifficulty() result goes straight into a level field (rule 3), so the
// stores of p and k that follow come after a field access.
function fb_record_diff(players)
{
    level.mw4_fb_rec_rawf = "";
    level.mw4_fb_rec_rawe = "";
    level.mw4_fb_cnta = [];
    level.mw4_fb_cntf = [];
    level.mw4_fb_cnte = [];
    for (k = 0; k < [[ &fb_diff_count ]](); k++)
    {
        level.mw4_fb_cnta[k] = 0;
        level.mw4_fb_cntf[k] = 0;
        level.mw4_fb_cnte[k] = 0;
    }
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (!isdefined(p) || !isbot(p)) continue;
        if (isdefined(p.var_8b69ecbd466a79fa) && isdefined(p.var_8b69ecbd466a79fa["mw4_bd_orig"]))
            level.mw4_fb_d = p.var_8b69ecbd466a79fa["mw4_bd_orig"];   // lobby value saved by the menu (DEV 30 note)
        else level.mw4_fb_d = p botgetdifficulty();
        if (!isdefined(level.mw4_fb_d)) continue;
        level.mw4_fb_isfriend = isdefined(level.mw4_fb_rec_hostteam) && isdefined(p.team) && p.team == level.mw4_fb_rec_hostteam;
        if (level.mw4_fb_isfriend) level.mw4_fb_rec_rawf = level.mw4_fb_rec_rawf + " " + level.mw4_fb_d;
        else level.mw4_fb_rec_rawe = level.mw4_fb_rec_rawe + " " + level.mw4_fb_d;
        level.mw4_fb_idx = -1;
        for (k = 0; k < [[ &fb_diff_count ]](); k++)
            if (level.mw4_fb_d == [[ &fb_diff_name ]](k)) level.mw4_fb_idx = k;
        if (level.mw4_fb_idx < 0) continue;
        level.mw4_fb_cnta[level.mw4_fb_idx] = level.mw4_fb_cnta[level.mw4_fb_idx] + 1;
        if (level.mw4_fb_isfriend) level.mw4_fb_cntf[level.mw4_fb_idx] = level.mw4_fb_cntf[level.mw4_fb_idx] + 1;
        else level.mw4_fb_cnte[level.mw4_fb_idx] = level.mw4_fb_cnte[level.mw4_fb_idx] + 1;
    }
    level.mw4_fb_rec_diff = [[ &fb_diff_majority ]](level.mw4_fb_cnta);
    level.mw4_fb_rec_dfriend = [[ &fb_diff_majority ]](level.mw4_fb_cntf);
    level.mw4_fb_rec_denemy = [[ &fb_diff_majority ]](level.mw4_fb_cnte);
}

// Wanted replacement-bot count for the current setting.
function fb_wanted()
{
    players = level.players;
    mode = getdvarint(@"mw4_botfix_fb_count", 100);
    w = spawnstruct();
    w.mode = mode;
    w.friend = -1;
    w.enemy = -1;
    w.diff = getdvarint(@"mw4_botfix_lb_diff", -1);
    w.dfriend = getdvarint(@"mw4_botfix_lb_diff_friend", -1);
    w.denemy = getdvarint(@"mw4_botfix_lb_diff_enemy", -1);
    w.source = "fixed";
    if (mode <= 0) w.total = 0;
    else if (mode < 100) w.total = mode;
    else
    {
        w.total = getdvarint(@"mw4_botfix_lb_total", -1);
        w.friend = getdvarint(@"mw4_botfix_lb_friend", -1);
        w.enemy = getdvarint(@"mw4_botfix_lb_enemy", -1);
        w.source = "recorded lobby";
        if (w.total <= 0)
        {
            w.total = 11;
            w.friend = -1;
            w.enemy = -1;
            w.source = "default 11 (nothing recorded yet)";
        }
    }
    return w;
}

// Bring the replacement bots to the wanted count (first fill and every later menu change).
// Runs one at a time; a change that arrives while it runs is applied right after.
function fb_apply()
{
    if (level.mw4_fb_busy)
    {
        level.mw4_fb_again = 1;
        return;
    }
    level.mw4_fb_busy = 1;
    for (pass = 0; pass < 5; pass++)
    {
        level.mw4_fb_again = 0;
        if ([[ &fb_postgame ]]()) break;
        w = [[ &fb_wanted ]]();
        have = [[ &fb_count_bots ]]();
        limit = level [[ &bots_util::function_e8e82751e1da8206 ]]();
        maxc = getmaxclients();
        if (limit <= 0 || limit > maxc) limit = maxc;
        humans = level.players.size - have;
        room = limit - humans;
        want = w.total;
        if (want > room) want = room;
        if (want < 0) want = 0;
        level.mw4_fb_target = want;
        setdvar(@"mw4_botfix_fb_target", want);
        [[ &fb_log ]]("apply mode=" + [[ &fb_mode_name ]](w.mode) + " source=" + w.source + " wanted=" + w.total
            + " room=" + room + " bots now=" + have + " -> target " + want);
        if (want > have)
        {
            // Lobby difficulty per side; a side without a recorded value takes the common one
            // (stock default "regular" if nothing is recorded).
            dcommon = [[ &fb_diff_pick ]](w.diff);
            dfriend = dcommon;
            denemy = dcommon;
            if (w.dfriend >= 0) dfriend = [[ &fb_diff_pick ]](w.dfriend);
            if (w.denemy >= 0) denemy = [[ &fb_diff_pick ]](w.denemy);
            // FFA / no host on a team: one autoassign call; every bot is an opponent there,
            // and an FFA recording stores all bots as enemy.
            dauto = denemy;
            // The recorded host-relative split is used only for the first fill.
            friend = -1;
            enemy = -1;
            if (have == 0)
            {
                friend = w.friend;
                enemy = w.enemy;
            }
            need = want - have;
            // Late lobby bots during the next 60 s are dropped again (fb_guard).
            level.mw4_fb_guard_t0 = gettime();
            if (!level.mw4_fb_guard_on) level thread [[ &fb_guard ]]();
            got = [[ &fb_fill ]](need, friend, enemy, dfriend, denemy, dauto);
            setdvar(@"mw4_botfix_fb_added", got);
            [[ &fb_log ]]("added " + got + "/" + need + " (diff friend=" + dfriend + " enemy=" + denemy
                + ") bots now=" + [[ &fb_count_bots ]]());
        }
        else if (want < have)
        {
            drop = have - want;
            [[ &fb_drop ]](drop);
            IPrintLn("MW4 Botfix: " + drop + " bots removed");
        }
        if (!level.mw4_fb_again) break;
    }
    level.mw4_fb_busy = 0;
    // more changes than passes: apply the latest one, too
    if (level.mw4_fb_again) level thread [[ &fb_apply ]]();
}

// Team plan for num new bots with one spawn_bots call per team, so each side gets its own
// difficulty: the recorded host-relative split on the first fill, otherwise the smaller side
// first (humans + bots). FFA or no host on a team: one "autoassign" call with dauto.
function fb_fill(num, friend, enemy, dfriend, denemy, dauto)
{
    players = level.players;
    host = [[ &fb_host ]]();
    teambased = isdefined(level.teambased) && level.teambased;
    allies = 0;
    axis = 0;
    autos = num;
    adiff = dauto;
    xdiff = dauto;
    if (teambased && isdefined(host) && (host.team == "allies" || host.team == "axis"))
    {
        if (friend >= 0 && enemy >= 0 && friend + enemy > 0)
        {
            while (friend + enemy > num)
            {
                if (friend >= enemy && friend > 0) friend--;
                else enemy--;
            }
            // a recorded lobby smaller than the clamp: put the rest on the smaller side
            while (friend + enemy < num)
            {
                if (friend < enemy) friend++;
                else enemy++;
            }
        }
        else
        {
            eteam = "axis";
            if (host.team == "axis") eteam = "allies";
            fhave = [[ &fb_team_count ]](host.team, false);
            ehave = [[ &fb_team_count ]](eteam, false);
            friend = 0;
            enemy = 0;
            while (friend + enemy < num)
            {
                if (fhave + friend < ehave + enemy) friend++;
                else enemy++;
            }
        }
        if (host.team == "allies") { allies = friend; axis = enemy; adiff = dfriend; xdiff = denemy; }
        else { axis = friend; allies = enemy; xdiff = dfriend; adiff = denemy; }
        autos = 0;
    }
    [[ &fb_log ]]("plan allies=" + allies + " (" + adiff + ") axis=" + axis + " (" + xdiff + ") autoassign="
        + autos + " (" + dauto + ")");
    teams = ["allies", "axis", "autoassign"];
    counts = [allies, axis, autos];
    diffs = [adiff, xdiff, dauto];
    got = 0;
    for (t = 0; t < teams.size; t++)
    {
        if (counts[t] <= 0) continue;
        got = got + [[ &fb_add ]](counts[t], teams[t], diffs[t]);
        if ([[ &fb_postgame ]]()) break;
    }
    return got;
}

// mw4_addbot's add call (v5-v85, Botfix v1): bots::spawn_bots(count, team, , , , difficulty, ).
// It retries addbot() for 15 s, waits up to 60 s until each bot is ready and returns nothing,
// so the result is counted from the bots before and after (the last bot may still be connecting).
function fb_add(num, team, diffname)
{
    players = level.players;
    before = [[ &fb_count_bots ]]();
    if ([[ &fb_bn_on ]]())
    {
        [[ &fb_log ]]("named add(" + num + ", " + team + ", " + diffname + ") bots before=" + before
            + " players=" + players.size + " names=" + level.mw4_fbn_list.size);
        level [[ &fb_add_named ]](num, team, diffname);
        if (level.mw4_fbn_wait.size == 0 && level.mw4_fbn_fail > 0)
        {
            // the engine refused the names: engine names rather than no bots
            [[ &fb_log ]]("named add failed (" + level.mw4_fbn_fail + " refused); spawn_bots with engine names instead");
            level [[ &bots::function_ebfd71106cee0b1c ]](num, team, undefined, undefined, undefined, diffname, undefined);
        }
    }
    else
    {
        [[ &fb_log ]]("spawn_bots(" + num + ", " + team + ", " + diffname + ") bots before=" + before
            + " players=" + players.size);
        level [[ &bots::function_ebfd71106cee0b1c ]](num, team, undefined, undefined, undefined, diffname, undefined);
    }
    after = [[ &fb_count_bots ]]();
    got = after - before;
    [[ &fb_log ]]("spawn_bots(" + num + ", " + team + ") finished: bots " + before + " -> " + after);
    return got;
}

// Bot names, teams and the difficulty the engine reports ("bots without names", and whether
// the engine took the requested difficulty, e.g. "master").
function fb_log_names()
{
    players = level.players;
    text = "";
    n = 0;
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (!isdefined(p) || !isbot(p)) continue;
        // rule 3: the method result goes into a level field; the reads after it restore stores
        if (isdefined(p.var_8b69ecbd466a79fa) && isdefined(p.var_8b69ecbd466a79fa["mw4_bd_orig"]))
            level.mw4_fb_d = p.var_8b69ecbd466a79fa["mw4_bd_orig"];   // lobby value saved by the menu (DEV 30 note)
        else level.mw4_fb_d = p botgetdifficulty();
        if (!isdefined(level.mw4_fb_d)) level.mw4_fb_d = "?";
        name = "<undefined>";
        if (isdefined(p.name)) name = "'" + p.name + "'";
        team = "?";
        if (isdefined(p.team)) team = p.team;
        text = text + " " + name + "/" + team + "/" + level.mw4_fb_d;
        n++;
    }
    [[ &fb_log ]]("bots now " + n + ":" + text);
}

// Lower the bot count by num. Team modes: one stock drop_bots(n, team) call per team, each kick
// from the side with more players (humans + bots) that still has bots, on a tie from the host's
// side (fb_fill gives the odd player to the enemy), so the teams stay even (a team-blind drop
// kicks from the end of level.players = the team filled last). Bots that have no team yet (just
// connected) are dropped team-blind as the rest. FFA: one call. No local store after a drop_bots
// call (it kicks via builtin methods and waits).
function fb_drop(num)
{
    players = level.players;
    teambased = isdefined(level.teambased) && level.teambased;
    if (!teambased)
    {
        [[ &fb_log ]]("dropping " + num + " bots");
        level [[ &bots::function_de8785b022e0692e ]](num);
        return;
    }
    al = [[ &fb_team_count ]]("allies", false);
    ax = [[ &fb_team_count ]]("axis", false);
    bal = [[ &fb_team_count ]]("allies", true);
    bax = [[ &fb_team_count ]]("axis", true);
    h = [[ &fb_host ]]();
    hal = isdefined(h) && h.team == "allies";
    dal = 0;
    dax = 0;
    for (k = 0; k < num; k++)
    {
        if (bal - dal <= 0 && bax - dax <= 0) break;
        if (bax - dax <= 0 || (bal - dal > 0 && (al - dal > ax - dax || (al - dal == ax - dax && hal)))) dal++;
        else dax++;
    }
    rest = num - dal - dax;
    [[ &fb_log ]]("dropping " + num + " bots: allies " + dal + ", axis " + dax + ", no team " + rest);
    if (dal > 0) level [[ &bots::function_de8785b022e0692e ]](dal, "allies");
    if (dax > 0) level [[ &bots::function_de8785b022e0692e ]](dax, "axis");
    if (rest > 0) level [[ &bots::function_de8785b022e0692e ]](rest);
}

// Drop surplus bots if the lobby bots still arrive late (stock bots::drop_bots, bots.gsc:608,
// kicks test clients, prefers dead ones). Runs 60 s after the last fill. Waits: no locals.
function fb_guard()
{
    level.mw4_fb_guard_on = 1;
    level.mw4_fb_over = 0;
    while ([[ &fb_elapsed ]](level.mw4_fb_guard_t0) < 60000)
    {
        wait 2;
        if (!isdefined(level.players) || [[ &fb_postgame ]]())
        {
            level.mw4_fb_guard_on = 0;
            return;
        }
        [[ &fb_guard_tick ]]();
    }
    level.mw4_fb_guard_on = 0;
}

function fb_guard_tick()
{
    // "Aus" leaves late lobby bots alone; a running apply decides itself.
    if (level.mw4_fb_busy || level.mw4_fb_target <= 0)
    {
        level.mw4_fb_over = 0;
        return;
    }
    extra = [[ &fb_count_bots ]]() - level.mw4_fb_target;
    if (extra > 0) level.mw4_fb_over = level.mw4_fb_over + 1;
    else level.mw4_fb_over = 0;
    if (level.mw4_fb_over >= 2)
    {
        [[ &fb_log ]]("lobby bots arrived late; dropping " + extra + " surplus bots");
        level.mw4_fb_over = 0;
        level.mw4_fb_busy = 1;
        level [[ &bots::function_de8785b022e0692e ]](extra);
        level.mw4_fb_busy = 0;
        if (level.mw4_fb_again) level thread [[ &fb_apply ]]();
    }
}

// ---------------------------------------------------------------- DEV 32: custom bot names

// 1 when the menu switched custom names on and a list exists; the list goes to level.mw4_fbn_list.
function fb_bn_on()
{
    level.mw4_fbn_list = [];
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bn_mode", 0) != 1) return 0;
    level.mw4_fbn_text = function_cf1241c266463447(@"mw4_botfix_bn_a", "") + "," + function_cf1241c266463447(@"mw4_botfix_bn_b", "")
        + "," + function_cf1241c266463447(@"mw4_botfix_bn_c", "");
    level.mw4_fbn_parts = function_8e6d6d99dbe52af1(level.mw4_fbn_text, ",");
    if (isdefined(level.mw4_fbn_parts)) level.mw4_fbn_list = level.mw4_fbn_parts;
    level.mw4_fbn_parts = undefined;
    if (level.mw4_fbn_list.size > 0) return 1;
    [[ &fb_log ]]("custom bot names are on, but no list was received (engine names)");
    return 0;
}

function fb_bn_used(name)
{
    level.mw4_fbn_u = name;
    for (level.mw4_fbn_j = 0; level.mw4_fbn_j < level.players.size; level.mw4_fbn_j++)
    {
        if (isdefined(level.players[level.mw4_fbn_j]) && level.players[level.mw4_fbn_j].name === level.mw4_fbn_u) return 1;
    }
    return 0;
}

// Next name of the list that no connected player has; when all are taken, the name with a number.
function fb_bn_next()
{
    if (!isdefined(level.mw4_fbn_pos)) level.mw4_fbn_pos = 0;
    if (!isdefined(level.mw4_fbn_dup)) level.mw4_fbn_dup = 1;
    for (level.mw4_fbn_try = 0; level.mw4_fbn_try < level.mw4_fbn_list.size; level.mw4_fbn_try++)
    {
        level.mw4_fbn_name = level.mw4_fbn_list[level.mw4_fbn_pos % level.mw4_fbn_list.size];
        level.mw4_fbn_pos++;
        if (![[ &fb_bn_used ]](level.mw4_fbn_name)) return level.mw4_fbn_name;
    }
    level.mw4_fbn_dup++;
    level.mw4_fbn_name = level.mw4_fbn_list[level.mw4_fbn_pos % level.mw4_fbn_list.size] + " " + level.mw4_fbn_dup;
    level.mw4_fbn_pos++;
    return level.mw4_fbn_name;
}

// Stock spawn_bots (bots.gsc:1548-1624) step by step with a named addbot. Waits: no locals (ACTS rule 1).
function fb_add_named(num, team, diffname)
{
    level.mw4_fbn_num = num;
    level.mw4_fbn_team = team;
    level.mw4_fbn_diff = diffname;
    level.var_bf3ce9ff992e6a4f = 1;                       // stock: bots are being added
    level.mw4_fbn_end = gettime() + 15000;
    level.mw4_fbn_wait = [];
    level.mw4_fbn_idx = 0;
    level.mw4_fbn_fail = 0;
    while (level.players.size < level [[ &bots_util::function_e8e82751e1da8206 ]]() && level.mw4_fbn_wait.size < level.mw4_fbn_num
        && gettime() < level.mw4_fbn_end)
    {
        wait 0.05;
        level.mw4_fbn_next = [[ &fb_bn_next ]]();
        level.mw4_fbn_bot = function_709cc358c725f922(level.mw4_fbn_next);   // addbot(name)
        if (!isdefined(level.mw4_fbn_bot))
        {
            level.mw4_fbn_fail++;
            wait 1;
            continue;
        }
        level.mw4_fbn_s = function_5c418f65db2e25e8();                          // spawnstruct
        level.mw4_fbn_s.var_65f30e0f33f34ee3 = level.mw4_fbn_bot;
        level.mw4_fbn_s.var_d8ba209dcfe18fe1 = 0;
        level.mw4_fbn_s.var_dad2ea86e867f2cc = 0;
        level.mw4_fbn_s.index = level.mw4_fbn_idx;
        level.mw4_fbn_s.var_3fcbf3566b3378a3 = level.mw4_fbn_diff;
        level.mw4_fbn_wait[level.mw4_fbn_wait.size] = level.mw4_fbn_s;
        level.mw4_fbn_idx++;
        level.mw4_fbn_s.var_65f30e0f33f34ee3 thread bots::function_123dbf2093db5dce(level.mw4_fbn_team, undefined, level.mw4_fbn_s);
    }
    level.mw4_fbn_end = gettime() + 60000;
    level.mw4_fbn_ready = 0;
    while (level.mw4_fbn_ready < level.mw4_fbn_wait.size && gettime() < level.mw4_fbn_end)
    {
        level.mw4_fbn_ready = 0;
        for (level.mw4_fbn_k = 0; level.mw4_fbn_k < level.mw4_fbn_wait.size; level.mw4_fbn_k++)
        {
            if (level.mw4_fbn_wait[level.mw4_fbn_k].var_d8ba209dcfe18fe1 || level.mw4_fbn_wait[level.mw4_fbn_k].var_dad2ea86e867f2cc)
                level.mw4_fbn_ready++;
        }
        wait 0.05;
    }
    level.var_bf3ce9ff992e6a4f = undefined;
    [[ &fb_log ]]("named add finished: " + level.mw4_fbn_wait.size + " bots added, " + level.mw4_fbn_ready + " ready, "
        + level.mw4_fbn_fail + " addbot failures");
}
