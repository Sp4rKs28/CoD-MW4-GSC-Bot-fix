// MW4 Botfix v1.2 release build (= menu GSC DEV 28, runtime-tested 2026-10-27; only the log prefix differs).
#using scripts\common\system;
#using scripts\common\utility;
#using scripts\common\ui;
#using script_74f99c09414692fa;      // common\weapon.gscc (namespace weapon)
#using script_6775ad452d13858;       // cp_mp\operator.gscc (namespace operator)
#using scripts\mp\teams;
#using scripts\mp\utility\weapon;    // DEV 23: mp\utility\weapon.gscc (namespace weapon: ammo filters)
#using scripts\mp\weapons;           // DEV 23: namespace_e7560f700c901627 (move speed recompute)
#using scripts\mp\equipment;         // DEV 23: namespace_c33cbcea986a02aa (lethal / tactical ammo)
#using script_fd32f08e72b657f;       // DEV 23: mp\gametypes\common.gscc (namespace_bce7aa9cc2eadaf, 2nd speed path)
#using script_3b64eb40368c1450;      // DEV 23: common\values.gscc (namespace_214d79f87f4bf971, val contexts)
#using scripts\mp\utility\player;    // DEV 23: namespace_5b53f19c893758d7 (_refreshfreezecontrols)
#using scripts\mp\class;             // DEV 25: namespace_9cc2bd30d111a0ae ("class" is an ACTS keyword): swapLoadout, preload
#using scripts\mp\utility\damage;    // DEV 25: damage::function_2fd1574113dfff1b (isFriendlyFire)
#namespace mw4_botfix_menu;

// Lua -> GSC: Engine.NotifyServer("splash_shown", value) -> stock ui.gsc registry -> menu_carrier.
//   917001..917006           ping/status (all/team/enemy)
//   9170000 + cmd*1000 + arg  settings: cmd 1 = bot class mask, 2 = bot fixed weapon,
//                                       3 = my skin, 4 = dump weapons/skins to the log
// GSC -> Lua: dvars mw4_botfix_allow / _fixed / _skin (+ _fixed_name / _skin_name labels,
//   _pool = comma list of the fixed-weapon roots, _skin_count = skins for my team).
// Dvars are written by GSC only, so the settings also survive into the next match.
// DEV 24: all on-screen texts in English (Henrik 2026-10-17).
// DEV 22: permanent Advanced UAV for the human player(s), never for bots (auav_* at the end);
//   dvar mw4_botfix_auav: 0 = off, 1 = on like a stock one (enemy Counter-UAV jams it),
//   2 = on and ignores enemy Counter-UAVs (default: Henrik wants it permanently active).
//   Like a real Advanced UAV it also switches the Ghost perk of his enemies off (auav_ghost).
// DEV 23: cmd 6-12 = player and bot settings (cfg_* block at the end): 6 Advanced UAV, 7 my health,
//   8 unlimited ammo, 9 my move speed, 10 bot difficulty, 11 bot health, 12 freeze bots.
// DEV 25 (Henrik 2026-10-24/25): weapon changes reach the bots at once (the stock pers loadout cache kept the
//   first spawn's weapon for the whole match); the My Skin list gets its size from the start; new cmd 13
//   headshots only, 14 bot respawn delay, 15-21 bot skins, 22-26 custom bot names (list for the fallback).
// DEV 26: bot name payload values 10000000 + 3 chars of 6 bits (below 2^24, exact even if the engine hands the
//   value on as a 32-bit float; DEV 25 used values above 2^30).
// DEV 27: Henrik: "a few bots still do not have the selected weapon". Bot weapons now cover the cases DEV 25/26
//   missed: a loadout whose primary is fists or failed to build (skipped before the signature, so never refreshed),
//   Fixed Weapon with an own second gun in the secondary slot (now a pistol), bots that run the fixed gun dry and
//   switch away (reserve kept full, back to the fixed gun), bots that could not swap at the moment of the change
//   (retried), and bots whose own primary already was the fixed root (rebuilt plain like the others).
// DEV 28 (Henrik 2026-10-26): bot difficulty and bot health per side (cmd 10/11 = bots on my team, new cmd 27/28 =
//   enemy bots; FFA: every bot is an enemy), cmd 29 bot unlimited ammo (reserve of primary and secondary kept
//   full), cmd 30 reset every BOTFIX setting to its default.

function private autoexec __init__system__()
{
    function_8b17726cc97055("MW4 Botfix v1.2 menu: autoexec entered");
    system::register(#"mw4_botfix_menu", undefined, &__init__, undefined);
}

function __init__()
{
    utility::function_fb7b1af19016b7f4("StartGameTypeCallbackFinished");
    level ui::function_96f4ffdd8248ddf3("splash_shown", &menu_carrier);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_allow", -1) < 0)
        function_b45d7cc91040f5d3(@"mw4_botfix_allow", 63);   // everything except shotguns
    // Single-slot loadout struct hook (class.gsc:5802); keep any previous owner chained.
    if (!isdefined(level.mw4_lr_installed))
    {
        level.mw4_lr_installed = 1;
        level.mw4_lr_prev = level.var_1f72e89d9af3c430;
        level.var_1f72e89d9af3c430 = &lr_struct_hook;
    }
    level.mw4_lr_logs = 0;
    level.mw4_lr_nd = 0;   // DEV 27: counters exist before any refresh or watchdog pass
    level.mw4_lr_ns = 0;
    level.mw4_lr_nw = 0;
    level.mw4_bb_n = 0;
    [[ &lr_publish ]]();
    [[ &cfg_defaults ]]();
    [[ &bs_init ]]();
    [[ &bn_init ]]();
    function_b45d7cc91040f5d3(@"mw4_botfix_menu_ready", 28);
    function_8b17726cc97055("MW4 Botfix v1.2 menu: ready; bot class mask=" + function_b4b0c0cb1ac2b968(@"mw4_botfix_allow", 63)
        + " fixed=" + function_b4b0c0cb1ac2b968(@"mw4_botfix_fixed", 0) + " skin=" + function_b4b0c0cb1ac2b968(@"mw4_botfix_skin", 0));
    level thread [[ &auav_main ]]();
    level thread [[ &cfg_main ]]();
}

// Stock ui.gsc registry callback (self = the player who pressed the button).
// Only reserved values count; genuine splash_shown values are ignored.
function menu_carrier(value)
{
    if (!isdefined(self) || !isdefined(value)) return;
    if (value >= 10000000 && value < 10262144)
    {
        [[ &bn_payload ]](value);   // bot names payload
        return;
    }
    for (i = 1; i <= 6; i++)
    {
        if (value === 917000 + i)
        {
            self [[ &menu_request ]](i);
            return;
        }
    }
    if (!(value >= 9170000 && value < 9270000)) return;
    cmd = int((value - 9170000) / 1000);
    arg = value - 9170000 - cmd * 1000;
    if (cmd >= 22 && cmd <= 26)
    {
        [[ &bn_command ]](cmd, arg);   // bot names: logs a summary itself
        return;
    }
    function_8b17726cc97055("MW4 Botfix v1.2 menu: command " + cmd + " arg=" + arg);
    if (cmd == 1) [[ &lr_set_mask ]](arg);
    else if (cmd == 2) [[ &lr_set_fixed ]](arg);
    else if (cmd == 3) self [[ &skin_set ]](arg);
    else if (cmd == 4) [[ &lr_dump ]]();
    else if (cmd >= 6 && cmd <= 14) [[ &cfg_set ]](cmd, arg);   // cmd 5 belongs to mw4_bot_fallback
    else if (cmd >= 15 && cmd <= 21) self [[ &bs_set ]](cmd, arg);
    else if (cmd >= 27 && cmd <= 29) [[ &cfg_set ]](cmd, arg);   // DEV 28: enemy bot difficulty / health, bot ammo
    else if (cmd == 30) self [[ &cfg_reset ]]();                 // DEV 28: reset all
}

function menu_request(value)
{
    if (!isdefined(self) || !isdefined(value)) return;
    if (value === 1) value = "ping:all";
    else if (value === 2) value = "ping:team";
    else if (value === 3) value = "ping:enemy";
    else if (value === 4) value = "status:all";
    else if (value === 5) value = "status:team";
    else if (value === 6) value = "status:enemy";
    else return;
    function_8b17726cc97055("MW4 Botfix v1.2 menu: request accepted; value=" + value);
    now = gettime();
    if (isdefined(self.mw4_menu_request_time) && now - self.mw4_menu_request_time < 500) return;
    self.mw4_menu_request_time = now;
    if (value == "ping:all" || value == "ping:team" || value == "ping:enemy")
    {
        IPrintLn("MW4 MENU: Lua -> GSC connection OK");
        function_8b17726cc97055("MW4 MENU: Lua -> GSC connection OK");
        return;
    }
    count = 0;
    alive = 0;
    if (isdefined(level.var_10f4ff41c4b7f0ac))
    {
        foreach (bot in level.var_10f4ff41c4b7f0ac)
        {
            if (!isdefined(bot) || !isdefined(bot.var_3215388132e3d9b5)) continue;
            if (value != "status:all")
            {
                if (!isdefined(self.team) || !isdefined(bot.team)) continue;
                if (value == "status:team" && bot.team != self.team) continue;
                if (value == "status:enemy" && bot.team == self.team) continue;
            }
            count++;
            if (isdefined(bot.var_d2c854047ddd1dbc) && bot.var_d2c854047ddd1dbc > 0
                && isdefined(bot.var_948fe687565941e7) && bot.var_948fe687565941e7 == "playing") alive++;
        }
    }
    IPrintLn("MW4 MENU: bots=" + count + " alive=" + alive);
    function_8b17726cc97055("MW4 MENU: " + value + " bots=" + count + " alive=" + alive);
}

// ---------------------------------------------------------------- loadout restrictions (bots only)

// Primary weapon groups; bit i of mw4_botfix_allow belongs to entry i (same order in the Lua menu).
function lr_groups()
{
    return ["weapon_assault", "weapon_smg", "weapon_battle", "weapon_dmr", "weapon_lmg", "weapon_sniper", "weapon_shotgun"];
}

function lr_is_bot()
{
    return function_aad3cad3abf3c14f(self) || isdefined(self.var_3215388132e3d9b5);
}

function lr_group(root)
{
    if (!isdefined(root) || root == "none") return "none";
    g = weapon::function_c3a18631f7595e9d(weapon::function_f541f60718130d5d(root));
    if (!isdefined(g)) return "other";
    return g;
}

// 1 = allowed, 0 = blocked, -1 = not a restrictable primary group.
function lr_group_state(g, mask)
{
    groups = [[ &lr_groups ]]();
    bit = 1;
    for (i = 0; i < groups.size; i++)
    {
        if (groups[i] == g)
        {
            if (mask & bit) return 1;
            return 0;
        }
        bit = bit * 2;
    }
    return -1;
}

// All primaries in fixed group order; index 1..size is the "fixed weapon" number.
function lr_primary_pool(mask)
{
    pool = [];
    groups = [[ &lr_groups ]]();
    bit = 1;
    for (i = 0; i < groups.size; i++)
    {
        if (mask < 0 || (mask & bit))
        {
            list = level.var_a5104b3f2543a0b1[groups[i]];   // built by weapon.gscc at load
            if (isdefined(list))
                foreach (r in list) pool[pool.size] = r;
        }
        bit = bit * 2;
    }
    return pool;
}

function lr_build(root)
{
    if (!isdefined(root)) return undefined;
    return weapon::function_5416d4273f081ce2(root, [], "camo_none", "none", -1);
}

function lr_log(text)
{
    if (level.mw4_lr_logs >= 40) return;
    level.mw4_lr_logs++;
    function_8b17726cc97055("MW4 Botfix v1.2 menu: " + text);
}

// Runs for every loadout struct build, after the weapon objects are built and before they are
// given (class.gsc:5795-5804). Must not wait. Bots only; human players are untouched.
function lr_struct_hook(struct)
{
    if (isdefined(level.mw4_lr_prev)) self [[ level.mw4_lr_prev ]](struct);
    if (!isdefined(self) || !isdefined(struct)) return;
    if (!self [[ &lr_is_bot ]]())
    {
        if (!isdefined(self.mw4_skin_watch))
        {
            self.mw4_skin_watch = 1;
            self thread [[ &skin_watch ]]();
        }
        return;
    }
    // DEV 25: bot skins: no class-table operator in a bot loadout while the custom mode is on (class.gsc:3581-3591)
    if (!isdefined(level.mw4_lr_oplog))
    {
        level.mw4_lr_oplog = 1;
        [[ &lr_log ]]("bot loadout operator field defined=" + isdefined(struct.operator));
    }
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_mode", 0) > 0) struct.operator = undefined;
    // DEV 27: juggernaut and game-mode loadouts stay stock. A gun primary is handled, and so is a loadout whose
    // primary is fists (stock turns "none" into fists, class.gsc:5829-5832) or failed to build: DEV 26 returned for
    // those before writing the signature, so they were never refreshed and never got a menu weapon. Pistol,
    // launcher, minigun and super structs stay stock.
    if (istrue(self.var_e5cc746798bed3ae)) return;                          // juggernaut (set before its build, juggernaut.gsc:277)
    if (isdefined(self.var_8b69ecbd466a79fa["gamemodeLoadout"])) return;   // game-mode loadout (class.gsc:4896)
    gun = 0;
    if (isdefined(struct.var_94d0f8ea18599de3) && weapon::function_fa3f875be1c8ccc6(struct.var_94d0f8ea18599de3)) gun = 1;
    ingroup = 0;   // the root is in one of the menu's primary groups (also DMRs the class test does not count)
    if (isdefined(struct.loadoutPrimary) && [[ &lr_group_state ]]([[ &lr_group ]](struct.loadoutPrimary), 127) >= 0) ingroup = 1;
    if (ingroup && isdefined(struct.var_94d0f8ea18599de3)) gun = 1;
    bare = 0;
    if (ingroup && !isdefined(struct.var_94d0f8ea18599de3)) bare = 1;   // its own gun failed to build
    else if (isdefined(struct.loadoutPrimary) && weapon::function_c3c1af0e6d1b8440(struct.loadoutPrimary)) bare = 1;   // fists
    if (!gun && !bare) return;
    mask = function_b4b0c0cb1ac2b968(@"mw4_botfix_allow", 63);
    fixed = function_b4b0c0cb1ac2b968(@"mw4_botfix_fixed", 0);
    self.var_8b69ecbd466a79fa["mw4_lr_sig"] = mask * 100 + fixed;   // DEV 25: settings this cached loadout was built with
    old = struct.loadoutPrimary;
    oldtxt = "none";
    if (isdefined(old)) oldtxt = old;
    if (bare) [[ &lr_log ]]("bot loadout without a gun primary (" + oldtxt + "), replacing it");
    root = undefined;
    pool = [];
    if (fixed > 0)
    {
        pool = [[ &lr_primary_pool ]](-1);
        if (pool.size > 0) root = pool[(fixed - 1) % pool.size];
    }
    else if (bare || [[ &lr_group_state ]]([[ &lr_group ]](old), mask) == 0)
    {
        pool = [[ &lr_primary_pool ]](mask);
        if (pool.size > 0) root = pool[randomint(pool.size)];
    }
    // Fixed: always rebuilt, so a bot whose own primary already is the fixed root gets the same plain gun as the others.
    if (isdefined(root) && (fixed > 0 || bare || !(root === old)))
    {
        obj = [[ &lr_build ]](root);
        if (!isdefined(obj) && fixed <= 0 && pool.size > 1)
        {
            root = pool[randomint(pool.size)];   // one more random pick if this root did not build
            obj = [[ &lr_build ]](root);
        }
        if (isdefined(obj))
        {
            struct.loadoutPrimary = root;
            struct.var_ff077cf4a9b27c36 = [];                     // attachments
            struct.loadoutPrimaryCamo = "camo_none";
            struct.loadoutPrimaryReticle = "none";
            struct.loadoutPrimaryVariantID = -1;
            struct.var_8c5510d3e892e9c5 = [];
            struct.loadoutPrimaryCosmeticAttachment = "charm_none";
            struct.var_94d0f8ea18599de3 = obj;
            struct.var_de84608151bccb72 = getcompleteweaponname(obj);
            if (!(root === old)) [[ &lr_log ]]("bot primary " + oldtxt + " -> " + root);
        }
        else [[ &lr_log ]]("bot primary " + root + " did not build, " + oldtxt + " stays");
    }
    // The secondary becomes a pistol when its group is blocked (e.g. an overkill shotgun), and with Fixed Weapon
    // when it is an own second gun (rifle/mg/sniper/smg/spread object); fists filler, melee, pistols and launchers stay.
    second = struct.loadoutSecondary;
    sg = "none";
    if (isdefined(second) && second != "none") sg = [[ &lr_group ]](second);
    swap2 = 0;
    if ([[ &lr_group_state ]](sg, mask) == 0) swap2 = 1;
    if (fixed > 0 && isdefined(struct.var_c817e40959fa971b) && weapon::function_fa3f875be1c8ccc6(struct.var_c817e40959fa971b)) swap2 = 1;
    if (swap2)
    {
        pistols = level.var_a5104b3f2543a0b1["weapon_pistol"];
        if (isdefined(pistols) && pistols.size > 0)
        {
            root = pistols[randomint(pistols.size)];
            obj = [[ &lr_build ]](root);
            if (isdefined(obj))
            {
                struct.loadoutSecondary = root;
                struct.var_644954038b94494e = [];
                struct.loadoutSecondaryCamo = "camo_none";
                struct.loadoutSecondaryReticle = "none";
                struct.loadoutSecondaryVariantID = -1;
                struct.var_6dd2fa8f61606fcd = [];
                struct.loadoutSecondaryCosmeticAttachment = "charm_none";
                struct.var_c817e40959fa971b = obj;
                struct.var_b714cc31313c18ca = getcompleteweaponname(obj);
                [[ &lr_log ]]("bot secondary " + second + " -> " + root);
            }
        }
    }
}

function lr_set_mask(mask)
{
    if (mask < 0 || mask > 127) return;
    function_b45d7cc91040f5d3(@"mw4_botfix_allow", mask);
    [[ &lr_publish ]]();
    IPrintLn("MW4 MENU: bot weapon classes updated");
    [[ &lr_refresh_bots ]]();
}

function lr_set_fixed(index)
{
    pool = [[ &lr_primary_pool ]](-1);
    if (index < 0 || index > pool.size) index = 0;
    function_b45d7cc91040f5d3(@"mw4_botfix_fixed", index);
    [[ &lr_publish ]]();
    if (index == 0) IPrintLn("MW4 MENU: bot fixed weapon off");
    else IPrintLn("MW4 MENU: bot fixed weapon " + index + "/" + pool.size + " " + pool[index - 1]);
    [[ &lr_refresh_bots ]]();
}

// Labels for the Lua buttons.
function lr_publish()
{
    fixed = function_b4b0c0cb1ac2b968(@"mw4_botfix_fixed", 0);
    name = "Off";
    if (fixed > 0)
    {
        pool = [[ &lr_primary_pool ]](-1);
        if (pool.size > 0) name = pool[(fixed - 1) % pool.size];
    }
    function_b45d7cc91040f5d3(@"mw4_botfix_fixed_name", name);
    pool = [[ &lr_primary_pool ]](-1);
    list = "";
    foreach (r in pool)
    {
        if (list != "") list = list + ",";
        list = list + r;
    }
    function_b45d7cc91040f5d3(@"mw4_botfix_pool", list);
    skin = function_b4b0c0cb1ac2b968(@"mw4_botfix_skin", 0);
    label = "Default";
    count = function_b4b0c0cb1ac2b968(@"mw4_botfix_skin_count", 0);
    if (skin > 0) label = "" + skin;
    if (skin > 0 && count > 0) label = "" + skin + "/" + count;
    function_b45d7cc91040f5d3(@"mw4_botfix_skin_name", label);
}

function lr_dump()
{
    pool = [[ &lr_primary_pool ]](-1);
    groups = [[ &lr_groups ]]();
    n = 0;
    foreach (g in groups)
    {
        list = level.var_a5104b3f2543a0b1[g];
        if (!isdefined(list)) continue;
        foreach (r in list)
        {
            n++;
            function_8b17726cc97055("MW4 Botfix v1.2 menu: weapon " + n + " " + g + " " + r);
        }
    }
    pistols = level.var_a5104b3f2543a0b1["weapon_pistol"];
    if (isdefined(pistols))
        foreach (r in pistols) function_8b17726cc97055("MW4 Botfix v1.2 menu: pistol " + r);
    foreach (team in ["allies", "axis"])
    {
        pairs = [[ &skin_pairs ]](team);
        function_8b17726cc97055("MW4 Botfix v1.2 menu: skins " + team + " count=" + pairs.size);
    }
    IPrintLn("MW4 MENU: " + pool.size + " weapons written to the log");
}

// ---------------------------------------------------------------- my skin (human players only)

// Operator/skin refs are hashes in MW4, so skins are picked by number from the match pool.
function skin_pairs(team)
{
    pairs = [];
    operator::function_99f3495eb915fb96();
    if (!isdefined(level.var_77fb663123a79288)) return pairs;
    pool = level.var_77fb663123a79288[team];
    if (!isdefined(pool)) return pairs;
    foreach (op, skins in pool)
    {
        foreach (s in skins)
        {
            p = [];
            p[0] = op;
            p[1] = s;
            pairs[pairs.size] = p;
        }
    }
    return pairs;
}

function skin_team()
{
    if (isdefined(self.team) && (self.team == "allies" || self.team == "axis")) return self.team;
    return "allies";
}

function skin_set(index)
{
    if (self [[ &lr_is_bot ]]()) return;
    pairs = [[ &skin_pairs ]](self [[ &skin_team ]]());
    if (index < 0 || index > pairs.size) index = 0;
    function_b45d7cc91040f5d3(@"mw4_botfix_skin", index);
    function_b45d7cc91040f5d3(@"mw4_botfix_skin_count", pairs.size);
    [[ &lr_publish ]]();
    self [[ &skin_apply ]]();
    if (index == 0) IPrintLn("MW4 MENU: skin reset to your loadout");
    else IPrintLn("MW4 MENU: skin " + index + "/" + pairs.size);
    function_8b17726cc97055("MW4 Botfix v1.2 menu: skin " + index + "/" + pairs.size);
}

function skin_apply()
{
    if (!isdefined(self)) return;
    index = function_b4b0c0cb1ac2b968(@"mw4_botfix_skin", 0);
    if (index <= 0)
    {
        self operator::function_8a20b5520866f917();   // back to the player's own selection
        self teams::function_1a7cd43628ac2797();
        return;
    }
    pairs = [[ &skin_pairs ]](self [[ &skin_team ]]());
    if (pairs.size == 0) return;
    p = pairs[(index - 1) % pairs.size];
    self operator::function_8a20b5520866f917(p[0], p[1]);
    self teams::function_1a7cd43628ac2797();
}

// Re-applies the chosen skin after every loadout (spawn, team change, class change).
function skin_watch()
{
    while (isdefined(self))
    {
        self waittill("giveLoadout");
        waitframe();
        if (!isdefined(self)) return;
        if (function_b4b0c0cb1ac2b968(@"mw4_botfix_skin", 0) > 0) self [[ &skin_apply ]]();
    }
}

// ---------------------------------------------------------------- permanent Advanced UAV (human players only)
// The stock Advanced UAV (killstreak "directional_uav") only raises team counters (uav.gsc:1113-1174);
// on every level "uav_update" the stock updater (uav.gsc:248-311, FFA 1475-1548) turns them into five
// engine client fields plus the omnvar "ui_radar_blocked" (uav.gsc:2037-2042). An active Advanced UAV
// means strength getuavstrengthmax(): radarstrength max, isradarblocked 0, hasradar 1,
// radarshowenemydirection 1, radarmode "constant_radar" (uav.gsc:1842-1911).
// Here each human player gets exactly that state directly, the per-player pattern of stock hvt
// (script_43c9482a4b303776.gsc:717-740). Both stock skip flags keep the updaters away from him
// (var_7bbc45fa0011e94c: uav.gsc:291 + 1481, skipuavupdate: uav.gsc:296). No aircraft, voice line,
// splash, score event or team counter, so bots (allied ones too) get nothing.
// Watchdog every 0.5 s plus one pass a frame after every "uav_update" (every player_spawned fires one:
// uav_mp.gsc:90 -> uav.gsc:836-839). Fields are written only when they differ; the omnvars are sent
// again after each "uav_update". Stops at postgame; each match/round runs a new script instance.
// An enemy Jammer field upgrade always wins (stock leaves jammed players alone too, uav.gsc:301-307);
// an enemy Counter-UAV jams it like a real one unless mw4_botfix_auav is 2.
// No locals anywhere in this block (ACTS store loss after wait / builtin method): state is in fields.

function auav_log(text)
{
    function_8b17726cc97055("MW4 Botfix v1.2 menu: " + text);
}

function auav_postgame()
{
    return isdefined(game["state"]) && game["state"] == "postgame";
}

function auav_name()
{
    if (isdefined(level.mw4_auav_p.var_6b09472177ca8529)) return "" + level.mw4_auav_p.var_6b09472177ca8529;
    return "?";
}

function auav_main()
{
    if (isdefined(level.mw4_auav_run)) return;
    level.mw4_auav_run = 1;
    level.mw4_auav_t0 = gettime();
    level.mw4_auav_users = 0;
    level.mw4_auav_fixes = 0;
    level.mw4_auav_resend = 0;
    level.mw4_auav_kick = 0;
    level.mw4_auav_log_wait = 0;
    level.mw4_auav_log_off = 0;
    level.mw4_auav_log_fix = 0;
    level.mw4_auav_log_cuav = 0;
    level.mw4_auav_log_jam = 0;
    level.mw4_auav_log_ghost = 0;
    level.mw4_auav_ghosts = 0;
    level thread [[ &auav_spawn_watch ]]();
    while (![[ &auav_postgame ]]())
    {
        [[ &auav_tick ]]();
        wait 0.5;
    }
    [[ &auav_log ]]("advanced UAV stopped (postgame); players=" + level.mw4_auav_users
        + " re-applied after a reset=" + level.mw4_auav_fixes + " enemies with Ghost revealed=" + level.mw4_auav_ghosts);
}

// Fast path: one pass a frame after every stock "uav_update" (spawns, UAV / Counter-UAV start and end).
function auav_spawn_watch()
{
    while (![[ &auav_postgame ]]())
    {
        level waittill("uav_update");
        waitframe();
        if ([[ &auav_postgame ]]()) return;
        level.mw4_auav_resend = 1;
        [[ &auav_tick ]]();
    }
}

function auav_tick()
{
    level.mw4_auav_mode = function_b4b0c0cb1ac2b968(@"mw4_botfix_auav", 2);
    // uav::init caches the strength levels (uav.gsc:319-320); without them the stock radar is not running.
    if (!isdefined(level.var_10c7c673ad23cef1) || !isdefined(level.var_88a109262bdf26c8))
    {
        if (!level.mw4_auav_log_wait && gettime() - level.mw4_auav_t0 > 30000)
        {
            level.mw4_auav_log_wait = 1;
            [[ &auav_log ]]("advanced UAV FAILED: stock uav script not initialised after 30 s, nothing changed");
        }
        return;
    }
    if (level.mw4_auav_mode <= 0 && !level.mw4_auav_log_off)
    {
        level.mw4_auav_log_off = 1;
        [[ &auav_log ]]("advanced UAV off (dvar mw4_botfix_auav=" + level.mw4_auav_mode + ")");
    }
    if (isdefined(level.var_10f4ff41c4b7f0ac))
    {
        for (level.mw4_auav_i = 0; level.mw4_auav_i < level.var_10f4ff41c4b7f0ac.size; level.mw4_auav_i++)
        {
            level.mw4_auav_p = level.var_10f4ff41c4b7f0ac[level.mw4_auav_i];
            [[ &auav_player ]]();
        }
    }
    level.mw4_auav_p = undefined;
    [[ &auav_ghost ]]();
    level.mw4_auav_resend = 0;
    if (level.mw4_auav_kick)
    {
        level.mw4_auav_kick = 0;
        level notify("uav_update");   // released players go back to the stock updater
    }
}

function auav_player()
{
    if (!isdefined(level.mw4_auav_p) || !isdefined(level.mw4_auav_p.team)) return;
    if (level.mw4_auav_p [[ &lr_is_bot ]]()) return;   // bots are never touched
    if (level.mw4_auav_mode <= 0)
    {
        [[ &auav_release ]]();
        return;
    }
    if (level.mw4_auav_p.team == "spectator" || level.mw4_auav_p.team == "codcaster")
    {
        [[ &auav_release ]]();
        return;
    }
    level.mw4_auav_p.var_7bbc45fa0011e94c = 1;   // skip flag of both stock updaters (uav.gsc:291, 1481)
    level.mw4_auav_p.var_d012effbad8f9e9e = 1;   // skipuavupdate (uav.gsc:296)
    if (isdefined(level.mw4_auav_p.var_3702583f19e5f23b) && level.mw4_auav_p.var_3702583f19e5f23b.size > 0)
    {
        // Jammed by an enemy Jammer: its own code owns radarstrength now (script_13b1a965a4983a38.gsc:617-675).
        level.mw4_auav_p.mw4_auav_state = "jammer";
        if (!level.mw4_auav_log_jam)
        {
            level.mw4_auav_log_jam = 1;
            [[ &auav_log ]]("advanced UAV paused for " + [[ &auav_name ]]() + ": enemy jammer (first time this match)");
        }
        return;
    }
    [[ &auav_enemy_cuav ]]();
    if (level.mw4_auav_cuav > 0 && level.mw4_auav_mode == 1)
    {
        [[ &auav_write_blocked ]]();
        return;
    }
    [[ &auav_write_on ]]();
}

// Enemy Counter-UAVs as the stock strength code counts them (uav.gsc:1814, 1488, 2235-2259).
function auav_enemy_cuav()
{
    level.mw4_auav_cuav = 0;
    if (!isdefined(level.var_259a3be9c1f34caf) || level.var_259a3be9c1f34caf <= 0) return;
    level.mw4_auav_cuav = level.var_259a3be9c1f34caf;
    level.mw4_auav_idx = level.mw4_auav_p.team;
    if (!istrue(level.var_ea49630c4e66000a)) level.mw4_auav_idx = level.mw4_auav_p.var_a42cb00cbc122327;
    else if (istrue(level.var_f3d1cde89907a07a)) level.mw4_auav_idx = level.mw4_auav_p.var_f18a5c28d4e5f769;
    if (isdefined(level.var_d098d36bf9047255) && isdefined(level.mw4_auav_idx)
        && isdefined(level.var_d098d36bf9047255[level.mw4_auav_idx]))
        level.mw4_auav_cuav = level.mw4_auav_cuav - level.var_d098d36bf9047255[level.mw4_auav_idx];
}

// Advanced UAV state = stock function_17f80789924009af(getuavstrengthmax()) applied as in uav.gsc:2037-2042.
function auav_write_on()
{
    level.mw4_auav_ok = level.mw4_auav_p.var_94652e88e1b160e3 == level.var_10c7c673ad23cef1
        && !istrue(level.mw4_auav_p.var_2871df7b7c46d392) && istrue(level.mw4_auav_p.var_573590ba78eec996)
        && istrue(level.mw4_auav_p.var_31a64604735cb39a) && level.mw4_auav_p.var_f1277d62863cbd29 == "constant_radar";
    // Lobby without minimap (gamelogic.gsc:4009, class.gsc:8991-8998): show it, as a stock UAV does;
    // every pass, because the stock spawn code hides it again.
    if (isdefined(level.var_aa1263d5fde5f4f2) && !level.var_aa1263d5fde5f4f2)
        level.mw4_auav_p function_978ffd9566c7439e("ui_hide_minimap", 0);
    level.mw4_auav_hum = level.mw4_auav_p;
    if (level.mw4_auav_ok && level.mw4_auav_p.mw4_auav_state === "on" && !level.mw4_auav_resend) return;
    if (!level.mw4_auav_ok && level.mw4_auav_p.mw4_auav_state === "on")
    {
        level.mw4_auav_fixes++;
        if (!level.mw4_auav_log_fix)
        {
            level.mw4_auav_log_fix = 1;
            [[ &auav_log ]]("advanced UAV re-applied for " + [[ &auav_name ]]() + " (first time this match): fields were strength="
                + level.mw4_auav_p.var_94652e88e1b160e3 + " blocked=" + level.mw4_auav_p.var_2871df7b7c46d392
                + " hasradar=" + level.mw4_auav_p.var_573590ba78eec996 + " dir=" + level.mw4_auav_p.var_31a64604735cb39a
                + " mode=" + level.mw4_auav_p.var_f1277d62863cbd29);
        }
    }
    level.mw4_auav_p.var_94652e88e1b160e3 = level.var_10c7c673ad23cef1;   // radarstrength = getuavstrengthmax()
    level.mw4_auav_p.var_2871df7b7c46d392 = 0;                           // isradarblocked
    level.mw4_auav_p.var_573590ba78eec996 = 1;                           // hasradar
    level.mw4_auav_p.var_31a64604735cb39a = 1;                           // radarshowenemydirection
    level.mw4_auav_p.var_f1277d62863cbd29 = "constant_radar";            // radarmode
    level.mw4_auav_p.mw4_auav_state = "on";
    level.mw4_auav_p function_978ffd9566c7439e("ui_radar_blocked", 0);
    if (!isdefined(level.mw4_auav_p.mw4_auav_logged))
    {
        level.mw4_auav_p.mw4_auav_logged = 1;
        level.mw4_auav_users++;
        [[ &auav_log ]]("advanced UAV on for " + [[ &auav_name ]]() + " (team=" + level.mw4_auav_p.team
            + " teambased=" + istrue(level.var_ea49630c4e66000a) + " strength=" + level.mw4_auav_p.var_94652e88e1b160e3
            + " mode=" + level.mw4_auav_p.var_f1277d62863cbd29 + " dvar=" + level.mw4_auav_mode + ")");
    }
}

// Enemy Counter-UAV: stock state for strength getuavstrengthmin() (uav.gsc:1863-1866, 1884-1911).
function auav_write_blocked()
{
    if (level.mw4_auav_p.mw4_auav_state === "cuav" && !level.mw4_auav_resend
        && level.mw4_auav_p.var_94652e88e1b160e3 == level.var_88a109262bdf26c8
        && istrue(level.mw4_auav_p.var_2871df7b7c46d392)) return;
    level.mw4_auav_p.var_94652e88e1b160e3 = level.var_88a109262bdf26c8;
    level.mw4_auav_p.var_2871df7b7c46d392 = 1;
    level.mw4_auav_p.var_573590ba78eec996 = 0;
    level.mw4_auav_p.var_31a64604735cb39a = 0;
    level.mw4_auav_p.var_f1277d62863cbd29 = "normal_radar";
    level.mw4_auav_p.mw4_auav_state = "cuav";
    level.mw4_auav_p function_978ffd9566c7439e("ui_radar_blocked", 1);
    if (!level.mw4_auav_log_cuav)
    {
        level.mw4_auav_log_cuav = 1;
        [[ &auav_log ]]("advanced UAV jammed for " + [[ &auav_name ]]()
            + " by an enemy Counter-UAV (first time this match; mw4_botfix_auav 2 ignores Counter-UAVs)");
    }
}

// Switched off: give the player back to the stock updater.
function auav_release()
{
    if (!isdefined(level.mw4_auav_p.mw4_auav_state)) return;
    level.mw4_auav_p.var_7bbc45fa0011e94c = undefined;
    level.mw4_auav_p.var_d012effbad8f9e9e = undefined;
    level.mw4_auav_p.var_2871df7b7c46d392 = 0;   // the FFA updater never writes it (uav.gsc:1475-1548)
    level.mw4_auav_p.var_31a64604735cb39a = 0;   // as at the end of a stock directional UAV (uav.gsc:1351-1373)
    level.mw4_auav_p.mw4_auav_state = undefined;
    level.mw4_auav_kick = 1;
    [[ &auav_log ]]("advanced UAV released for " + [[ &auav_name ]]() + " (dvar mw4_botfix_auav=" + level.mw4_auav_mode + ")");
}

// A real Advanced UAV switches the Ghost perk of the enemies off while it is active (specialty_ghost,
// script_88ea1ece4b24953.gsc:245-301): enemy self function_6c3ad272698e3e5e(!bundle flag) and
// self function_536edb64c5a120ba(0). The team counters it reads are not raised here (allied bots would
// get the radar), so the same two calls are made on every enemy that has the perk (marker
// var_87e24c0db4be12c4, set when the perk is given: :37, removed: :123). The perk code sets the
// state again on spawn and after firing (:88, :158); the watchdog repeats it within 0.5 s.
function auav_ghost()
{
    if (!isdefined(level.mw4_auav_hum) || !isdefined(level.var_10f4ff41c4b7f0ac)) return;
    if (!(level.mw4_auav_hum.mw4_auav_state === "on")) return;
    level.mw4_auav_gflag = 0;
    if (isdefined(level.var_93817cbeded9a978) && isdefined(level.var_93817cbeded9a978.var_5ee8074ece2d3715)
        && isdefined(level.var_93817cbeded9a978.var_5ee8074ece2d3715["directional_uav"]))
        level.mw4_auav_gflag = istrue(level.var_93817cbeded9a978.var_5ee8074ece2d3715["directional_uav"].var_c354011303a999d9);
    for (level.mw4_auav_j = 0; level.mw4_auav_j < level.var_10f4ff41c4b7f0ac.size; level.mw4_auav_j++)
    {
        level.mw4_auav_q = level.var_10f4ff41c4b7f0ac[level.mw4_auav_j];
        if (!isdefined(level.mw4_auav_q) || level.mw4_auav_q == level.mw4_auav_hum) continue;
        if (!isdefined(level.mw4_auav_q.var_87e24c0db4be12c4)) continue;   // no Ghost perk
        if (istrue(level.var_ea49630c4e66000a) && level.mw4_auav_q.team == level.mw4_auav_hum.team) continue;
        level.mw4_auav_q function_6c3ad272698e3e5e(!level.mw4_auav_gflag);
        level.mw4_auav_q function_536edb64c5a120ba(0);
        if (!isdefined(level.mw4_auav_q.mw4_auav_ghost))
        {
            level.mw4_auav_q.mw4_auav_ghost = 1;
            level.mw4_auav_ghosts++;
        }
        if (!level.mw4_auav_log_ghost)
        {
            level.mw4_auav_log_ghost = 1;
            if (isdefined(level.mw4_auav_q.var_6b09472177ca8529))
                [[ &auav_log ]]("advanced UAV: Ghost of enemy " + level.mw4_auav_q.var_6b09472177ca8529
                    + " switched off (first time this match)");
            else [[ &auav_log ]]("advanced UAV: Ghost of an enemy switched off (first time this match)");
        }
    }
    level.mw4_auav_q = undefined;
}

// ---------------------------------------------------------------- DEV 23: player and bot settings (cmd 6-12)
// Lua sends 9170000 + cmd*1000 + arg; menu_carrier -> cfg_set checks the range, writes the dvar (it lives for
// the game session, so the setting carries into the next match), logs one line and applies it at once.
//   cmd 6  Advanced UAV    0 off, 2 on (1 = on, enemy Counter-UAV jams)             mw4_botfix_auav   (default 2)
//   cmd 7  my health       0 standard, 1 150, 2 200, 3 300, 4 500, 5 invulnerable    mw4_botfix_hp     (default 0)
//   cmd 8  unlimited ammo  0 off, 1 on                                              mw4_botfix_ammo   (default 0)
//   cmd 9  my move speed   0 100 %, 1 110 %, 2 125 %, 3 150 %                       mw4_botfix_speed  (default 0)
//   cmd 10 bot difficulty  0 lobby (untouched), 1 recruit, 2 regular, 3 hardened, 4 veteran   mw4_botfix_bdiff (0)
//   cmd 11 bot health      0 standard, 1 50, 2 150, 3 200, 4 300                    mw4_botfix_bhp    (default 0)
//   cmd 12 freeze bots     0 off, 1 on                                              mw4_botfix_freeze (default 0)
// "my" settings go to human players only, bot settings to every bot (lr_is_bot: isbot or bot_team field;
// the bot builtins only on real bot clients). cfg_main is one watchdog: every 0.25 s plus one pass a frame
// after every level "uav_update" (each player_spawned fires one, see the AUAV block). It reads the dvars on
// every pass. Each change is marked on the entity (in pers where it must survive a round restart), so
// standard/off gives the stock state back exactly once and untouched players are never written.
// Stops at postgame. No locals anywhere in this block (ACTS store loss after wait / builtin method): state
// lives in level / entity fields. Stock script functions that may endon or fail run in an entity thread, so
// they can never end the watchdog.
//
// Health: stock spawnPlayer sets maxHealth = commonOption maxHealth and health = maxHealth on every spawn
// (playerlogic.gsc:3157-3200, sessionstate "playing" first, no wait in between). Raising writes maxhealth
// first (juggernaut.gsc:325-326), lowering health first (script_13f6d1136f0a1b51.gsc:1391-1397). A new life
// or a menu change keeps the health ratio (at spawn health == maxhealth, so that is a full bar). Juggernaut
// (isjuggernaut) and last stand (inLastStand) own maxhealth and are skipped. The stock regen loop heals
// 40 HP/s times the per-player factor var_e6a8138052022574 (script_372301af73968cb.gsc:350-355); it is set
// to want/standard, so a full regen takes the stock time at any maxhealth, and back to 1 on standard.
// Invulnerable = the stock plotArmor flag, the first player check of filterDamage (damage.gsc:5195-5198);
// stock MP sets and clears it itself for spawn protection (spawncamera.gsc:1168/1218, tac_insert.gsc:1548/1561).

function cfg_log(text)
{
    function_8b17726cc97055("MW4 Botfix v1.2 menu: " + text);
}

function cfg_name()
{
    if (isdefined(level.mw4_cfg_p) && isdefined(level.mw4_cfg_p.var_6b09472177ca8529)) return "" + level.mw4_cfg_p.var_6b09472177ca8529;
    return "?";
}

function cfg_self_name()
{
    if (isdefined(self.var_6b09472177ca8529)) return "" + self.var_6b09472177ca8529;
    return "?";
}

// Missing dvars get their defaults, so Lua can read every value from the start (pattern of mw4_botfix_allow).
function cfg_defaults()
{
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_auav", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_auav", 2);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_hp", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_hp", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_ammo", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_ammo", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_speed", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_speed", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bdiff", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bdiff", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bhp", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bhp", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_freeze", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_freeze", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_hsonly", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_hsonly", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_brespawn", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_brespawn", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_mode", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bs_mode", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_fix_allies", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bs_fix_allies", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_fix_axis", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bs_fix_axis", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_block_allies", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bs_block_allies", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_block_axis", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bs_block_axis", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_psel", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bs_psel", 1);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_bsel", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bs_bsel", 1);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bdiff_e", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bdiff_e", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bhp_e", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bhp_e", 0);
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bammo", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bammo", 0);
}

// Highest valid arg per command (-1 = no such command).
function cfg_max(cmd)
{
    if (cmd == 6) return 2;
    if (cmd == 7) return 5;
    if (cmd == 8) return 1;
    if (cmd == 9) return 3;
    if (cmd == 10) return 4;
    if (cmd == 11) return 4;
    if (cmd == 12) return 1;
    if (cmd == 13) return 1;
    if (cmd == 14) return 7;
    if (cmd == 27) return 4;
    if (cmd == 28) return 4;
    if (cmd == 29) return 1;
    return -1;
}

function cfg_label(cmd, arg)
{
    if (cmd == 6)
    {
        if (arg == 2) return "Advanced UAV on";
        if (arg == 1) return "Advanced UAV on (enemy Counter-UAV jams it)";
        return "Advanced UAV off";
    }
    if (cmd == 7)
    {
        if (arg == 5) return "My health: invulnerable";
        if (arg <= 0) return "My health: default";
        return "My health: " + [[ &hp_my_value ]](arg);
    }
    if (cmd == 8)
    {
        if (arg == 1) return "Unlimited ammo on";
        return "Unlimited ammo off";
    }
    if (cmd == 9) return "Movement speed: " + [[ &spd_percent ]](arg) + " %";
    if (cmd == 10) return "Friendly bot difficulty: " + [[ &bd_label ]](arg);
    if (cmd == 27) return "Enemy bot difficulty: " + [[ &bd_label ]](arg);
    if (cmd == 11)
    {
        if (arg <= 0) return "Friendly bot health: default";
        return "Friendly bot health: " + [[ &hp_bot_value ]](arg);
    }
    if (cmd == 28)
    {
        if (arg <= 0) return "Enemy bot health: default";
        return "Enemy bot health: " + [[ &hp_bot_value ]](arg);
    }
    if (cmd == 29)
    {
        if (arg == 1) return "Bot unlimited ammo on";
        return "Bot unlimited ammo off";
    }
    if (cmd == 12)
    {
        if (arg == 1) return "Freeze bots on";
        return "Freeze bots off";
    }
    if (cmd == 13)
    {
        if (arg == 1) return "Headshots only on";
        return "Headshots only off";
    }
    if (cmd == 14) return "Bot respawn delay: " + [[ &rd_label ]](arg);
    return "?";
}

// Called from menu_carrier (registry callback): must not wait. The parameters go into level fields first.
function cfg_set(cmd, arg)
{
    level.mw4_cfg_scmd = cmd;
    level.mw4_cfg_sarg = arg;
    if (level.mw4_cfg_sarg < 0 || level.mw4_cfg_sarg > [[ &cfg_max ]](level.mw4_cfg_scmd))
    {
        [[ &cfg_log ]]("command " + level.mw4_cfg_scmd + " arg=" + level.mw4_cfg_sarg + " ignored (out of range)");
        return;
    }
    if (level.mw4_cfg_scmd == 6) function_b45d7cc91040f5d3(@"mw4_botfix_auav", level.mw4_cfg_sarg);
    else if (level.mw4_cfg_scmd == 7) function_b45d7cc91040f5d3(@"mw4_botfix_hp", level.mw4_cfg_sarg);
    else if (level.mw4_cfg_scmd == 8) function_b45d7cc91040f5d3(@"mw4_botfix_ammo", level.mw4_cfg_sarg);
    else if (level.mw4_cfg_scmd == 9) function_b45d7cc91040f5d3(@"mw4_botfix_speed", level.mw4_cfg_sarg);
    else if (level.mw4_cfg_scmd == 10) function_b45d7cc91040f5d3(@"mw4_botfix_bdiff", level.mw4_cfg_sarg);
    else if (level.mw4_cfg_scmd == 11) function_b45d7cc91040f5d3(@"mw4_botfix_bhp", level.mw4_cfg_sarg);
    else if (level.mw4_cfg_scmd == 12) function_b45d7cc91040f5d3(@"mw4_botfix_freeze", level.mw4_cfg_sarg);
    else if (level.mw4_cfg_scmd == 13) function_b45d7cc91040f5d3(@"mw4_botfix_hsonly", level.mw4_cfg_sarg);
    else if (level.mw4_cfg_scmd == 14) function_b45d7cc91040f5d3(@"mw4_botfix_brespawn", level.mw4_cfg_sarg);
    else if (level.mw4_cfg_scmd == 27) function_b45d7cc91040f5d3(@"mw4_botfix_bdiff_e", level.mw4_cfg_sarg);
    else if (level.mw4_cfg_scmd == 28) function_b45d7cc91040f5d3(@"mw4_botfix_bhp_e", level.mw4_cfg_sarg);
    else function_b45d7cc91040f5d3(@"mw4_botfix_bammo", level.mw4_cfg_sarg);
    level.mw4_cfg_stext = [[ &cfg_label ]](level.mw4_cfg_scmd, level.mw4_cfg_sarg);
    IPrintLn("MW4 MENU: " + level.mw4_cfg_stext);
    [[ &cfg_log ]]("setting " + level.mw4_cfg_stext + " (cmd " + level.mw4_cfg_scmd + " arg=" + level.mw4_cfg_sarg + ")");
    // Advanced UAV: the DEV 22 watchdog applies it (auav_release when off)
    if (level.mw4_cfg_scmd == 6 && isdefined(level.mw4_auav_run) && ![[ &auav_postgame ]]()) [[ &auav_tick ]]();
    level.mw4_cfg_quiet = 1;   // the line above is the log of this change
    [[ &cfg_tick ]]();
    level.mw4_cfg_quiet = 0;
}

function cfg_init()
{
    level.mw4_cfg_n_hp = 0;
    level.mw4_cfg_n_hpfix = 0;
    level.mw4_cfg_n_hpr = 0;
    level.mw4_cfg_n_bhp = 0;
    level.mw4_cfg_n_bhpr = 0;
    level.mw4_cfg_n_god = 0;
    level.mw4_cfg_n_spd = 0;
    level.mw4_cfg_n_spdfix = 0;
    level.mw4_cfg_n_spdr = 0;
    level.mw4_cfg_n_spdpg = 0;
    level.mw4_cfg_n_am = 0;
    level.mw4_cfg_n_bd = 0;
    level.mw4_cfg_n_bdr = 0;
    level.mw4_cfg_n_bf = 0;
    level.mw4_cfg_n_bfr = 0;
    level.mw4_cfg_lg_hp = 0;
    level.mw4_cfg_lg_hpr = 0;
    level.mw4_cfg_lg_hpfix = 0;
    level.mw4_cfg_lg_bhp = 0;
    level.mw4_cfg_lg_bhpr = 0;
    level.mw4_cfg_lg_god = 0;
    level.mw4_cfg_lg_godr = 0;
    level.mw4_cfg_lg_spd = 0;
    level.mw4_cfg_lg_spdr = 0;
    level.mw4_cfg_lg_am = 0;
    level.mw4_cfg_lg_bd = 0;
    level.mw4_cfg_lg_bdr = 0;
    level.mw4_cfg_lg_bf = 0;
    level.mw4_cfg_lg_bfr = 0;
    level.mw4_cfg_n_rd = 0;
    level.mw4_cfg_n_rdr = 0;
    level.mw4_cfg_n_rdskip = 0;
    level.mw4_cfg_lg_rd = 0;
    level.mw4_cfg_lg_rdinfo = 0;
    level.mw4_lr_nammo = 0;
    level.mw4_lr_nback = 0;
    level.mw4_lr_lgback = 0;
    level.mw4_lr_nw = 0;
    level.mw4_lr_nd = 0;
    level.mw4_lr_ns = 0;
    level.mw4_bb_n = 0;
    level.mw4_hs_n = 0;
    level.mw4_hs_ni = 0;
    level.mw4_hs_lga = 0;
    level.mw4_hs_lgb = 0;
    level.mw4_cfg_rep = -1;
    level.mw4_cfg_quiet = 0;
}

function cfg_main()
{
    if (isdefined(level.mw4_cfg_run)) return;
    [[ &cfg_init ]]();
    level.mw4_cfg_run = 1;
    level thread [[ &cfg_spawn_watch ]]();
    level thread [[ &cfg_end_watch ]]();
    while (![[ &auav_postgame ]]())
    {
        [[ &cfg_tick ]]();
        wait 0.25;
    }
    [[ &cfg_postgame ]]();
    [[ &cfg_log ]]("settings watchdog stopped (postgame); my health sets=" + level.mw4_cfg_n_hp + " re-applied=" + level.mw4_cfg_n_hpfix
        + " restored=" + level.mw4_cfg_n_hpr + " invulnerable=" + level.mw4_cfg_n_god + " speed sets=" + level.mw4_cfg_n_spd
        + " re-applied=" + level.mw4_cfg_n_spdfix + " restored=" + level.mw4_cfg_n_spdr + " speed cap flags removed at postgame="
        + level.mw4_cfg_n_spdpg + " ammo refills=" + level.mw4_cfg_n_am
        + " bot health sets=" + level.mw4_cfg_n_bhp + " restored=" + level.mw4_cfg_n_bhpr + " bot difficulty sets=" + level.mw4_cfg_n_bd
        + " restored=" + level.mw4_cfg_n_bdr + " bot freezes=" + level.mw4_cfg_n_bf + " releases=" + level.mw4_cfg_n_bfr);
    [[ &cfg_log ]]("DEV 25 counters: headshot-only blocks=" + level.mw4_hs_n + " respawn overrides=" + level.mw4_cfg_n_rd
        + " skipped=" + level.mw4_cfg_n_rdskip + " bot skins set=" + level.mw4_bs_n + " restored=" + level.mw4_bs_nr
        + " refused=" + level.mw4_bs_nfail + " bot fixed-weapon refills=" + level.mw4_lr_nammo + " switches back=" + level.mw4_lr_nback
        + " bot ammo refills=" + level.mw4_bb_n);
}

// Fast path: one pass a frame after every stock "uav_update" (every spawn), after the stock spawn values.
function cfg_spawn_watch()
{
    while (![[ &auav_postgame ]]())
    {
        level waittill("uav_update");
        waitframe();
        if ([[ &auav_postgame ]]()) return;
        [[ &cfg_tick ]]();
    }
}

// At the match end (level "game_ended" is sent together with game["state"] = "postgame", gamelogic.gsc:8172-8175)
// the speed cap flag leaves self.perks again: the final killcam looks every key of the killer's perks up in
// the stock perk table (killcam.gsc:1121-1131, reached only from final_killcam.gsc:336), and
// "specialty_super_speed_script" is never given by stock. Nothing else is undone (the match is over).
function cfg_end_watch()
{
    if ([[ &auav_postgame ]]()) return;
    level waittill("game_ended");
    [[ &cfg_postgame ]]();
}

function cfg_postgame()
{
    if (!isdefined(level.var_10f4ff41c4b7f0ac)) return;
    for (level.mw4_cfg_k = 0; level.mw4_cfg_k < level.var_10f4ff41c4b7f0ac.size; level.mw4_cfg_k++)
    {
        level.mw4_cfg_q = level.var_10f4ff41c4b7f0ac[level.mw4_cfg_k];
        if (!isdefined(level.mw4_cfg_q) || !isdefined(level.mw4_cfg_q.mw4_spd_on) || !isdefined(level.mw4_cfg_q.var_4041d41dbb64df3)) continue;
        if (!isdefined(level.mw4_cfg_q.var_4041d41dbb64df3["specialty_super_speed_script"])) continue;
        level.mw4_cfg_q.var_4041d41dbb64df3["specialty_super_speed_script"] = undefined;
        level.mw4_cfg_n_spdpg++;
    }
    level.mw4_cfg_q = undefined;
}

function cfg_read(cmd)
{
    level.mw4_cfg_v = 0;
    if (cmd == 7) level.mw4_cfg_v = function_b4b0c0cb1ac2b968(@"mw4_botfix_hp", 0);
    else if (cmd == 8) level.mw4_cfg_v = function_b4b0c0cb1ac2b968(@"mw4_botfix_ammo", 0);
    else if (cmd == 9) level.mw4_cfg_v = function_b4b0c0cb1ac2b968(@"mw4_botfix_speed", 0);
    else if (cmd == 10) level.mw4_cfg_v = function_b4b0c0cb1ac2b968(@"mw4_botfix_bdiff", 0);
    else if (cmd == 11) level.mw4_cfg_v = function_b4b0c0cb1ac2b968(@"mw4_botfix_bhp", 0);
    else if (cmd == 12) level.mw4_cfg_v = function_b4b0c0cb1ac2b968(@"mw4_botfix_freeze", 0);
    else if (cmd == 13) level.mw4_cfg_v = function_b4b0c0cb1ac2b968(@"mw4_botfix_hsonly", 0);
    else if (cmd == 14) level.mw4_cfg_v = function_b4b0c0cb1ac2b968(@"mw4_botfix_brespawn", 0);
    else if (cmd == 27) level.mw4_cfg_v = function_b4b0c0cb1ac2b968(@"mw4_botfix_bdiff_e", 0);
    else if (cmd == 28) level.mw4_cfg_v = function_b4b0c0cb1ac2b968(@"mw4_botfix_bhp_e", 0);
    else if (cmd == 29) level.mw4_cfg_v = function_b4b0c0cb1ac2b968(@"mw4_botfix_bammo", 0);
    if (level.mw4_cfg_v < 0 || level.mw4_cfg_v > [[ &cfg_max ]](cmd)) level.mw4_cfg_v = 0;   // invalid -> default
    return level.mw4_cfg_v;
}

function cfg_tick()
{
    if (!isdefined(level.mw4_cfg_run) || [[ &auav_postgame ]]()) return;
    level.mw4_cfg_hp = [[ &cfg_read ]](7);
    [[ &hp_deo ]]();
    level.mw4_cfg_ammo = [[ &cfg_read ]](8);
    level.mw4_cfg_speed = [[ &cfg_read ]](9);
    level.mw4_cfg_bdiff = [[ &cfg_read ]](10);
    level.mw4_cfg_bhp = [[ &cfg_read ]](11);
    level.mw4_cfg_freeze = [[ &cfg_read ]](12);
    level.mw4_cfg_hs = [[ &cfg_read ]](13);
    [[ &hs_hook ]]();
    level.mw4_cfg_brd = [[ &cfg_read ]](14);
    [[ &rd_tick ]]();
    level.mw4_lr_sig = [[ &lr_sig_now ]]();
    level.mw4_lr_fixed = function_b4b0c0cb1ac2b968(@"mw4_botfix_fixed", 0);
    if (!(level.mw4_lr_fixed === level.mw4_lr_fixwas))
    {
        level.mw4_lr_fixwas = level.mw4_lr_fixed;
        level.mw4_lr_fixroot = undefined;
        level.mw4_lr_fixpool = [[ &lr_primary_pool ]](-1);
        if (level.mw4_lr_fixed > 0 && level.mw4_lr_fixpool.size > 0) level.mw4_lr_fixroot = level.mw4_lr_fixpool[(level.mw4_lr_fixed - 1) % level.mw4_lr_fixpool.size];
        level.mw4_lr_fixpool = undefined;
    }
    if (isdefined(level.mw4_bs_slotent)) [[ &bs_slots ]]();
    level.mw4_cfg_dname = [[ &bd_name ]](level.mw4_cfg_bdiff);
    level.mw4_cfg_bdiff_e = [[ &cfg_read ]](27);                  // DEV 28: enemy bots
    level.mw4_cfg_bhp_e = [[ &cfg_read ]](28);
    level.mw4_cfg_bammo = [[ &cfg_read ]](29);
    level.mw4_cfg_dname_f = level.mw4_cfg_dname;
    level.mw4_cfg_dname_e = [[ &bd_name ]](level.mw4_cfg_bdiff_e);
    [[ &cfg_host ]]();
    level.mw4_cfg_mult = [[ &spd_value ]](level.mw4_cfg_speed);
    level.mw4_cfg_root = [[ &spd_root ]](level.mw4_cfg_speed);
    level.mw4_cfg_spdb = function_b4b0c0cb1ac2b968(@"hash_443d1da7a531d52f", 0);   // 2nd movement path active? (weapons.gsc:3728)
    // the maxhealth stock gives every player on spawn (playerlogic.gsc:3168)
    level.mw4_cfg_raw = function_8d35635fa0f5f852("commonOption", "maxHealth");
    level.mw4_cfg_stock = 100;
    if (isdefined(level.mw4_cfg_raw)) level.mw4_cfg_stock = int(level.mw4_cfg_raw);
    if (level.mw4_cfg_stock <= 0) level.mw4_cfg_stock = 100;
    [[ &cfg_report ]]();
    if (!isdefined(level.var_10f4ff41c4b7f0ac)) return;
    for (level.mw4_cfg_i = 0; level.mw4_cfg_i < level.var_10f4ff41c4b7f0ac.size; level.mw4_cfg_i++)
    {
        level.mw4_cfg_p = level.var_10f4ff41c4b7f0ac[level.mw4_cfg_i];
        [[ &cfg_player ]]();
    }
    level.mw4_cfg_p = undefined;
}

// One log line with all settings at match start and whenever they change outside the menu
// (a menu change already logged its own line in cfg_set).
function cfg_report()
{
    level.mw4_cfg_auav = function_b4b0c0cb1ac2b968(@"mw4_botfix_auav", 2);
    if (level.mw4_cfg_auav < 0 || level.mw4_cfg_auav > 2) level.mw4_cfg_auav = 2;
    // one number for all settings (no string work on an unchanged pass)
    // step by step: one nested expression this deep overflows the ACTS parser stack
    level.mw4_cfg_sig = level.mw4_cfg_bammo + 2 * (level.mw4_cfg_bhp_e + 5 * level.mw4_cfg_bdiff_e);   // DEV 28
    level.mw4_cfg_sig = level.mw4_cfg_brd + 8 * (level.mw4_bs_mode + 3 * level.mw4_cfg_sig);
    level.mw4_cfg_sig = level.mw4_cfg_hs + 2 * level.mw4_cfg_sig;
    level.mw4_cfg_sig = level.mw4_cfg_freeze + 2 * level.mw4_cfg_sig;
    level.mw4_cfg_sig = level.mw4_cfg_bhp + 5 * level.mw4_cfg_sig;
    level.mw4_cfg_sig = level.mw4_cfg_bdiff + 5 * level.mw4_cfg_sig;
    level.mw4_cfg_sig = level.mw4_cfg_speed + 4 * level.mw4_cfg_sig;
    level.mw4_cfg_sig = level.mw4_cfg_ammo + 2 * level.mw4_cfg_sig;
    level.mw4_cfg_sig = level.mw4_cfg_hp + 6 * level.mw4_cfg_sig;
    level.mw4_cfg_sig = level.mw4_cfg_auav + 3 * level.mw4_cfg_sig;
    if (level.mw4_cfg_sig === level.mw4_cfg_rep) return;
    level.mw4_cfg_rep = level.mw4_cfg_sig;
    if (level.mw4_cfg_quiet) return;
    level.mw4_cfg_text = [[ &cfg_label ]](6, level.mw4_cfg_auav) + ", " + [[ &cfg_label ]](7, level.mw4_cfg_hp) + ", "
        + [[ &cfg_label ]](8, level.mw4_cfg_ammo) + ", " + [[ &cfg_label ]](9, level.mw4_cfg_speed) + ", "
        + [[ &cfg_label ]](10, level.mw4_cfg_bdiff) + ", " + [[ &cfg_label ]](11, level.mw4_cfg_bhp) + ", "
        + [[ &cfg_label ]](12, level.mw4_cfg_freeze) + ", " + [[ &cfg_label ]](13, level.mw4_cfg_hs) + ", "
        + [[ &cfg_label ]](14, level.mw4_cfg_brd) + ", " + [[ &bs_label ]](15, level.mw4_bs_mode);
    level.mw4_cfg_text = level.mw4_cfg_text + ", " + [[ &cfg_label ]](27, level.mw4_cfg_bdiff_e) + ", "
        + [[ &cfg_label ]](28, level.mw4_cfg_bhp_e) + ", " + [[ &cfg_label ]](29, level.mw4_cfg_bammo);
    [[ &cfg_log ]]("settings active: " + level.mw4_cfg_text + " (standard maxhealth " + level.mw4_cfg_stock + ")");
}

function cfg_player()
{
    if (!isdefined(level.mw4_cfg_p) || !isdefined(level.mw4_cfg_p.team) || !isdefined(level.mw4_cfg_p.var_8b69ecbd466a79fa)) return;
    level.mw4_cfg_bot = level.mw4_cfg_p [[ &lr_is_bot ]]();
    level.mw4_cfg_alive = level.mw4_cfg_p.var_948fe687565941e7 === "playing" && isdefined(level.mw4_cfg_p.var_d2c854047ddd1dbc)
        && level.mw4_cfg_p.var_d2c854047ddd1dbc > 0;
    if (level.mw4_cfg_bot)
    {
        // DEV 28: health / difficulty per side; while the human has no team in a team mode (spectator, not yet
        // assigned) only when both sides have the same value. Everything else always runs.
        level.mw4_cfg_side = 1;
        if (istrue(level.teambased) && !isdefined(level.mw4_cfg_hteam)) level.mw4_cfg_side = 0;
        if (level.mw4_cfg_bhp == level.mw4_cfg_bhp_e && level.mw4_cfg_bdiff == level.mw4_cfg_bdiff_e) level.mw4_cfg_side = 1;
        level.mw4_cfg_sbhp = level.mw4_cfg_bhp;
        level.mw4_cfg_dname = level.mw4_cfg_dname_f;
        if ([[ &cfg_enemy ]]())
        {
            level.mw4_cfg_sbhp = level.mw4_cfg_bhp_e;
            level.mw4_cfg_dname = level.mw4_cfg_dname_e;
        }
        level.mw4_cfg_god = 0;                                   // never invulnerable bots
        level.mw4_cfg_want = [[ &hp_bot_value ]](level.mw4_cfg_sbhp);
        [[ &hp_god ]]();
        if (level.mw4_cfg_side) [[ &hp_player ]]();
        if (!function_aad3cad3abf3c14f(level.mw4_cfg_p)) return; // bot builtins only on real bot clients
        if (level.mw4_cfg_side) [[ &bd_bot ]]();
        [[ &bf_bot ]]();
        level.mw4_lr_p = level.mw4_cfg_p;                          // DEV 25: weapons after a round restart
        [[ &lr_refresh_one ]](0);
        if (isdefined(level.mw4_cfg_p.mw4_lr_req)) level.mw4_cfg_p thread [[ &lr_swap ]]();   // DEV 27: retry
        if (level.mw4_cfg_alive && level.mw4_lr_fixed > 0) level.mw4_cfg_p thread [[ &lr_bot_keep ]]();
        if (level.mw4_cfg_alive && level.mw4_cfg_bammo > 0) level.mw4_cfg_p thread [[ &bb_ammo ]]();   // DEV 28
        [[ &rd_bot ]]();
        [[ &bs_bot ]]();
        return;
    }
    level.mw4_cfg_god = level.mw4_cfg_hp == 5;
    level.mw4_cfg_want = [[ &hp_my_value ]](level.mw4_cfg_hp);
    [[ &hp_god ]]();
    [[ &hp_player ]]();
    [[ &spd_player ]]();
    if (level.mw4_cfg_ammo > 0 && level.mw4_cfg_alive) level.mw4_cfg_p thread [[ &am_run ]]();
    [[ &skin_publish ]]();                                       // DEV 25: My Skin list size
    if (!isdefined(level.mw4_cfg_p.mw4_skin_watch))
    {
        level.mw4_cfg_p.mw4_skin_watch = 1;                      // the loadout hook does not run on cached loadouts
        level.mw4_cfg_p thread [[ &skin_watch ]]();
    }
}

// ---- health (cmd 7 / cmd 11)

// While invulnerable, every blocked hit would print a stock "[DamageEarlyOut] ... isTrue( victim.plotArmor )"
// line (damage.gsc:332-337 -> function_2499f72abb86f810 :12452-12457, only if dvar #a658b504ac40c111 == 1,
// default 1). It is set to 0 while my health is "invulnerable" and back to the stock 1 afterwards; the dvar
// mw4_botfix_deo_muted remembers across matches that we changed it.
function hp_deo()
{
    if (level.mw4_cfg_hp == 5)
    {
        if (function_b4b0c0cb1ac2b968(@"hash_a658b504ac40c111", 1) == 0) return;
        function_b45d7cc91040f5d3(@"hash_a658b504ac40c111", 0);
        function_b45d7cc91040f5d3(@"mw4_botfix_deo_muted", 1);
        [[ &cfg_log ]]("stock damage early-out log muted while invulnerable");
        return;
    }
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_deo_muted", 0) == 0) return;
    function_b45d7cc91040f5d3(@"hash_a658b504ac40c111", 1);
    function_b45d7cc91040f5d3(@"mw4_botfix_deo_muted", 0);
    [[ &cfg_log ]]("stock damage early-out log restored");
}

// 0 = stock maxhealth, otherwise the wanted maxhealth (5 = invulnerable keeps the stock maxhealth).
function hp_my_value(arg)
{
    if (arg == 1) return 150;
    if (arg == 2) return 200;
    if (arg == 3) return 300;
    if (arg == 4) return 500;
    return 0;
}

function hp_bot_value(arg)
{
    if (arg == 1) return 50;
    if (arg == 2) return 150;
    if (arg == 3) return 200;
    if (arg == 4) return 300;
    return 0;
}

// plotArmor for invulnerable humans, every pass, dead or alive: stock spawn protection writes it back to 0
// (spawncamera.gsc:1189/1218, tac_insert.gsc:1561). Marker in pers, so a round restart cannot lose it.
function hp_god()
{
    if (level.mw4_cfg_god)
    {
        if (!istrue(level.mw4_cfg_p.var_69aa7046a099e5b0)) level.mw4_cfg_p.var_69aa7046a099e5b0 = 1;
        if (isdefined(level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_hp_god"])) return;
        level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_hp_god"] = 1;
        level.mw4_cfg_n_god++;
        if (!level.mw4_cfg_lg_god)
        {
            level.mw4_cfg_lg_god = 1;
            [[ &cfg_log ]]("invulnerable on for " + [[ &cfg_name ]]() + " (stock plotArmor flag; first time this match)");
        }
        return;
    }
    if (!isdefined(level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_hp_god"])) return;
    level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_hp_god"] = undefined;
    level.mw4_cfg_p.var_69aa7046a099e5b0 = 0;   // the value stock writes after its spawn protection (spawncamera.gsc:1218)
    if (!level.mw4_cfg_lg_godr)
    {
        level.mw4_cfg_lg_godr = 1;
        [[ &cfg_log ]]("invulnerable off for " + [[ &cfg_name ]]() + " (first time this match)");
    }
}

function hp_player()
{
    if (!level.mw4_cfg_alive) return;
    if (istrue(level.mw4_cfg_p.var_e5cc746798bed3ae) || istrue(level.mw4_cfg_p.var_d0697a2251283e17)) return;   // juggernaut / last stand
    if (level.mw4_cfg_want > 0) [[ &hp_apply ]]();
    else [[ &hp_restore ]]();
}

function hp_apply()
{
    level.mw4_cfg_hkeep = 0;   // new life or menu change: keep the health ratio
    if (level.mw4_cfg_p.mw4_hp_life === level.mw4_cfg_p.var_c2db1b2eb73638c && level.mw4_cfg_p.mw4_hp_set === level.mw4_cfg_want)
    {
        // same life, same setting: only undo a stock reset of maxhealth (e.g. Battle Rage back to commonOption,
        // script_19fd5b5d73d44c18.gsc:470-478); a temporary stock boost beyond the wanted value is left alone
        if (level.mw4_cfg_want >= level.mw4_cfg_stock && level.mw4_cfg_p.var_bf80442dd2797c82 >= level.mw4_cfg_want) return;
        if (level.mw4_cfg_want < level.mw4_cfg_stock && level.mw4_cfg_p.var_bf80442dd2797c82 <= level.mw4_cfg_want) return;
        level.mw4_cfg_hkeep = 1;
    }
    level.mw4_cfg_hold = level.mw4_cfg_p.var_bf80442dd2797c82;
    if (!isdefined(level.mw4_cfg_hold)) level.mw4_cfg_hold = 0;   // only for the log line (string + undefined)
    // first change in this life: remember the stock maxhealth of this life (perks, mode) for "Standard"
    if (!(level.mw4_cfg_p.mw4_hp_life === level.mw4_cfg_p.var_c2db1b2eb73638c)) level.mw4_cfg_p.mw4_hp_base = level.mw4_cfg_p.var_bf80442dd2797c82;
    level.mw4_cfg_newmax = level.mw4_cfg_want;
    [[ &hp_write ]]();
    level.mw4_cfg_p.var_e6a8138052022574 = level.mw4_cfg_want * 1.0 / level.mw4_cfg_stock;
    level.mw4_cfg_p.mw4_hp_set = level.mw4_cfg_want;
    level.mw4_cfg_p.mw4_hp_life = level.mw4_cfg_p.var_c2db1b2eb73638c;
    if (level.mw4_cfg_hkeep)
    {
        level.mw4_cfg_n_hpfix++;
        if (level.mw4_cfg_lg_hpfix) return;
        level.mw4_cfg_lg_hpfix = 1;
        [[ &cfg_log ]]("health " + level.mw4_cfg_want + " re-applied for " + [[ &cfg_name ]]() + " after a stock change of maxhealth to "
            + level.mw4_cfg_hold + " (first time this match)");
        return;
    }
    if (level.mw4_cfg_bot)
    {
        level.mw4_cfg_n_bhp++;
        if (level.mw4_cfg_lg_bhp) return;
        level.mw4_cfg_lg_bhp = 1;
        [[ &cfg_log ]]("bot health " + level.mw4_cfg_want + " for " + [[ &cfg_name ]]() + ": maxhealth " + level.mw4_cfg_hold
            + " -> " + level.mw4_cfg_want + ", health " + level.mw4_cfg_newhp + " (first bot this match)");
        return;
    }
    level.mw4_cfg_n_hp++;
    if (level.mw4_cfg_lg_hp) return;
    level.mw4_cfg_lg_hp = 1;
    [[ &cfg_log ]]("my health " + level.mw4_cfg_want + " for " + [[ &cfg_name ]]() + ": maxhealth " + level.mw4_cfg_hold + " -> "
        + level.mw4_cfg_want + ", health " + level.mw4_cfg_newhp + ", regen x" + level.mw4_cfg_p.var_e6a8138052022574 + " (first time this match)");
}

function hp_restore()
{
    if (!isdefined(level.mw4_cfg_p.mw4_hp_set)) return;   // never touched: the stock state stays as it is
    level.mw4_cfg_p.var_e6a8138052022574 = 1;   // stock default (script_372301af73968cb.gsc:350-353)
    if (!(level.mw4_cfg_p.mw4_hp_life === level.mw4_cfg_p.var_c2db1b2eb73638c))
    {
        // a new life: the stock spawn already set the stock maxhealth (playerlogic.gsc:3168, perks after it)
        level.mw4_cfg_p.mw4_hp_set = undefined;
        level.mw4_cfg_p.mw4_hp_life = undefined;
        level.mw4_cfg_p.mw4_hp_base = undefined;
        return;
    }
    level.mw4_cfg_hkeep = 0;
    level.mw4_cfg_hold = level.mw4_cfg_p.var_bf80442dd2797c82;
    if (!isdefined(level.mw4_cfg_hold)) level.mw4_cfg_hold = 0;   // only for the log line (string + undefined)
    level.mw4_cfg_newmax = level.mw4_cfg_stock;
    if (isdefined(level.mw4_cfg_p.mw4_hp_base) && level.mw4_cfg_p.mw4_hp_base > 0) level.mw4_cfg_newmax = level.mw4_cfg_p.mw4_hp_base;
    [[ &hp_write ]]();
    level.mw4_cfg_p.mw4_hp_set = undefined;
    level.mw4_cfg_p.mw4_hp_life = undefined;
    level.mw4_cfg_p.mw4_hp_base = undefined;
    if (level.mw4_cfg_bot)
    {
        level.mw4_cfg_n_bhpr++;
        if (level.mw4_cfg_lg_bhpr) return;
        level.mw4_cfg_lg_bhpr = 1;
        [[ &cfg_log ]]("bot health back to standard for " + [[ &cfg_name ]]() + ": maxhealth " + level.mw4_cfg_hold + " -> "
            + level.mw4_cfg_newmax + " (first bot this match)");
        return;
    }
    level.mw4_cfg_n_hpr++;
    if (level.mw4_cfg_lg_hpr) return;
    level.mw4_cfg_lg_hpr = 1;
    [[ &cfg_log ]]("my health back to standard for " + [[ &cfg_name ]]() + ": maxhealth " + level.mw4_cfg_hold + " -> "
        + level.mw4_cfg_newmax + " (first time this match)");
}

// In: level.mw4_cfg_newmax, level.mw4_cfg_hkeep (1 = keep health, only clamp; 0 = keep the ratio).
function hp_write()
{
    level.mw4_cfg_oldmax = level.mw4_cfg_p.var_bf80442dd2797c82;
    level.mw4_cfg_newhp = level.mw4_cfg_p.var_d2c854047ddd1dbc;
    if (!level.mw4_cfg_hkeep && isdefined(level.mw4_cfg_oldmax) && level.mw4_cfg_oldmax > 0)
        level.mw4_cfg_newhp = int(level.mw4_cfg_newhp * level.mw4_cfg_newmax / level.mw4_cfg_oldmax);
    if (level.mw4_cfg_newhp > level.mw4_cfg_newmax) level.mw4_cfg_newhp = level.mw4_cfg_newmax;
    if (level.mw4_cfg_newhp < 1) level.mw4_cfg_newhp = 1;
    if (!isdefined(level.mw4_cfg_oldmax) || level.mw4_cfg_newmax >= level.mw4_cfg_oldmax)
    {
        // raising: maxhealth first, then health (juggernaut.gsc:325-326)
        level.mw4_cfg_p.var_bf80442dd2797c82 = level.mw4_cfg_newmax;
        if (!(level.mw4_cfg_p.var_d2c854047ddd1dbc === level.mw4_cfg_newhp)) level.mw4_cfg_p.var_d2c854047ddd1dbc = level.mw4_cfg_newhp;
        return;
    }
    // lowering: health first, then maxhealth (script_13f6d1136f0a1b51.gsc:1391-1397)
    if (!(level.mw4_cfg_p.var_d2c854047ddd1dbc === level.mw4_cfg_newhp)) level.mw4_cfg_p.var_d2c854047ddd1dbc = level.mw4_cfg_newhp;
    level.mw4_cfg_p.var_bf80442dd2797c82 = level.mw4_cfg_newmax;
}

// ---- move speed (cmd 9), human players only
// Every stock speed change goes through weapons::function_7de1c896d40acab1 (weapons.gsc:3726-3882): it
// multiplies the base by every entry of self.var_e5996377e9a13e32 (3813-3819; no stock writer), clamps to
// 1.08 unless self.perks["specialty_super_speed_script"] lifts the cap to getdvarfloat(@"hash_94084550cb0f64e7", 2)
// (3735-3736; read only in stock), then calls setmovespeedscale (3881). Our entry therefore rides along with
// every stock recompute (weapon switch, perks, gas, ...). Loadouts clear self.perks (perks.gsc:738), so the
// watchdog puts the cap flag back (field reads only; a recompute only when something is missing). The MP
// loadout clear (perks.gsc:720-742) only runs unset callbacks registered for a key (none for this one); the
// variant that calls the unsetPerk builtin for every key (perks.gsc:1451-1477) is reached only from br
// (script_1e4a61db11011446.gsc:5479 -> class.gsc:4341). At the match end the flag is removed (cfg_postgame).
// If the dvar @"hash_443d1da7a531d52f" is set the stock uses the 2nd path common::function_79211cd1f2b54512
// (weapons.gsc:3728-3731, script_fd32f08e72b657f.gsc:3418-3507), which multiplies a type-3 modifier twice
// (case 3 and again after the switch): there the square root goes in.

function spd_value(mode)
{
    if (mode == 1) return 1.1;
    if (mode == 2) return 1.25;
    if (mode == 3) return 1.5;
    return 1;
}

function spd_root(mode)
{
    if (mode == 1) return 1.0488088;
    if (mode == 2) return 1.118034;
    if (mode == 3) return 1.2247449;
    return 1;
}

function spd_percent(mode)
{
    if (mode == 1) return 110;
    if (mode == 2) return 125;
    if (mode == 3) return 150;
    return 100;
}

function spd_player()
{
    if (level.mw4_cfg_mult > 1)
    {
        if (!level.mw4_cfg_alive || !isdefined(level.mw4_cfg_p.var_ac98ec01ce4f30f6) || !isdefined(level.mw4_cfg_p.var_4041d41dbb64df3)) return;
        if (isdefined(level.mw4_cfg_p.var_e5996377e9a13e32) && level.mw4_cfg_p.var_e5996377e9a13e32["mw4_botfix_speed"] === level.mw4_cfg_mult
            && isdefined(level.mw4_cfg_p.var_4041d41dbb64df3["specialty_super_speed_script"])
            && (level.mw4_cfg_spdb == 0 || level.mw4_cfg_p.mw4_spd_b === level.mw4_cfg_mult)) return;
        level.mw4_cfg_p thread [[ &spd_on ]]();
        return;
    }
    if (!isdefined(level.mw4_cfg_p.mw4_spd_on)) return;   // never touched
    level.mw4_cfg_p thread [[ &spd_off ]]();
}

// self = human player (own thread: a stock error cannot end the watchdog). Markers before the stock calls.
function spd_on()
{
    if (!isdefined(self.var_e5996377e9a13e32)) self.var_e5996377e9a13e32 = [];
    self.var_e5996377e9a13e32["mw4_botfix_speed"] = level.mw4_cfg_mult;
    self.var_4041d41dbb64df3["specialty_super_speed_script"] = 1;
    if (!isdefined(self.mw4_spd_on))
    {
        level.mw4_cfg_n_spd++;
        if (!level.mw4_cfg_lg_spd)
        {
            level.mw4_cfg_lg_spd = 1;
            [[ &cfg_log ]]("move speed x" + level.mw4_cfg_mult + " for " + [[ &cfg_self_name ]]() + " (2nd path dvar="
                + level.mw4_cfg_spdb + " no-clamp dvar=" + function_b4b0c0cb1ac2b968(@"hash_b7318d7f06303895", 0)
                + " cap with flag=" + function_de833aa04cb46c43(@"hash_94084550cb0f64e7", 2) + "; first time this match)");
        }
    }
    else if (self.mw4_spd_on === level.mw4_cfg_mult) level.mw4_cfg_n_spdfix++;
    self.mw4_spd_on = level.mw4_cfg_mult;
    if (level.mw4_cfg_spdb != 0 && !(self.mw4_spd_b === level.mw4_cfg_mult))
    {
        self.mw4_spd_b = level.mw4_cfg_mult;
        self namespace_bce7aa9cc2eadaf::function_dbe1e4d9bd688221("mw4_botfix_speed", level.mw4_cfg_root, level.mw4_cfg_root,
            level.mw4_cfg_root, level.mw4_cfg_root);
    }
    self namespace_e7560f700c901627::function_7de1c896d40acab1();   // stock recompute -> setmovespeedscale
}

// 100 %: our entries out again, then the stock recompute gives exactly the stock value.
function spd_off()
{
    self.mw4_spd_on = undefined;
    if (isdefined(self.var_e5996377e9a13e32))
    {
        self.var_e5996377e9a13e32["mw4_botfix_speed"] = undefined;
        if (self.var_e5996377e9a13e32.size == 0) self.var_e5996377e9a13e32 = undefined;   // stock state (no stock writer)
    }
    if (isdefined(self.var_4041d41dbb64df3)) self.var_4041d41dbb64df3["specialty_super_speed_script"] = undefined;   // never set by stock
    level.mw4_cfg_n_spdr++;
    if (!level.mw4_cfg_lg_spdr)
    {
        level.mw4_cfg_lg_spdr = 1;
        [[ &cfg_log ]]("move speed back to 100 % for " + [[ &cfg_self_name ]]() + " (first time this match)");
    }
    if (isdefined(self.mw4_spd_b))
    {
        self.mw4_spd_b = undefined;
        self namespace_bce7aa9cc2eadaf::function_d85a92c557ea5a52("mw4_botfix_speed");
    }
    if (self.var_948fe687565941e7 === "playing" && isdefined(self.var_ac98ec01ce4f30f6))
        self namespace_e7560f700c901627::function_7de1c896d40acab1();
}

// ---- unlimited ammo (cmd 8), human players only
// Reserve always full, magazine full unless a reload is running; the weapon filter of the stock ammo
// restock (ammorestock.gsc:952): no melee-only, super, killstreak or game mode weapons. Dual wield / akimbo
// fill both hands (class.gsc:827-829), underbarrels through getaltweapon (class.gsc:853-855). Lethal and
// tactical through the stock equipment API, which also updates the HUD charges (equipment.gsc:1287-1321,
// 1432-1442). Off: nothing to give back. self = human player (own thread); state in self fields.

function am_run()
{
    self.mw4_am_rel = self function_de3308f8f8188c85();          // isreloading (damage.gsc:6751)
    self.mw4_am_list = self function_764725998ad94fc3();         // getweaponslistprimaries (weapons.gsc:7427)
    if (isdefined(self.mw4_am_list))
    {
        for (self.mw4_am_j = 0; self.mw4_am_j < self.mw4_am_list.size; self.mw4_am_j++)
        {
            self.mw4_am_w = self.mw4_am_list[self.mw4_am_j];
            self [[ &am_weapon ]]();
            if (isdefined(self.mw4_am_w) && istrue(self.mw4_am_w.var_ba9e31dda49589b8))   // hasalternate
            {
                self.mw4_am_w = self.mw4_am_w function_a68ab200e4b8a8c5();          // getaltweapon
                self [[ &am_weapon ]]();
            }
        }
    }
    self.mw4_am_list = undefined;
    self.mw4_am_w = undefined;
    if (!isdefined(self.var_4041d41dbb64df3)) return;   // getequipmentmaxammo reads self.perks (equipment.gsc:990)
    self.mw4_am_slot = "primary";     // lethal
    self [[ &am_equip ]]();
    self.mw4_am_slot = "secondary";   // tactical
    self [[ &am_equip ]]();
}

function am_weapon()
{
    if (!isdefined(self.mw4_am_w) || function_a4570faaefbe853f(self.mw4_am_w)) return;   // isnullweapon
    if (weapon::function_28f110447a3881d0(self.mw4_am_w) || weapon::function_90bbcf8c76e0f9d1(self.mw4_am_w)
        || weapon::function_71a662b35139507c(self.mw4_am_w) || weapon::function_9f17ca77a89fa437(self.mw4_am_w)) return;
    self.mw4_am_max = function_16410b68f883657e(self.mw4_am_w);          // weaponmaxammo
    self.mw4_am_cur = self function_bb22cf581da23562(self.mw4_am_w);     // getweaponammostock
    if (self.mw4_am_cur < self.mw4_am_max)
    {
        self function_203c60b1e5c3e21e(self.mw4_am_w, self.mw4_am_max);  // setweaponammostock
        self [[ &am_count ]]();
    }
    if (istrue(self.mw4_am_rel)) return;   // a started reload finishes normally
    self.mw4_am_clip = function_55e3f2582ad44bc9(self.mw4_am_w);         // weaponclipsize
    if (istrue(self.mw4_am_w.var_c674dcaaa4a071d7) || weapon::function_670ef0c228ed3507(self.mw4_am_w))   // isdualwield / isakimbo
    {
        self.mw4_am_hand = "right";
        self [[ &am_clip ]]();
        self.mw4_am_hand = "left";
        self [[ &am_clip ]]();
        return;
    }
    self.mw4_am_hand = undefined;
    self [[ &am_clip ]]();
}

function am_clip()
{
    if (isdefined(self.mw4_am_hand))
    {
        self.mw4_am_cur = self function_f930fc7a157424fa(self.mw4_am_w, self.mw4_am_hand);   // getweaponammoclip
        if (self.mw4_am_cur >= self.mw4_am_clip) return;
        self function_52af4bdf96523e46(self.mw4_am_w, self.mw4_am_clip, self.mw4_am_hand);  // setweaponammoclip
        self [[ &am_count ]]();
        return;
    }
    self.mw4_am_cur = self function_f930fc7a157424fa(self.mw4_am_w);
    if (self.mw4_am_cur >= self.mw4_am_clip) return;
    self function_52af4bdf96523e46(self.mw4_am_w, self.mw4_am_clip);
    self [[ &am_count ]]();
}

function am_equip()
{
    self.mw4_am_ref = self namespace_c33cbcea986a02aa::function_339f7e9a4730e935(self.mw4_am_slot);   // getcurrentequipment
    if (!isdefined(self.mw4_am_ref)) return;
    self.mw4_am_emax = self namespace_c33cbcea986a02aa::function_75174cf5a80f1202(self.mw4_am_ref);   // getequipmentmaxammo
    self.mw4_am_ecur = self namespace_c33cbcea986a02aa::function_a29c0edcfade60cc(self.mw4_am_ref);   // getequipmentammo
    if (!isdefined(self.mw4_am_emax) || !isdefined(self.mw4_am_ecur) || self.mw4_am_emax <= 0) return;
    if (self.mw4_am_ecur >= self.mw4_am_emax) return;
    self namespace_c33cbcea986a02aa::function_7c3cf86d138e6c7c(self.mw4_am_slot, self.mw4_am_emax); // setequipmentslotammo
    self [[ &am_count ]]();
}

function am_count()
{
    level.mw4_cfg_n_am++;
    if (level.mw4_cfg_lg_am) return;
    level.mw4_cfg_lg_am = 1;
    [[ &cfg_log ]]("unlimited ammo: first refill for " + [[ &cfg_self_name ]]() + " (this match)");
}

// ---- bot difficulty (cmd 10)
// bots_util::bot_set_difficulty (bots_util.gsc:70-87) = botsetdifficulty + self.difficulty +
// pers["bot_difficulty"], plus a rank xp update when the engine value changes. bot_think applies
// pers["bot_difficulty"] again on every life (bots.gsc:1639-1642, 1746-1748), so writing these three (without
// the rank part) lasts over spawns and rounds and the next bot_think life finds nothing to change. The lobby
// values are kept in pers and written back raw on "lobby" (no rank table lookup, so "master" is fine).

function bd_name(mode)
{
    if (mode == 1) return "recruit";
    if (mode == 2) return "regular";
    if (mode == 3) return "hardened";
    if (mode == 4) return "veteran";
    return undefined;
}

function bd_label(mode)
{
    if (mode >= 1 && mode <= 4) return [[ &bd_name ]](mode);
    return "lobby setting";
}

function bd_bot()
{
    if (isdefined(level.mw4_cfg_dname))
    {
        // stock has not set this bot up yet (bot_think writes self.difficulty on every life, bots.gsc:1639-1642,
        // spawn_bots on add, bots.gsc:1172-1180): wait, so the recorded lobby value is the stock one
        if (!isdefined(level.mw4_cfg_p.var_3fcbf3566b3378a3)) return;
        if (isdefined(level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_bd_orig"]) && level.mw4_cfg_p.mw4_bd_set === level.mw4_cfg_dname
            && level.mw4_cfg_p.var_3fcbf3566b3378a3 === level.mw4_cfg_dname
            && level.mw4_cfg_p.var_8b69ecbd466a79fa["bot_difficulty"] === level.mw4_cfg_dname) return;   // field reads only
        level.mw4_cfg_p thread [[ &bd_on ]]();
        return;
    }
    if (!isdefined(level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_bd_orig"])) return;   // lobby setting: never touched
    level.mw4_cfg_p thread [[ &bd_off ]]();
}

// self = bot (own thread).
function bd_on()
{
    self.mw4_bd_cur = self function_92dbcbda33bf29f8();                 // botgetdifficulty (bots_util.gsc:77)
    if (!isdefined(self.mw4_bd_cur)) return;
    if (!isdefined(self.var_8b69ecbd466a79fa["mw4_bd_orig"]))
    {
        self.var_8b69ecbd466a79fa["mw4_bd_orig"] = self.mw4_bd_cur;
        self.var_8b69ecbd466a79fa["mw4_bd_origf"] = self.var_3fcbf3566b3378a3;
        self.var_8b69ecbd466a79fa["mw4_bd_origp"] = self.var_8b69ecbd466a79fa["bot_difficulty"];
    }
    self.mw4_bd_set = level.mw4_cfg_dname;
    if (self.mw4_bd_cur === level.mw4_cfg_dname && self.var_3fcbf3566b3378a3 === level.mw4_cfg_dname
        && self.var_8b69ecbd466a79fa["bot_difficulty"] === level.mw4_cfg_dname) return;
    self function_b86b22e4f34c24ec(level.mw4_cfg_dname);                 // botsetdifficulty (bots_util.gsc:78)
    self.var_3fcbf3566b3378a3 = level.mw4_cfg_dname;                     // self.difficulty (bots_util.gsc:79)
    self.var_8b69ecbd466a79fa["bot_difficulty"] = level.mw4_cfg_dname;   // (bots_util.gsc:80)
    level.mw4_cfg_n_bd++;
    if (level.mw4_cfg_lg_bd) return;
    level.mw4_cfg_lg_bd = 1;
    [[ &cfg_log ]]("bot difficulty " + [[ &cfg_self_name ]]() + ": " + self.mw4_bd_cur + " -> " + level.mw4_cfg_dname
        + " (lobby value " + self.var_8b69ecbd466a79fa["mw4_bd_orig"] + "; first bot this match)");
}

// self = bot (own thread). Markers first, so a failure can never repeat every pass.
function bd_off()
{
    self.mw4_bd_orig = self.var_8b69ecbd466a79fa["mw4_bd_orig"];
    self.var_8b69ecbd466a79fa["mw4_bd_orig"] = undefined;
    self.mw4_bd_set = undefined;
    self function_b86b22e4f34c24ec(self.mw4_bd_orig);
    self.var_3fcbf3566b3378a3 = self.var_8b69ecbd466a79fa["mw4_bd_origf"];
    self.var_8b69ecbd466a79fa["bot_difficulty"] = self.var_8b69ecbd466a79fa["mw4_bd_origp"];
    self.var_8b69ecbd466a79fa["mw4_bd_origf"] = undefined;
    self.var_8b69ecbd466a79fa["mw4_bd_origp"] = undefined;
    level.mw4_cfg_n_bdr++;
    if (level.mw4_cfg_lg_bdr) return;
    level.mw4_cfg_lg_bdr = 1;
    [[ &cfg_log ]]("bot difficulty " + [[ &cfg_self_name ]]() + " back to the lobby value " + self.mw4_bd_orig + " (first bot this match)");
}

// ---- freeze bots (cmd 12)
// Three layers: an own val context with the keys of the stock prematch freeze (playerlogic.gsc:107-118),
// freezecontrols(1) and BotSetFlag disable_movement / _rotation / _attack (bots.gsc:3885-3889). Release
// removes only the own context (val::reset_all, values.gsc:779-800), so a stock "prematch" entry keeps the
// bots frozen until the stock prematch end; then the stock freeze stack decides about freezecontrols
// (_refreshfreezecontrols, player.gsc:1270-1308; prematch itself never uses the stack, playerlogic.gsc:4048-4053).
// val calls add endon("disconnect") to the CALLING thread (values.gsc:1172-1177): always "bot thread".
// freezecontrols and the flags go again on every pass: stock writes freezecontrols(0) on spawn and at the
// prematch end (playerlogic.gsc:3604-3621, gamelogic.gsc:5765) and stock bot code clears disable_movement.

function bf_bot()
{
    if (level.mw4_cfg_freeze > 0)
    {
        if (!level.mw4_cfg_alive) return;
        if (!isdefined(level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_bf_on"]))
        {
            level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_bf_on"] = 1;
            level.mw4_cfg_n_bf++;
            if (!level.mw4_cfg_lg_bf)
            {
                level.mw4_cfg_lg_bf = 1;
                [[ &cfg_log ]]("bot frozen: " + [[ &cfg_name ]]() + " (first bot this match)");
            }
        }
        if (!(level.mw4_cfg_p.mw4_bf_life === level.mw4_cfg_p.var_c2db1b2eb73638c))
        {
            level.mw4_cfg_p.mw4_bf_life = level.mw4_cfg_p.var_c2db1b2eb73638c;   // once per life (spawntime, playerlogic.gsc:3200)
            level.mw4_cfg_p thread [[ &bf_vals_on ]]();
        }
        level.mw4_cfg_p function_a176070c70b75053(1);                       // freezecontrols
        level.mw4_cfg_p function_9dfcfc6e680af2db("disable_movement", 1);   // BotSetFlag
        level.mw4_cfg_p function_9dfcfc6e680af2db("disable_rotation", 1);
        level.mw4_cfg_p function_9dfcfc6e680af2db("disable_attack", 1);
        return;
    }
    if (!isdefined(level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_bf_on"])) return;   // never frozen by us
    level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_bf_on"] = undefined;
    level.mw4_cfg_p.mw4_bf_life = undefined;
    level.mw4_cfg_n_bfr++;
    if (!level.mw4_cfg_lg_bfr)
    {
        level.mw4_cfg_lg_bfr = 1;
        [[ &cfg_log ]]("bot released: " + [[ &cfg_name ]]() + " (first bot this match)");
    }
    level.mw4_cfg_p thread [[ &bf_off ]]();
}

// self = bot (own thread).
function bf_vals_on()
{
    self.mw4_bf_vals = 1;
    self namespace_214d79f87f4bf971::function_b2fc2925c70ceb16("mw4_botfix_freeze", "allow_movement", 0);   // val::set
    self namespace_214d79f87f4bf971::function_b2fc2925c70ceb16("mw4_botfix_freeze", "fire", 0);
    self namespace_214d79f87f4bf971::function_b2fc2925c70ceb16("mw4_botfix_freeze", "offhand_weapons", 0);
    self namespace_214d79f87f4bf971::function_b2fc2925c70ceb16("mw4_botfix_freeze", "offhand_primary_weapons", 0);
    self namespace_214d79f87f4bf971::function_b2fc2925c70ceb16("mw4_botfix_freeze", "offhand_secondary_weapons", 0);
    self namespace_214d79f87f4bf971::function_b2fc2925c70ceb16("mw4_botfix_freeze", "supers", 0);
    self namespace_214d79f87f4bf971::function_b2fc2925c70ceb16("mw4_botfix_freeze", "allow_jump", 0);
    self namespace_214d79f87f4bf971::function_b2fc2925c70ceb16("mw4_botfix_freeze", "melee", 0);
    self namespace_214d79f87f4bf971::function_b2fc2925c70ceb16("mw4_botfix_freeze", "sprint", 0);
    self namespace_214d79f87f4bf971::function_b2fc2925c70ceb16("mw4_botfix_freeze", "killstreaks", 0);
    self namespace_214d79f87f4bf971::function_b2fc2925c70ceb16("mw4_botfix_freeze", "usability", 0);
}

// self = bot (own thread).
function bf_off()
{
    self function_9dfcfc6e680af2db("disable_movement", 0);
    self function_9dfcfc6e680af2db("disable_rotation", 0);
    self function_9dfcfc6e680af2db("disable_attack", 0);
    self namespace_5b53f19c893758d7::function_45e90c1865e79dbf();                        // _refreshfreezecontrols
    // After a round restart the own context is gone (new script instance, marker only in pers): set it once
    // more, so that reset_all hands the keys back to the stock winner or default (values.gsc:779-800, 1001-1029).
    if (!isdefined(self.mw4_bf_vals)) self [[ &bf_vals_on ]]();
    self.mw4_bf_vals = undefined;
    self namespace_214d79f87f4bf971::function_9a5ee51116044765("mw4_botfix_freeze");      // val::reset_all (own context)
}

// ================================================================ DEV 25 (Henrik 2026-10-24/25)
// No locals in this block unless noted (ACTS store loss after wait / builtin method): state is in fields.
// Every helper that runs inside the cfg_tick player loop uses its own level.mw4_<prefix>_* scratch fields
// and never touches level.mw4_cfg_i / _k / _q (thread calls run synchronously until their first wait).

// ---- bot weapons: apply a menu change at once (cmd 1 / cmd 2)
// Stock MP caches each built loadout struct in pers[#"hash_c73fe5b925f4eeb3"][class] (class.gsc:9480-9494);
// a bot's class is "callback" and every respawn takes the cached struct (playerlogic.gsc:3104-3108 ->
// class.gsc:492-528 -> giveLoadout 7862-7867), so lr_struct_hook ran only on the first spawn of a match.
// The hook stores mask*100+fixed in pers["mw4_lr_sig"]; when it differs from the dvars the cache is dropped
// (the state before the first spawn) and the next spawn builds through the hook again. Living bots also get
// the stock mid-life class change: preload (class.gsc:9078, rebuild + re-cache through the hook) and
// swapLoadout (class.gsc:9082 / 7760-7829).

function lr_sig_now()
{
    return function_b4b0c0cb1ac2b968(@"mw4_botfix_allow", 63) * 100 + function_b4b0c0cb1ac2b968(@"mw4_botfix_fixed", 0);
}

function lr_refresh_bots()
{
    level.mw4_lr_sig = [[ &lr_sig_now ]]();
    level.mw4_lr_logs = 0;
    level.mw4_lr_nd = 0;
    level.mw4_lr_ns = 0;
    level.mw4_lr_nw = 0;
    if (isdefined(level.var_10f4ff41c4b7f0ac))
    {
        for (level.mw4_lr_i = 0; level.mw4_lr_i < level.var_10f4ff41c4b7f0ac.size; level.mw4_lr_i++)
        {
            level.mw4_lr_p = level.var_10f4ff41c4b7f0ac[level.mw4_lr_i];
            [[ &lr_refresh_one ]](1);
        }
    }
    level.mw4_lr_p = undefined;
    [[ &lr_log ]]("weapon refresh: " + level.mw4_lr_nd + " bot loadouts rebuilt, " + level.mw4_lr_ns + " living bots switch now, "
        + level.mw4_lr_nw + " later (dead, spawning or busy: retried)");
}

// level.mw4_lr_p = the player, level.mw4_lr_sig = the wanted signature.
function lr_refresh_one(swap)
{
    level.mw4_lr_swap = swap;
    if (!isdefined(level.mw4_lr_p) || !isdefined(level.mw4_lr_p.var_8b69ecbd466a79fa)) return;
    if (!function_aad3cad3abf3c14f(level.mw4_lr_p)) return;                                   // real bot clients only
    if (!isdefined(level.mw4_lr_p.var_c2db1b2eb73638c) && !isdefined(level.mw4_lr_p.var_8b69ecbd466a79fa["mw4_lr_sig"])) return;   // nothing built yet
    if (level.mw4_lr_p.var_8b69ecbd466a79fa["mw4_lr_sig"] === level.mw4_lr_sig) return;     // (undefined = mismatch)
    if (!isdefined(level.mw4_lr_p.var_29e122bc4f99e591)) return;   // no classCallback: a "callback" rebuild would assert (class.gsc:1075)
    level.mw4_lr_p.var_8b69ecbd466a79fa["mw4_lr_sig"] = level.mw4_lr_sig;
    level.mw4_lr_p.var_8b69ecbd466a79fa[#"hash_c73fe5b925f4eeb3"] = undefined;               // stock loadout cache
    level.mw4_lr_p.var_598528c4a86e63ab = undefined;   // a struct preloaded for a spawn in progress: giveLoadout rebuilds (class.gsc:7862-7872)
    level.mw4_lr_nd++;
    if (!level.mw4_lr_swap) return;
    level.mw4_lr_p.mw4_lr_waitlog = undefined;
    level.mw4_lr_p.mw4_lr_req = gettime();             // retried by cfg_player until done or the bot has spawned again
    level.mw4_lr_p thread [[ &lr_swap ]]();
}

// self = bot, own thread (the stock rebuild can waitframe on its lock, class.gsc:5731-5734).
// Runs for a pending request (self.mw4_lr_req); a bot that cannot swap right now keeps the request and
// cfg_player calls this again every pass. A spawn after the request already built the new loadout.
function lr_swap()
{
    if (!isdefined(self.mw4_lr_req)) return;
    if (isdefined(self.var_c2db1b2eb73638c) && self.var_c2db1b2eb73638c > self.mw4_lr_req)
    {
        self.mw4_lr_req = undefined;
        self.mw4_lr_waitlog = undefined;
        return;
    }
    // short conditions (one long chain risks the ACTS parser stack)
    self.mw4_lr_bad = 0;
    if (!(self.var_948fe687565941e7 === "playing") || !isdefined(self.var_d2c854047ddd1dbc) || self.var_d2c854047ddd1dbc <= 0) self.mw4_lr_bad = 1;
    if (istrue(self.var_e5cc746798bed3ae) || istrue(self.var_d0697a2251283e17) || !(game["state"] === "playing")) self.mw4_lr_bad = 1;
    if (!isdefined(self.var_8b69ecbd466a79fa["class"]) || self.var_8b69ecbd466a79fa["class"] === "") self.mw4_lr_bad = 1;
    if (!isdefined(self.var_8b69ecbd466a79fa["team"])) self.mw4_lr_bad = 1;
    if (self.mw4_lr_bad)
    {
        if (!isdefined(self.mw4_lr_waitlog))
        {
            self.mw4_lr_waitlog = 1;
            level.mw4_lr_nw++;
        }
        return;
    }
    self.mw4_lr_req = undefined;
    self.mw4_lr_waitlog = undefined;
    level.mw4_lr_ns++;
    self namespace_9cc2bd30d111a0ae::function_40863b0639eaf329(self.var_8b69ecbd466a79fa["class"]);   // class:: preload
    self namespace_9cc2bd30d111a0ae::swapLoadout();
}

// ---- my skin list: the pool size of my team for the Lua list (did not exist before the first cmd 3)
// level.mw4_cfg_p = the human. The pools are built by stock teams::init before StartGameTypeCallbackFinished.
function skin_publish()
{
    if (!isdefined(level.mw4_bs_pairs)) return;
    level.mw4_sp_team = "allies";
    if (level.mw4_cfg_p.team === "axis") level.mw4_sp_team = "axis";
    if (!isdefined(level.mw4_bs_pairs[level.mw4_sp_team])) return;
    level.mw4_sp_n = level.mw4_bs_pairs[level.mw4_sp_team].size;
    if (level.mw4_sp_n <= 0) return;
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_skin_count", -1) == level.mw4_sp_n) return;
    function_b45d7cc91040f5d3(@"mw4_botfix_skin_count", level.mw4_sp_n);
    [[ &lr_publish ]]();
}

// ---- headshots only (cmd 13)
// The stock player damage callback asks level.var_a44ba6c01eac941 whether to drop a hit (damage.gsc:360-363,
// after filterDamage, the last-stand tick and the prematch block, before friendly fire, spawn protection,
// hitmarker, attacker tracking and finishPlayerDamage). Stock sets it only in the arcade mode
// (script_32c2f4a699e57e1e.gsc:64, after "prematch_started"); that predicate is chained. Installed only while
// the mode is on, re-checked every watchdog pass.
// Rule while on: a hit on a bot from a HUMAN player (directly or through his killstreak / agent) counts only as
// a bullet to "head" / "helmet" (stock isheadshot, damage_utility.gsc:436-449); everything else from him is
// dropped (body shots, explosives, melee, fire, impact, killstreaks, a human-driven vehicle). World damage
// (trigger_hurt, falls, crush by the map, out of bounds = attacker self), bot attackers, finishers, last stand
// and friendly fire stay stock.

function hs_hook()
{
    if (level.mw4_cfg_hs > 0)
    {
        if (isdefined(level.var_a44ba6c01eac941) && level.var_a44ba6c01eac941 == &hs_filter) return;
        level.mw4_hs_prev = level.var_a44ba6c01eac941;   // undefined, or the stock arcade predicate
        level.var_a44ba6c01eac941 = &hs_filter;
        level.mw4_hs_on = 1;
        level.mw4_hs_ni++;
        if (level.mw4_hs_ni == 1) [[ &cfg_log ]]("headshots only: damage filter installed");
        return;
    }
    if (!isdefined(level.mw4_hs_on)) return;
    level.mw4_hs_on = undefined;
    level.var_a44ba6c01eac941 = level.mw4_hs_prev;
    level.mw4_hs_prev = undefined;
    [[ &cfg_log ]]("headshots only: damage filter removed (" + level.mw4_hs_n + " hits blocked)");
}

// Runs inside the engine damage event: no wait, no builtin method call, no local stores (params and level
// fields only). Return 1 = stock drops the hit.
function hs_filter(inflictor, attacker, victim, damage, flags, mod, unk7, weapon, point, dir, hitloc, offset, unk13, part, unk15, unk16)
{
    if (isdefined(level.mw4_hs_prev) && !istrue(level.mw4_hs_in))
    {
        level.mw4_hs_in = 1;
        level.mw4_hs_r = [[ level.mw4_hs_prev ]](inflictor, attacker, victim, damage, flags, mod, unk7, weapon, point, dir, hitloc, offset, unk13, part, unk15, unk16);
        level.mw4_hs_in = undefined;
        if (istrue(level.mw4_hs_r)) return 1;
    }
    if (!isdefined(level.mw4_cfg_hs) || level.mw4_cfg_hs <= 0) return 0;
    if (!isdefined(victim) || !isdefined(attacker) || attacker === victim) return 0;   // world / self damage
    if (!(victim [[ &lr_is_bot ]]())) return 0;                                          // humans never
    if (istrue(victim.var_d0697a2251283e17)) return 0;                                  // last stand: stock
    level.mw4_hs_a = attacker;
    if (!function_503f9a7fd00943c7(level.mw4_hs_a) && isdefined(level.mw4_hs_a.owner)) level.mw4_hs_a = level.mw4_hs_a.owner;
    if (!isdefined(level.mw4_hs_a) || !function_503f9a7fd00943c7(level.mw4_hs_a) || level.mw4_hs_a === victim) return 0;   // map hazards
    if (level.mw4_hs_a [[ &lr_is_bot ]]()) return 0;                                    // bot vs bot: stock
    if (mod === "MOD_EXECUTION" || mod === "MOD_MELEE_TAKEDOWN") return 0;              // finishers
    if (damage::function_2fd1574113dfff1b(victim, level.mw4_hs_a)) return 0;            // friendly fire: stock rules
    if ((mod === "MOD_RIFLE_BULLET" || mod === "MOD_PISTOL_BULLET" || mod === "MOD_HEAD_SHOT" || mod === "MOD_EXPLOSIVE_BULLET")
        && (hitloc === "head" || hitloc === "helmet"))
    {
        if (!level.mw4_hs_lga)
        {
            level.mw4_hs_lga = 1;
            [[ &cfg_log ]]("headshots only: first headshot on a bot this match (" + mod + ", " + hitloc + ")");
        }
        return 0;
    }
    level.mw4_hs_n++;
    if (!level.mw4_hs_lgb)
    {
        level.mw4_hs_lgb = 1;
        level.mw4_hs_t1 = "?";
        level.mw4_hs_t2 = "?";
        if (isdefined(mod)) level.mw4_hs_t1 = "" + mod;
        if (isdefined(hitloc)) level.mw4_hs_t2 = "" + hitloc;
        [[ &cfg_log ]]("headshots only: first blocked hit on a bot this match (" + level.mw4_hs_t1 + ", " + level.mw4_hs_t2 + ")");
    }
    return 1;
}

// ---- bot respawn delay (cmd 14)
// waitAndSpawnClient takes self.var_1e503ec3975df6f0 instead of the computed delay and its floor, then
// clears it (playerlogic.gsc:943-951); no stock script writes it. It is set once per death of a bot, after
// the stock death wait (1.75 s, damage.gsc:7490) has started, so the bot respawns that many seconds after it.
// The bot killcam (victim field var_bd035b8c3552b972, damage.gsc:8154) is switched off for bots while the
// setting is active, otherwise it would run first. Not in modes with limited lives, wave respawns, an own
// spawnClient, or a mode callback that returns its own delay (HQ, wm, tdef ...): those stay stock.

function rd_seconds(mode)
{
    if (mode == 1) return 0;
    if (mode == 2) return 1;
    if (mode == 3) return 2;
    if (mode == 4) return 3;
    if (mode == 5) return 5;
    if (mode == 6) return 10;
    if (mode == 7) return 15;
    return -1;
}

function rd_label(mode)
{
    if (mode <= 0) return "default";
    if (mode == 1) return "instant";
    return "" + [[ &rd_seconds ]](mode) + " s";
}

function rd_tick()
{
    level.mw4_cfg_rdv = [[ &rd_seconds ]](level.mw4_cfg_brd);
    level.mw4_cfg_rdok = 1;
    if (!(game["state"] === "playing") || istrue(level.var_9ff6e401c5578760)) level.mw4_cfg_rdok = 0;
    if (isdefined(level.numLives) && level.numLives > 0) level.mw4_cfg_rdok = 0;
    if (function_8d35635fa0f5f852("commonOption", "waveRespawnDelay") > 0) level.mw4_cfg_rdok = 0;
    if (isdefined(level.var_f212e6a5f628683)) level.mw4_cfg_rdok = 0;
    if (level.mw4_cfg_lg_rdinfo || level.mw4_cfg_rdv < 0) return;
    level.mw4_cfg_lg_rdinfo = 1;
    level.mw4_cfg_rdstock = function_8d35635fa0f5f852("commonOption", "respawnDelay");
    if (!isdefined(level.mw4_cfg_rdstock)) level.mw4_cfg_rdstock = "?";
    level.mw4_cfg_rdlives = "-";
    if (isdefined(level.numLives)) level.mw4_cfg_rdlives = level.numLives;
    [[ &cfg_log ]]("bot respawn delay " + level.mw4_cfg_rdv + " s active=" + level.mw4_cfg_rdok + " (stock respawnDelay="
        + level.mw4_cfg_rdstock + " numLives=" + level.mw4_cfg_rdlives + ")");
}

// level.mw4_cfg_p = a real bot client.
function rd_bot()
{
    if (level.mw4_cfg_rdv < 0 || !level.mw4_cfg_rdok)
    {
        [[ &rd_restore ]]();
        return;
    }
    if (!istrue(level.mw4_cfg_p.var_bd035b8c3552b972))
    {
        level.mw4_cfg_p.var_bd035b8c3552b972 = 1;   // no bot killcam
        level.mw4_cfg_p.mw4_rd_kc = 1;
    }
    if (!isdefined(level.mw4_cfg_p.var_557c110747b750fd) || !isdefined(level.mw4_cfg_p.var_c2db1b2eb73638c)) return;
    if (level.mw4_cfg_p.var_557c110747b750fd < level.mw4_cfg_p.var_c2db1b2eb73638c)
    {
        // alive since its last death: an override that was never used goes away
        if (isdefined(level.mw4_cfg_p.mw4_rd_set))
        {
            level.mw4_cfg_p.var_1e503ec3975df6f0 = undefined;
            level.mw4_cfg_p.mw4_rd_set = undefined;
        }
        return;
    }
    if (level.mw4_cfg_p.mw4_rd_death === level.mw4_cfg_p.var_557c110747b750fd && level.mw4_cfg_p.mw4_rd_want === level.mw4_cfg_rdv) return;
    if (!istrue(level.mw4_cfg_p.hasSpawned)) return;
    level.mw4_cfg_p.mw4_rd_death = level.mw4_cfg_p.var_557c110747b750fd;   // markers first
    level.mw4_cfg_p.mw4_rd_want = level.mw4_cfg_rdv;
    level.mw4_cfg_p thread [[ &rd_set ]]();
}

// self = bot, own thread (a mode callback could fail).
function rd_set()
{
    if (isdefined(level.var_999c6abb40d69260))
    {
        self.mw4_rd_mode = self [[ level.var_999c6abb40d69260 ]]();   // default returns nothing (utility.gsc:8902)
        if (isdefined(self.mw4_rd_mode))
        {
            level.mw4_cfg_n_rdskip++;
            return;
        }
    }
    self.mw4_rd_set = self.mw4_rd_want;
    self.var_1e503ec3975df6f0 = self.mw4_rd_want;
    level.mw4_cfg_n_rd++;
    if (level.mw4_cfg_lg_rd) return;
    level.mw4_cfg_lg_rd = 1;
    [[ &cfg_log ]]("bot respawn delay " + self.mw4_rd_want + " s set for " + [[ &cfg_self_name ]]() + " (first bot this match)");
}

// level.mw4_cfg_p = a bot. Only bots we touched are written.
function rd_restore()
{
    if (isdefined(level.mw4_cfg_p.mw4_rd_kc))
    {
        level.mw4_cfg_p.mw4_rd_kc = undefined;
        level.mw4_cfg_p.var_bd035b8c3552b972 = undefined;
    }
    if (isdefined(level.mw4_cfg_p.mw4_rd_set))
    {
        level.mw4_cfg_p.mw4_rd_set = undefined;
        level.mw4_cfg_p.var_1e503ec3975df6f0 = undefined;
        level.mw4_cfg_n_rdr++;
    }
    level.mw4_cfg_p.mw4_rd_death = undefined;
    level.mw4_cfg_p.mw4_rd_want = undefined;
}

// ---- bot skins (cmd 15-21)
// A skin = its number k in skin_pairs(team) (operator/skin refs are hashes); lists with both teams use a code:
// allies skin k = k, axis skin k = 100 + k. Applied with the calls of my own skin (operator::function_8a20b5520866f917
// + teams::function_1a7cd43628ac2797). Stock keeps a bot's operatorCustomization over respawns and only puts
// it on again (class.gsc:3581-3615), so a skin set once stays; "new every respawn" picks the next skin when the
// bot dies and sets only the data while it is dead, the respawn puts it on (no flicker). While the mode is on,
// built bot loadouts get no struct.operator (class.gsc:3581-3591 would otherwise reset the operator).
// Order: own skin of the bot's slot > skin of its team > random from the team's allowed pool (least worn first).
// At most 3 attempts per bot and life (a skin the engine refuses would otherwise be set again every pass).

function bs_init()
{
    level.mw4_bs_pairs = [];
    level.mw4_bs_pairs["allies"] = [[ &skin_pairs ]]("allies");
    level.mw4_bs_pairs["axis"] = [[ &skin_pairs ]]("axis");
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_count_allies", level.mw4_bs_pairs["allies"].size);
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_count_axis", level.mw4_bs_pairs["axis"].size);
    level.mw4_bs_slotent = [];
    level.mw4_bs_names_pub = "-";
    level.mw4_bs_bots_pub = -1;
    level.mw4_bs_sig = 0;
    level.mw4_bs_n = 0;
    level.mw4_bs_nr = 0;
    level.mw4_bs_nfail = 0;
    level.mw4_bs_lg = 0;
    level.mw4_bs_lgr = 0;
    level.mw4_bs_lgf = 0;
    [[ &bs_read ]]();
    [[ &cfg_log ]]("bot skins: pools allies=" + level.mw4_bs_pairs["allies"].size + " axis=" + level.mw4_bs_pairs["axis"].size
        + ", " + [[ &bs_label ]](15, level.mw4_bs_mode));
}

function bs_count(team)
{
    if (!isdefined(level.mw4_bs_pairs) || !isdefined(level.mw4_bs_pairs[team])) return 0;
    return level.mw4_bs_pairs[team].size;
}

function bs_code_valid(code)
{
    if (code >= 1 && code <= [[ &bs_count ]]("allies")) return 1;
    if (code >= 101 && code <= 100 + [[ &bs_count ]]("axis")) return 1;
    return 0;
}

function bs_code_name(code)
{
    if (code > 100) return "Axis " + (code - 100);
    return "Allies " + code;
}

// Settings from the dvars (GSC writes them; they carry over into the next match).
function bs_read()
{
    level.mw4_bs_mode = function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_mode", 0);
    if (level.mw4_bs_mode < 0 || level.mw4_bs_mode > 2) level.mw4_bs_mode = 0;
    level.mw4_bs_fix = [];
    level.mw4_bs_fix["allies"] = function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_fix_allies", 0);
    level.mw4_bs_fix["axis"] = function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_fix_axis", 0);
    if (level.mw4_bs_fix["allies"] < 0 || level.mw4_bs_fix["allies"] > [[ &bs_count ]]("allies")) level.mw4_bs_fix["allies"] = 0;
    if (level.mw4_bs_fix["axis"] < 0 || level.mw4_bs_fix["axis"] > [[ &bs_count ]]("axis")) level.mw4_bs_fix["axis"] = 0;
    level.mw4_bs_block = [];
    level.mw4_bs_block["allies"] = function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_block_allies", 0);
    level.mw4_bs_block["axis"] = function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_block_axis", 0);
    level.mw4_bs_slot = [];
    level.mw4_bs_txt = function_cf1241c266463447(@"mw4_botfix_bs_slots", "");
    level.mw4_bs_parts = function_8e6d6d99dbe52af1(level.mw4_bs_txt, ",");
    for (level.mw4_bs_j = 1; level.mw4_bs_j <= 17; level.mw4_bs_j++)
    {
        level.mw4_bs_slot[level.mw4_bs_j] = 0;
        if (isdefined(level.mw4_bs_parts) && level.mw4_bs_parts.size == 17)
        {
            level.mw4_bs_slot[level.mw4_bs_j] = int(level.mw4_bs_parts[level.mw4_bs_j - 1]);
            if (level.mw4_bs_slot[level.mw4_bs_j] != 0 && ![[ &bs_code_valid ]](level.mw4_bs_slot[level.mw4_bs_j])) level.mw4_bs_slot[level.mw4_bs_j] = 0;
        }
    }
    level.mw4_bs_parts = undefined;
}

function bs_write_slots()
{
    level.mw4_bs_txt = "";
    for (level.mw4_bs_j = 1; level.mw4_bs_j <= 17; level.mw4_bs_j++)
    {
        if (level.mw4_bs_j > 1) level.mw4_bs_txt = level.mw4_bs_txt + ",";
        level.mw4_bs_txt = level.mw4_bs_txt + level.mw4_bs_slot[level.mw4_bs_j];
    }
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_slots", level.mw4_bs_txt);
}

// Bit k-1 of a team's block mask set = skin k blocked for random picks.
function bs_blocked(team, k)
{
    level.mw4_bs_bit = 1;
    for (level.mw4_bs_b = 1; level.mw4_bs_b < k; level.mw4_bs_b++) level.mw4_bs_bit = level.mw4_bs_bit * 2;
    if (level.mw4_bs_block[team] & level.mw4_bs_bit) return 1;
    return 0;
}

function bs_label(cmd, arg)
{
    if (cmd == 15)
    {
        if (arg == 1) return "Bot skins: custom, keep for the match";
        if (arg == 2) return "Bot skins: custom, new every respawn";
        return "Bot skins: game default";
    }
    if (cmd == 16 || cmd == 17)
    {
        level.mw4_bs_lt = "Allies";
        if (cmd == 17) level.mw4_bs_lt = "Axis";
        if (arg <= 0) return level.mw4_bs_lt + " bot skin: random from pool";
        return level.mw4_bs_lt + " bot skin: skin " + arg;
    }
    return "?";
}

// Bot slots 1..17 for single-bot skins: the smallest free number when a bot is first seen, kept in pers.
// Publishes mw4_botfix_bs_bots (highest used slot) and mw4_botfix_bs_names (names by slot) for the Lua list.
function bs_slots()
{
    for (level.mw4_bs_j = 1; level.mw4_bs_j <= 17; level.mw4_bs_j++)
    {
        if (isdefined(level.mw4_bs_slotent[level.mw4_bs_j]) && !isdefined(level.mw4_bs_slotent[level.mw4_bs_j].var_8b69ecbd466a79fa))
            level.mw4_bs_slotent[level.mw4_bs_j] = undefined;
    }
    if (isdefined(level.var_10f4ff41c4b7f0ac))
    {
        for (level.mw4_bs_k = 0; level.mw4_bs_k < level.var_10f4ff41c4b7f0ac.size; level.mw4_bs_k++)
        {
            level.mw4_bs_q = level.var_10f4ff41c4b7f0ac[level.mw4_bs_k];
            if (!isdefined(level.mw4_bs_q) || !isdefined(level.mw4_bs_q.var_8b69ecbd466a79fa) || !function_aad3cad3abf3c14f(level.mw4_bs_q)) continue;
            if (isdefined(level.mw4_bs_q.mw4_bs_slot) && level.mw4_bs_slotent[level.mw4_bs_q.mw4_bs_slot] === level.mw4_bs_q) continue;
            level.mw4_bs_s = level.mw4_bs_q.var_8b69ecbd466a79fa["mw4_bs_slot"];
            if (isdefined(level.mw4_bs_s) && isdefined(level.mw4_bs_slotent[level.mw4_bs_s])) level.mw4_bs_s = undefined;
            if (!isdefined(level.mw4_bs_s))
            {
                for (level.mw4_bs_j = 1; level.mw4_bs_j <= 17; level.mw4_bs_j++)
                {
                    if (!isdefined(level.mw4_bs_slotent[level.mw4_bs_j]))
                    {
                        level.mw4_bs_s = level.mw4_bs_j;
                        break;
                    }
                }
            }
            if (!isdefined(level.mw4_bs_s)) continue;   // more than 17 bots
            level.mw4_bs_slotent[level.mw4_bs_s] = level.mw4_bs_q;
            level.mw4_bs_q.mw4_bs_slot = level.mw4_bs_s;
            level.mw4_bs_q.var_8b69ecbd466a79fa["mw4_bs_slot"] = level.mw4_bs_s;
        }
    }
    level.mw4_bs_q = undefined;
    level.mw4_bs_top = 0;
    level.mw4_bs_txt = "";
    for (level.mw4_bs_j = 1; level.mw4_bs_j <= 17; level.mw4_bs_j++)
    {
        if (level.mw4_bs_j > 1) level.mw4_bs_txt = level.mw4_bs_txt + ",";
        if (!isdefined(level.mw4_bs_slotent[level.mw4_bs_j])) continue;
        level.mw4_bs_top = level.mw4_bs_j;
        if (isdefined(level.mw4_bs_slotent[level.mw4_bs_j].var_6b09472177ca8529))
            level.mw4_bs_txt = level.mw4_bs_txt + level.mw4_bs_slotent[level.mw4_bs_j].var_6b09472177ca8529;
    }
    if (!(level.mw4_bs_txt === level.mw4_bs_names_pub))
    {
        level.mw4_bs_names_pub = level.mw4_bs_txt;
        function_b45d7cc91040f5d3(@"mw4_botfix_bs_names", level.mw4_bs_txt);
    }
    if (level.mw4_bs_top != level.mw4_bs_bots_pub)
    {
        level.mw4_bs_bots_pub = level.mw4_bs_top;
        function_b45d7cc91040f5d3(@"mw4_botfix_bs_bots", level.mw4_bs_top);
    }
}

// The code this bot should wear, in level.mw4_bs_want (0 = nothing to do). level.mw4_cfg_p = the bot.
function bs_want()
{
    level.mw4_bs_want = 0;
    level.mw4_bs_team = "allies";
    if (level.mw4_cfg_p.team === "axis") level.mw4_bs_team = "axis";
    level.mw4_bs_off = 0;
    if (level.mw4_bs_team == "axis") level.mw4_bs_off = 100;
    if (isdefined(level.mw4_cfg_p.mw4_bs_slot) && level.mw4_bs_slot[level.mw4_cfg_p.mw4_bs_slot] > 0)
    {
        level.mw4_bs_want = level.mw4_bs_slot[level.mw4_cfg_p.mw4_bs_slot];
        return;
    }
    if (level.mw4_bs_fix[level.mw4_bs_team] > 0)
    {
        level.mw4_bs_want = level.mw4_bs_off + level.mw4_bs_fix[level.mw4_bs_team];
        return;
    }
    // random from the pool: kept for the match (mode 1) or until the next death (mode 2)
    level.mw4_bs_key = "keep";
    if (level.mw4_bs_mode == 2)
    {
        level.mw4_bs_key = 0;
        if (isdefined(level.mw4_cfg_p.var_557c110747b750fd)) level.mw4_bs_key = level.mw4_cfg_p.var_557c110747b750fd;
    }
    level.mw4_bs_rnd = level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_bs_rnd"];
    if (isdefined(level.mw4_bs_rnd) && level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_bs_rndkey"] === level.mw4_bs_key
        && level.mw4_bs_rnd > level.mw4_bs_off && level.mw4_bs_rnd <= level.mw4_bs_off + [[ &bs_count ]](level.mw4_bs_team)
        && ![[ &bs_blocked ]](level.mw4_bs_team, level.mw4_bs_rnd - level.mw4_bs_off))
    {
        level.mw4_bs_want = level.mw4_bs_rnd;
        return;
    }
    [[ &bs_pick ]]();
    if (level.mw4_bs_want <= 0) return;
    level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_bs_rnd"] = level.mw4_bs_want;
    level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_bs_rndkey"] = level.mw4_bs_key;
}

// Random allowed skin of level.mw4_bs_team that the fewest other bots of that team wear right now.
function bs_pick()
{
    level.mw4_bs_n_team = [[ &bs_count ]](level.mw4_bs_team);
    if (level.mw4_bs_n_team <= 0) return;
    level.mw4_bs_worn = [];
    for (level.mw4_bs_j = 1; level.mw4_bs_j <= level.mw4_bs_n_team; level.mw4_bs_j++) level.mw4_bs_worn[level.mw4_bs_j] = 0;
    for (level.mw4_bs_k = 0; level.mw4_bs_k < level.var_10f4ff41c4b7f0ac.size; level.mw4_bs_k++)
    {
        level.mw4_bs_q = level.var_10f4ff41c4b7f0ac[level.mw4_bs_k];
        if (!isdefined(level.mw4_bs_q) || level.mw4_bs_q === level.mw4_cfg_p || !isdefined(level.mw4_bs_q.mw4_bs_code)) continue;
        if (!(level.mw4_bs_q.team === level.mw4_cfg_p.team)) continue;
        level.mw4_bs_c = level.mw4_bs_q.mw4_bs_code - level.mw4_bs_off;
        if (level.mw4_bs_c >= 1 && level.mw4_bs_c <= level.mw4_bs_n_team) level.mw4_bs_worn[level.mw4_bs_c]++;
    }
    level.mw4_bs_q = undefined;
    level.mw4_bs_min = -1;
    level.mw4_bs_cand = [];
    for (level.mw4_bs_pass = 0; level.mw4_bs_pass < 2 && level.mw4_bs_cand.size == 0; level.mw4_bs_pass++)
    {
        for (level.mw4_bs_j = 1; level.mw4_bs_j <= level.mw4_bs_n_team; level.mw4_bs_j++)
        {
            if (level.mw4_bs_pass == 0 && [[ &bs_blocked ]](level.mw4_bs_team, level.mw4_bs_j)) continue;   // all blocked: pass 1 takes all
            if (level.mw4_bs_min < 0 || level.mw4_bs_worn[level.mw4_bs_j] < level.mw4_bs_min)
            {
                level.mw4_bs_min = level.mw4_bs_worn[level.mw4_bs_j];
                level.mw4_bs_cand = [];
            }
            if (level.mw4_bs_worn[level.mw4_bs_j] == level.mw4_bs_min) level.mw4_bs_cand[level.mw4_bs_cand.size] = level.mw4_bs_j;
        }
    }
    if (level.mw4_bs_cand.size == 0) return;
    level.mw4_bs_want = level.mw4_bs_off + level.mw4_bs_cand[randomint(level.mw4_bs_cand.size)];
}

// Watchdog part for one bot (level.mw4_cfg_p, real bot client), every pass.
function bs_bot()
{
    if (level.mw4_bs_mode <= 0)
    {
        if (isdefined(level.mw4_cfg_p.var_8b69ecbd466a79fa["mw4_bs_on"]) && level.mw4_cfg_alive) level.mw4_cfg_p thread [[ &bs_restore ]]();
        return;
    }
    if (!isdefined(level.mw4_bs_pairs) || !isdefined(level.mw4_cfg_p.operatorCustomization)) return;
    [[ &bs_want ]]();
    if (level.mw4_bs_want <= 0) return;
    level.mw4_bs_wt = "allies";
    level.mw4_bs_wk = level.mw4_bs_want;
    if (level.mw4_bs_want > 100)
    {
        level.mw4_bs_wt = "axis";
        level.mw4_bs_wk = level.mw4_bs_want - 100;
    }
    if (level.mw4_bs_wk < 1 || level.mw4_bs_wk > [[ &bs_count ]](level.mw4_bs_wt)) return;
    level.mw4_bs_pair = level.mw4_bs_pairs[level.mw4_bs_wt][level.mw4_bs_wk - 1];
    if (!isdefined(level.mw4_bs_pair)) return;
    // the life an attempt belongs to: spawn time while alive, death time while dead
    level.mw4_bs_life = level.mw4_cfg_p.var_c2db1b2eb73638c;
    if (!level.mw4_cfg_alive)
    {
        level.mw4_bs_life = -1;
        if (isdefined(level.mw4_cfg_p.var_557c110747b750fd)) level.mw4_bs_life = -1 - level.mw4_cfg_p.var_557c110747b750fd;
    }
    if (level.mw4_cfg_p.mw4_bs_code === level.mw4_bs_want && level.mw4_cfg_p.operatorCustomization.operatorRef === level.mw4_bs_pair[0]
        && level.mw4_cfg_p.operatorCustomization.skinRef === level.mw4_bs_pair[1]) return;
    // tries count per life and per wanted skin: every new menu choice gets 3 fresh tries
    if (!(level.mw4_cfg_p.mw4_bs_tlife === level.mw4_bs_life) || !(level.mw4_cfg_p.mw4_bs_code === level.mw4_bs_want))
    {
        level.mw4_cfg_p.mw4_bs_tlife = level.mw4_bs_life;
        level.mw4_cfg_p.mw4_bs_tries = 0;
    }
    if (level.mw4_cfg_p.mw4_bs_tries >= 3)
    {
        if (level.mw4_cfg_p.mw4_bs_tries == 3)
        {
            level.mw4_cfg_p.mw4_bs_tries = 4;
            level.mw4_bs_nfail++;
            if (!level.mw4_bs_lgf)
            {
                level.mw4_bs_lgf = 1;
                [[ &cfg_log ]]("bot skin " + [[ &bs_code_name ]](level.mw4_bs_want) + " did not stay on " + [[ &cfg_name ]]() + " after 3 tries (first bot this match)");
            }
        }
        return;
    }
    level.mw4_cfg_p.mw4_bs_tries++;
    level.mw4_cfg_p.mw4_bs_code = level.mw4_bs_want;
    level.mw4_cfg_p.mw4_bs_op = level.mw4_bs_pair[0];
    level.mw4_cfg_p.mw4_bs_skin = level.mw4_bs_pair[1];
    level.mw4_cfg_p.mw4_bs_put = level.mw4_cfg_alive;   // dead: data only, the respawn puts it on
    level.mw4_cfg_p thread [[ &bs_apply ]]();
}

// self = bot, own thread.
function bs_apply()
{
    self.var_8b69ecbd466a79fa["mw4_bs_on"] = 1;
    self operator::function_8a20b5520866f917(self.mw4_bs_op, self.mw4_bs_skin);
    if (self.mw4_bs_put) self teams::function_1a7cd43628ac2797();
    level.mw4_bs_n++;
    if (level.mw4_bs_lg) return;
    level.mw4_bs_lg = 1;
    [[ &cfg_log ]]("bot skin " + [[ &bs_code_name ]](self.mw4_bs_code) + " on " + [[ &cfg_self_name ]]() + " (alive=" + self.mw4_bs_put
        + "; first bot this match)");
}

// self = bot, own thread: back to the stock selection (stock picks a new random skin, operator.gsc:1441-1445).
function bs_restore()
{
    self.var_8b69ecbd466a79fa["mw4_bs_on"] = undefined;
    self.var_8b69ecbd466a79fa["mw4_bs_rnd"] = undefined;
    self.var_8b69ecbd466a79fa["mw4_bs_rndkey"] = undefined;
    self.mw4_bs_code = undefined;
    self.mw4_bs_tlife = undefined;
    self operator::function_8a20b5520866f917();
    self teams::function_1a7cd43628ac2797();
    level.mw4_bs_nr++;
    if (level.mw4_bs_lgr) return;
    level.mw4_bs_lgr = 1;
    [[ &cfg_log ]]("bot skins back to the game default for " + [[ &cfg_self_name ]]() + " (first bot this match)");
}

// Menu commands 15-21 (self = the human who picked). Called from menu_carrier: no wait.
function bs_set(cmd, arg)
{
    level.mw4_bs_scmd = cmd;
    level.mw4_bs_sarg = arg;
    level.mw4_bs_stext = undefined;
    if (!isdefined(level.mw4_bs_pairs)) return;
    if (level.mw4_bs_scmd == 15)
    {
        if (level.mw4_bs_sarg < 0 || level.mw4_bs_sarg > 2) return;
        function_b45d7cc91040f5d3(@"mw4_botfix_bs_mode", level.mw4_bs_sarg);
        level.mw4_bs_stext = [[ &bs_label ]](15, level.mw4_bs_sarg);
    }
    else if (level.mw4_bs_scmd == 16 || level.mw4_bs_scmd == 17)
    {
        level.mw4_bs_steam = "allies";
        if (level.mw4_bs_scmd == 17) level.mw4_bs_steam = "axis";
        if (level.mw4_bs_sarg < 0 || level.mw4_bs_sarg > [[ &bs_count ]](level.mw4_bs_steam)) return;
        if (level.mw4_bs_scmd == 16) function_b45d7cc91040f5d3(@"mw4_botfix_bs_fix_allies", level.mw4_bs_sarg);
        else function_b45d7cc91040f5d3(@"mw4_botfix_bs_fix_axis", level.mw4_bs_sarg);
        level.mw4_bs_stext = [[ &bs_label ]](level.mw4_bs_scmd, level.mw4_bs_sarg);
        [[ &bs_auto_mode ]]();
    }
    else if (level.mw4_bs_scmd == 18)
    {
        if (![[ &bs_code_valid ]](level.mw4_bs_sarg)) return;
        function_b45d7cc91040f5d3(@"mw4_botfix_bs_psel", level.mw4_bs_sarg);
        [[ &bs_read ]]();
        level.mw4_bs_stext = "Pool skin " + [[ &bs_code_name ]](level.mw4_bs_sarg) + ": " + [[ &bs_pool_state ]](level.mw4_bs_sarg);
    }
    else if (level.mw4_bs_scmd == 19)
    {
        if (level.mw4_bs_sarg < 0 || level.mw4_bs_sarg > 3) return;
        [[ &bs_pool_use ]]();
    }
    else if (level.mw4_bs_scmd == 20)
    {
        if (level.mw4_bs_sarg < 1 || level.mw4_bs_sarg > 17) return;
        function_b45d7cc91040f5d3(@"mw4_botfix_bs_bsel", level.mw4_bs_sarg);
        level.mw4_bs_stext = "Single bot: bot " + level.mw4_bs_sarg + [[ &bs_slot_name ]](level.mw4_bs_sarg);
    }
    else if (level.mw4_bs_scmd == 21)
    {
        if (level.mw4_bs_sarg != 0 && ![[ &bs_code_valid ]](level.mw4_bs_sarg)) return;
        [[ &bs_read ]]();
        level.mw4_bs_ssel = function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_bsel", 1);
        if (level.mw4_bs_ssel < 1 || level.mw4_bs_ssel > 17) level.mw4_bs_ssel = 1;
        level.mw4_bs_slot[level.mw4_bs_ssel] = level.mw4_bs_sarg;
        [[ &bs_write_slots ]]();
        if (level.mw4_bs_sarg == 0) level.mw4_bs_stext = "Skin of bot " + level.mw4_bs_ssel + [[ &bs_slot_name ]](level.mw4_bs_ssel) + ": team setting";
        else level.mw4_bs_stext = "Skin of bot " + level.mw4_bs_ssel + [[ &bs_slot_name ]](level.mw4_bs_ssel) + ": " + [[ &bs_code_name ]](level.mw4_bs_sarg);
        if (level.mw4_bs_sarg != 0) [[ &bs_auto_mode ]]();
    }
    [[ &bs_read ]]();
    level.mw4_bs_sig++;
    if (!isdefined(level.mw4_bs_stext)) return;
    IPrintLn("MW4 MENU: " + level.mw4_bs_stext);
    [[ &cfg_log ]]("setting " + level.mw4_bs_stext + " (cmd " + level.mw4_bs_scmd + " arg=" + level.mw4_bs_sarg + ")");
    level.mw4_cfg_quiet = 1;
    [[ &cfg_tick ]]();
    level.mw4_cfg_quiet = 0;
}

// A team or single-bot skin needs the custom mode: switch it on and say so.
function bs_auto_mode()
{
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_mode", 0) > 0) return;
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_mode", 1);
    IPrintLn("MW4 MENU: " + [[ &bs_label ]](15, 1));
}

function bs_slot_name(slot)
{
    if (!isdefined(level.mw4_bs_slotent[slot]) || !isdefined(level.mw4_bs_slotent[slot].var_6b09472177ca8529)) return "";
    return " (" + level.mw4_bs_slotent[slot].var_6b09472177ca8529 + ")";
}

function bs_pool_state(code)
{
    level.mw4_bs_pt = "allies";
    level.mw4_bs_pk = code;
    if (code > 100)
    {
        level.mw4_bs_pt = "axis";
        level.mw4_bs_pk = code - 100;
    }
    if ([[ &bs_blocked ]](level.mw4_bs_pt, level.mw4_bs_pk)) return "blocked";
    return "allowed";
}

// cmd 19 on the selected pool skin: 0 allowed, 1 blocked, 2 allow all of that team, 3 only this skin.
function bs_pool_use()
{
    level.mw4_bs_code = function_b4b0c0cb1ac2b968(@"mw4_botfix_bs_psel", 1);
    if (![[ &bs_code_valid ]](level.mw4_bs_code)) level.mw4_bs_code = 1;
    level.mw4_bs_pt = "allies";
    level.mw4_bs_pk = level.mw4_bs_code;
    if (level.mw4_bs_code > 100)
    {
        level.mw4_bs_pt = "axis";
        level.mw4_bs_pk = level.mw4_bs_code - 100;
    }
    level.mw4_bs_all = 0;
    level.mw4_bs_bit = 1;
    for (level.mw4_bs_j = 1; level.mw4_bs_j <= [[ &bs_count ]](level.mw4_bs_pt); level.mw4_bs_j++)
    {
        if (level.mw4_bs_j == level.mw4_bs_pk) level.mw4_bs_kbit = level.mw4_bs_bit;
        level.mw4_bs_all = level.mw4_bs_all + level.mw4_bs_bit;
        level.mw4_bs_bit = level.mw4_bs_bit * 2;
    }
    level.mw4_bs_mask = level.mw4_bs_block[level.mw4_bs_pt];
    if (level.mw4_bs_sarg == 0 && (level.mw4_bs_mask & level.mw4_bs_kbit)) level.mw4_bs_mask = level.mw4_bs_mask - level.mw4_bs_kbit;
    else if (level.mw4_bs_sarg == 1 && !(level.mw4_bs_mask & level.mw4_bs_kbit)) level.mw4_bs_mask = level.mw4_bs_mask + level.mw4_bs_kbit;
    else if (level.mw4_bs_sarg == 2) level.mw4_bs_mask = 0;
    else if (level.mw4_bs_sarg == 3) level.mw4_bs_mask = level.mw4_bs_all - level.mw4_bs_kbit;
    if ((level.mw4_bs_mask & level.mw4_bs_all) == level.mw4_bs_all)
    {
        level.mw4_bs_stext = "at least one " + level.mw4_bs_pt + " skin must stay allowed";
        return;
    }
    if (level.mw4_bs_pt == "axis") function_b45d7cc91040f5d3(@"mw4_botfix_bs_block_axis", level.mw4_bs_mask);
    else function_b45d7cc91040f5d3(@"mw4_botfix_bs_block_allies", level.mw4_bs_mask);
    [[ &bs_read ]]();
    if (level.mw4_bs_sarg == 2) level.mw4_bs_stext = "all " + level.mw4_bs_pt + " skins allowed for bots";
    else if (level.mw4_bs_sarg == 3) level.mw4_bs_stext = "only " + [[ &bs_code_name ]](level.mw4_bs_code) + " allowed for " + level.mw4_bs_pt + " bots";
    else level.mw4_bs_stext = [[ &bs_code_name ]](level.mw4_bs_code) + " " + [[ &bs_pool_state ]](level.mw4_bs_code) + " for bots";
}

// ---- bot names (cmd 22-26 + payload values; the fallback uses the list when it adds bots)
// Lua (mw4_botfix_names_post.lua list): cmd 23 n, per name cmd 24 len + values 10000000 + 3 chars of 6 bits
// (first char in the lowest bits), cmd 25 signature (sum of index*position over all names + n) % 1000,
// cmd 22 mode (a complete list switches it on by itself), cmd 26 clear. Every value raises mw4_botfix_bn_rx, which paces the Lua sender. The list is kept
// in the GSC-only string dvars mw4_botfix_bn_a.._c (comma separated) for the next matches.

function bn_init()
{
    // index 0 = space, then A-Z, a-z, 0-9, _ (the Lua alphabet)
    level.mw4_bn_abc = function_8e6d6d99dbe52af1("A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z,0,1,2,3,4,5,6,7,8,9,_", ",");
    level.mw4_bn_tmp = [];
    level.mw4_bn_tmp[0] = " ";
    for (level.mw4_bn_k = 0; level.mw4_bn_k < level.mw4_bn_abc.size; level.mw4_bn_k++) level.mw4_bn_tmp[level.mw4_bn_k + 1] = level.mw4_bn_abc[level.mw4_bn_k];
    level.mw4_bn_abc = level.mw4_bn_tmp;
    level.mw4_bn_tmp = undefined;
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_bn_mode", -1) < 0) function_b45d7cc91040f5d3(@"mw4_botfix_bn_mode", 0);
    level.mw4_bn_in = undefined;
}

function bn_ack()
{
    function_b45d7cc91040f5d3(@"mw4_botfix_bn_rx", (function_b4b0c0cb1ac2b968(@"mw4_botfix_bn_rx", 0) + 1) % 100000);
}

function bn_count()
{
    level.mw4_bn_cnt = 0;
    level.mw4_bn_t = function_cf1241c266463447(@"mw4_botfix_bn_a", "") + "," + function_cf1241c266463447(@"mw4_botfix_bn_b", "") + ","
        + function_cf1241c266463447(@"mw4_botfix_bn_c", "");
    level.mw4_bn_parts = function_8e6d6d99dbe52af1(level.mw4_bn_t, ",");
    if (isdefined(level.mw4_bn_parts)) level.mw4_bn_cnt = level.mw4_bn_parts.size;
    level.mw4_bn_parts = undefined;
    return level.mw4_bn_cnt;
}

function bn_command(cmd, arg)
{
    level.mw4_bn_cmd = cmd;
    level.mw4_bn_arg = arg;
    [[ &bn_ack ]]();
    if (level.mw4_bn_cmd == 22)
    {
        if (level.mw4_bn_arg < 0 || level.mw4_bn_arg > 1) return;
        function_b45d7cc91040f5d3(@"mw4_botfix_bn_mode", level.mw4_bn_arg);
        if (level.mw4_bn_arg == 1) level.mw4_bn_text = "Bot names: custom list (" + [[ &bn_count ]]() + " names, for bots added from now on)";
        else level.mw4_bn_text = "Bot names: default";
        IPrintLn("MW4 MENU: " + level.mw4_bn_text);
        [[ &cfg_log ]]("setting " + level.mw4_bn_text + " (cmd 22 arg=" + level.mw4_bn_arg + ")");
        return;
    }
    if (level.mw4_bn_cmd == 23)
    {
        level.mw4_bn_in = [];
        level.mw4_bn_inn = level.mw4_bn_arg;
        level.mw4_bn_cur = undefined;
        level.mw4_bn_len = 0;
        level.mw4_bn_pos = 0;
        level.mw4_bn_sum = 0;
        level.mw4_bn_bad = 0;
        if (level.mw4_bn_inn < 1 || level.mw4_bn_inn > 32) level.mw4_bn_bad = 1;
        return;
    }
    if (level.mw4_bn_cmd == 24)
    {
        if (!isdefined(level.mw4_bn_in) || isdefined(level.mw4_bn_cur) || level.mw4_bn_arg < 1 || level.mw4_bn_arg > 20) level.mw4_bn_bad = 1;
        level.mw4_bn_cur = "";
        level.mw4_bn_len = level.mw4_bn_arg;
        level.mw4_bn_pos = 0;
        return;
    }
    if (level.mw4_bn_cmd == 25)
    {
        [[ &bn_finish ]]();
        return;
    }
    if (level.mw4_bn_cmd == 26)
    {
        function_b45d7cc91040f5d3(@"mw4_botfix_bn_a", "");
        function_b45d7cc91040f5d3(@"mw4_botfix_bn_b", "");
        function_b45d7cc91040f5d3(@"mw4_botfix_bn_c", "");
        function_b45d7cc91040f5d3(@"mw4_botfix_bn_count", 0);
        IPrintLn("MW4 MENU: bot name list cleared");
    }
}

// value = 10000000 + up to 3 characters of 6 bits (int() first: bit operators need an int).
function bn_payload(value)
{
    level.mw4_bn_v = int(value) - 10000000;
    [[ &bn_ack ]]();
    if (!isdefined(level.mw4_bn_in) || !isdefined(level.mw4_bn_cur))
    {
        level.mw4_bn_bad = 1;
        return;
    }
    for (level.mw4_bn_k = 0; level.mw4_bn_k < 3 && level.mw4_bn_pos < level.mw4_bn_len; level.mw4_bn_k++)
    {
        level.mw4_bn_c = (level.mw4_bn_v >> (6 * level.mw4_bn_k)) & 63;
        level.mw4_bn_cur = level.mw4_bn_cur + level.mw4_bn_abc[level.mw4_bn_c];
        level.mw4_bn_pos++;
        level.mw4_bn_sum = level.mw4_bn_sum + level.mw4_bn_c * level.mw4_bn_pos;
    }
    if (level.mw4_bn_pos < level.mw4_bn_len) return;
    level.mw4_bn_in[level.mw4_bn_in.size] = level.mw4_bn_cur;
    level.mw4_bn_cur = undefined;
}

function bn_finish()
{
    if (!isdefined(level.mw4_bn_in))
    {
        [[ &cfg_log ]]("bot names: end without begin");
        return;
    }
    level.mw4_bn_want = (level.mw4_bn_sum + level.mw4_bn_inn) % 1000;
    if (level.mw4_bn_bad || isdefined(level.mw4_bn_cur) || level.mw4_bn_in.size != level.mw4_bn_inn || level.mw4_bn_want != level.mw4_bn_arg)
    {
        IPrintLn("MW4 MENU: bot names transfer failed, pick Custom again");
        [[ &cfg_log ]]("bot names transfer failed: names " + level.mw4_bn_in.size + "/" + level.mw4_bn_inn + " signature "
            + level.mw4_bn_want + "/" + level.mw4_bn_arg + " bad=" + level.mw4_bn_bad);
        level.mw4_bn_in = undefined;
        return;
    }
    // up to 32 names of up to 20 characters: three dvars of at most 230 characters
    level.mw4_bn_out = ["", "", ""];
    level.mw4_bn_o = 0;
    for (level.mw4_bn_k = 0; level.mw4_bn_k < level.mw4_bn_in.size; level.mw4_bn_k++)
    {
        if (level.mw4_bn_out[level.mw4_bn_o].size + level.mw4_bn_in[level.mw4_bn_k].size > 210 && level.mw4_bn_o < 2) level.mw4_bn_o++;
        if (level.mw4_bn_out[level.mw4_bn_o] != "") level.mw4_bn_out[level.mw4_bn_o] = level.mw4_bn_out[level.mw4_bn_o] + ",";
        level.mw4_bn_out[level.mw4_bn_o] = level.mw4_bn_out[level.mw4_bn_o] + level.mw4_bn_in[level.mw4_bn_k];
    }
    function_b45d7cc91040f5d3(@"mw4_botfix_bn_a", level.mw4_bn_out[0]);
    function_b45d7cc91040f5d3(@"mw4_botfix_bn_b", level.mw4_bn_out[1]);
    function_b45d7cc91040f5d3(@"mw4_botfix_bn_c", level.mw4_bn_out[2]);
    function_b45d7cc91040f5d3(@"mw4_botfix_bn_count", level.mw4_bn_in.size);
    function_b45d7cc91040f5d3(@"mw4_botfix_bn_sig", level.mw4_bn_want);
    level.mw4_bn_ok = function_cf1241c266463447(@"mw4_botfix_bn_a", "") == level.mw4_bn_out[0];
    function_b45d7cc91040f5d3(@"mw4_botfix_bn_mode", 1);   // custom names on only with a complete list
    IPrintLn("MW4 MENU: " + level.mw4_bn_in.size + " bot names received, custom names on (for bots added from now on)");
    [[ &cfg_log ]]("bot names received: " + level.mw4_bn_in.size + " (" + level.mw4_bn_out[0] + ") readback ok=" + level.mw4_bn_ok);
    level.mw4_bn_in = undefined;
}

// ---- DEV 27: keep bots on the fixed weapon (cmd 2 > 0). self = living bot, own thread, no locals.
// The fixed gun is built without attachments (default reserve) and bots get no ammo; when it runs dry or the
// bot AI picks the secondary (range, after a killstreak: bots_killstreaks.gsc:181-192) the bot holds a pistol.
// Reserve of the primary object of the last give (class.gsc:6467) is kept full; a bot holding its secondary is
// switched back to the primary, at most every 3 s (the AI may switch again).
function lr_bot_keep()
{
    if (istrue(self.var_e5cc746798bed3ae) || istrue(self.var_d0697a2251283e17)) return;   // juggernaut / last stand
    if (!isdefined(level.mw4_lr_fixroot) || !(self.loadoutPrimary === level.mw4_lr_fixroot)) return;   // only the fixed gun (class.gsc:6456)
    if (!isdefined(self.var_a419fe5f19581789)) return;
    if (!(self function_68d0f034c2d1f36e(self.var_a419fe5f19581789))) return;              // hasweapon
    self.mw4_bk_max = function_16410b68f883657e(self.var_a419fe5f19581789);               // weaponmaxammo
    self.mw4_bk_cur = self function_bb22cf581da23562(self.var_a419fe5f19581789);          // getweaponammostock
    if (isdefined(self.mw4_bk_max) && isdefined(self.mw4_bk_cur) && self.mw4_bk_cur < self.mw4_bk_max)
    {
        self function_203c60b1e5c3e21e(self.var_a419fe5f19581789, self.mw4_bk_max);       // setweaponammostock
        level.mw4_lr_nammo++;
    }
    if (isdefined(self.mw4_bk_next) && gettime() < self.mw4_bk_next) return;
    if (!isdefined(self.secondaryWeapon) || self.secondaryWeapon === "none") return;      // string (class.gsc:466)
    self.mw4_bk_w = self function_e3b3cc459cc1f25b();                                       // getcurrentweapon
    if (!isdefined(self.mw4_bk_w)) return;
    self.mw4_bk_name = function_8e38d1fba3026ede(self.mw4_bk_w);                            // getcompleteweaponname
    if (!(self.mw4_bk_name === self.secondaryWeapon)) return;
    self.mw4_bk_next = gettime() + 3000;
    self function_3c68071310d8587b(self.var_a419fe5f19581789);                             // switchtoweapon
    level.mw4_lr_nback++;
    if (level.mw4_lr_lgback) return;
    level.mw4_lr_lgback = 1;
    [[ &cfg_log ]]("bot " + [[ &cfg_self_name ]]() + " switched back from its secondary to the fixed weapon (first time this match)");
}

// ---- DEV 28: sides, bot unlimited ammo, reset all

// The team of the first human player (level.mw4_cfg_hteam), every watchdog pass.
function cfg_host()
{
    level.mw4_cfg_hteam = undefined;
    if (!isdefined(level.var_10f4ff41c4b7f0ac)) return;
    for (level.mw4_cfg_hk = 0; level.mw4_cfg_hk < level.var_10f4ff41c4b7f0ac.size; level.mw4_cfg_hk++)
    {
        level.mw4_cfg_hq = level.var_10f4ff41c4b7f0ac[level.mw4_cfg_hk];
        if (!isdefined(level.mw4_cfg_hq) || level.mw4_cfg_hq [[ &lr_is_bot ]]()) continue;
        if (level.mw4_cfg_hq.team === "allies" || level.mw4_cfg_hq.team === "axis")
        {
            level.mw4_cfg_hteam = level.mw4_cfg_hq.team;
            break;
        }
    }
    level.mw4_cfg_hq = undefined;
}

// 1 = level.mw4_cfg_p counts as an enemy bot (not on the human's team; FFA: every bot).
function cfg_enemy()
{
    if (!istrue(level.teambased)) return 1;
    if (!isdefined(level.mw4_cfg_hteam)) return 1;
    if (level.mw4_cfg_p.team === level.mw4_cfg_hteam) return 0;
    return 1;
}

// cmd 29: reserve of the bot's primary and secondary (objects of the last give, class.gsc:6467 / 469) kept full.
// self = living bot, own thread, no locals.
function bb_ammo()
{
    if (istrue(self.var_e5cc746798bed3ae)) return;   // juggernaut
    self.mw4_bb_w = self.var_a419fe5f19581789;
    self [[ &bb_refill ]]();
    self.mw4_bb_w = self.var_f540ac18041bd899;
    self [[ &bb_refill ]]();
    self.mw4_bb_w = undefined;
}

function bb_refill()
{
    if (!isdefined(self.mw4_bb_w)) return;
    if (!(self function_68d0f034c2d1f36e(self.mw4_bb_w))) return;                 // hasweapon
    self.mw4_bb_max = function_16410b68f883657e(self.mw4_bb_w);                  // weaponmaxammo
    self.mw4_bb_cur = self function_bb22cf581da23562(self.mw4_bb_w);             // getweaponammostock
    if (!isdefined(self.mw4_bb_max) || !isdefined(self.mw4_bb_cur) || self.mw4_bb_cur >= self.mw4_bb_max) return;
    self function_203c60b1e5c3e21e(self.mw4_bb_w, self.mw4_bb_max);              // setweaponammostock
    level.mw4_bb_n++;
}

// cmd 30 (self = the human who picked): every BOTFIX setting back to its default. The dvars are what Lua
// shows; weapons go through the refresh, everything else through the watchdog pass right after.
function cfg_reset()
{
    function_b45d7cc91040f5d3(@"mw4_botfix_allow", 63);
    function_b45d7cc91040f5d3(@"mw4_botfix_fixed", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_auav", 2);
    function_b45d7cc91040f5d3(@"mw4_botfix_hp", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_ammo", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_speed", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_bdiff", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_bhp", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_freeze", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_hsonly", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_brespawn", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_bdiff_e", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_bhp_e", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_bammo", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_mode", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_fix_allies", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_fix_axis", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_block_allies", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_block_axis", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_psel", 1);
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_bsel", 1);
    function_b45d7cc91040f5d3(@"mw4_botfix_bs_slots", "");
    function_b45d7cc91040f5d3(@"mw4_botfix_bn_mode", 0);
    function_b45d7cc91040f5d3(@"mw4_botfix_fb_count", 100);
    [[ &lr_publish ]]();
    if (function_b4b0c0cb1ac2b968(@"mw4_botfix_skin", 0) != 0) self [[ &skin_set ]](0);   // my own skin back to the loadout
    [[ &bs_read ]]();
    level.mw4_bs_sig++;
    IPrintLn("MW4 MENU: all BOTFIX settings reset to their defaults");
    [[ &cfg_log ]]("all settings reset to their defaults (cmd 30)");
    [[ &lr_refresh_bots ]]();
    level.mw4_cfg_quiet = 1;
    [[ &cfg_tick ]]();
    level.mw4_cfg_quiet = 0;
}
