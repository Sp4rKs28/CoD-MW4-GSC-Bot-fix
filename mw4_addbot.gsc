// MW4 Botfix v1.2. Lobby-selected bots; ADS and contextual slides; no window controller.
// v1.2 (2026-10-27): withdraw thresholds relative to the bot's maxhealth (35 % / 70 %), working reload helper
// (builtin method results in bot fields; sprint/fire blocked while the clip is empty; "reload" pressed at most every
// 6 s in an own thread), no native door "use" press (it closed doors that stock had just opened).
#using script_446e0e1d717ded39;
#using scripts\mp\bots\bots_util;
#using scripts\common\system;
#using scripts\common\utility;
#using scripts\engine\utility;
#using scripts\mp\bots\bots;
#using scripts\mp\door;
#namespace mw4_addbot;
function private autoexec __init__system__()
{
    system::register( #"mw4_addbot", undefined, &__init__, undefined );
}

function __init__()
{

    level thread [[ &maintain_pickup_guard ]]();
    utility::function_fb7b1af19016b7f4( "StartGameTypeCallbackFinished" );
    level.mw4_perf_score_popups_off = true;
    // Native HUD splash gates verified in hud_util / hud_message. These
    level.var_90854497526d85e2 = true;
    level.var_58cdd295b0c5dafa = true;

    if (level.mw4_perf_score_popups_off) level.var_46dc170ddb18e3e9 = true;

    level thread [[ &maintain_fx_guards ]]();
    level thread [[ &spawn_bots_auto ]]();
}

function maintain_pickup_guard()
{
    // Native bots::bot_think_seek_dropped_weapons listens to this exact event.
    // Restore the callback after native initialization and stop old pickup threads.
    for (;;)
    {
        if (isdefined(game["state"]) && game["state"] == "postgame") return;
        if (isdefined(level.var_cc3cbaf0cb1a1b43))
            level.var_cc3cbaf0cb1a1b43["dropped_weapon_think"] = &skip_dropped_weapon_think;
        if (isdefined(level.var_10f4ff41c4b7f0ac))
        {
            for (i = 0; i < level.var_10f4ff41c4b7f0ac.size; i++)
            {
                bot = level.var_10f4ff41c4b7f0ac[i];
                if (!isdefined(bot) || !isdefined(bot.var_3215388132e3d9b5)) continue;
                bot notify("bot_think_seek_dropped_weapons");
            }
        }
        wait 0.5;
    }
}

function maintain_fx_guards()
{
    for (;;)
    {
        if (isdefined(game["state"]) && game["state"] == "postgame") return;
        level.var_90854497526d85e2 = true;
        level.var_58cdd295b0c5dafa = true;
        if (isdefined(level.var_a1afeb27a3d180ff))
        {
            if (!isdefined(level.var_a1afeb27a3d180ff.var_da7869431c7775a6)
                || !level.var_a1afeb27a3d180ff.var_da7869431c7775a6)
                level.var_a1afeb27a3d180ff.var_da7869431c7775a6 = true;
        }
        if (isdefined(level.var_b54e5d340afbe452))
            level.var_b54e5d340afbe452.var_f10d7aeea25eb7ff = &skip_first_person_blood_fx;
        wait 0.5;
    }
}

function spawn_bots_auto()
{
    wait 5;
    if ( isdefined( level.mw4_addbot_auto_started ) )
        return;
    level.mw4_addbot_auto_started = true;
    if ( !isdefined( level.var_cc3cbaf0cb1a1b43 ) || !isdefined( level.var_cc3cbaf0cb1a1b43[ "think" ] ) )
    {

        level [[ &bots::main ]]();
        wait 2;
    }
    if ( !isdefined( level.var_cc3cbaf0cb1a1b43 ) || !isdefined( level.var_cc3cbaf0cb1a1b43[ "think" ] ) )
    {
        function_8b17726cc97055("MW4 Bots: initialization failed; think callback missing");
        return;
    }
    if ( !isdefined( level.var_477af87fd16c4a08 ) || !level.var_477af87fd16c4a08 )
    {

        level [[ &bots::init ]]();
        wait 1;
    }
    if ( !isdefined( level.var_477af87fd16c4a08 ) || !level.var_477af87fd16c4a08 )
    {
        function_8b17726cc97055("MW4 Bots: initialization failed; bot init flag missing");
        return;
    }
    level.var_cc3cbaf0cb1a1b43[ "dropped_weapon_think" ] = &skip_dropped_weapon_think;

    IPrintLnBold("MW4 Botfix v1.2 loaded");
    level thread [[ &combat_fallback ]]();
    level thread [[ &movement_controller ]]();
    level thread [[ &combat_behavior ]]();
    // bots::init starts the native lobby bot connection monitor.
    // Preserve the lobby roster, teams and difficulty; do not spawn extras.

}

// Reuses the native enemy selection and last-seen timestamp.
// Logs requests separately from BOTAI; requests do not prove a shot was fired.
function combat_fallback()
{

    for ( ;; )
    {
        wait 0.2;
        if ( isdefined( game[ "state" ] ) && game[ "state" ] == "postgame" )
            return;
        if ( !isdefined( level.var_10f4ff41c4b7f0ac ) )
            continue;
        now = GetTime();
        for ( i = 0; i < level.var_10f4ff41c4b7f0ac.size; i++ )
        {
            bot = level.var_10f4ff41c4b7f0ac[ i ];
            if ( !isdefined( bot ) || !isdefined( bot.var_3215388132e3d9b5 ) )
                continue;
            update_ads(bot,now);
            if ( !isdefined( bot.var_d2c854047ddd1dbc ) || bot.var_d2c854047ddd1dbc <= 0 )
                continue;
            if ( !isdefined( bot.var_948fe687565941e7 ) || bot.var_948fe687565941e7 != "playing" )
                continue;
            if ( !isdefined( bot.Enemy ) || !isdefined( bot.var_19572a6dcd79331d ) )
                continue;
            if ( bot.var_19572a6dcd79331d <= 0 || now - bot.var_19572a6dcd79331d > 250 )
                continue;
            enemy = bot.Enemy;
            if ( enemy == bot || !isdefined( enemy.origin ) || !isdefined( bot.origin ) )
                continue;
            if ( !isdefined( enemy.var_d2c854047ddd1dbc ) || enemy.var_d2c854047ddd1dbc <= 0 )
                continue;
            if ( !isdefined( enemy.var_948fe687565941e7 ) || enemy.var_948fe687565941e7 != "playing" )
                continue;
            if ( isdefined( bot.team ) && isdefined( enemy.team ) && bot.team != "free" && bot.team == enemy.team )
                continue;
            if (isdefined(bot.mw4_sprint_active) && bot.mw4_sprint_active)
            {
                bot BotClearButton("sprint");
                bot BotClearButton("slide");
                bot.mw4_sprint_active = false;
                bot.mw4_sprint_since = undefined;
            }
            bot.mw4_combat_active_until = now + 500;
            combat_profile(bot);
            if (!isdefined(bot.mw4_focus_enemy) || bot.mw4_focus_enemy != enemy
                || !isdefined(bot.mw4_last_contact) || now - bot.mw4_last_contact > 1500)
            {
                bot.mw4_focus_enemy = enemy;
                bot.mw4_reaction_until = now + 240 + (bot.mw4_style_id % 3) * 70;
                bot.mw4_burst_until = 0;
                bot.mw4_fire_again = bot.mw4_reaction_until;
            }
            bot.mw4_last_contact = now;
            if (now < bot.mw4_reaction_until) continue;
            target_look = enemy.origin + (0,0,48);
            look = smooth_look(bot,target_look,now,0.45);
            bot [[ &bots_util::function_26196082e7a55bbd ]](look,0.35);
            // Do not fire while the smoothed aim is still crossing to a new opponent.
            if (DistanceSquared(look,target_look) <= 4096) combat_fire(bot,enemy,now);
            else bot BotClearButton("attack");
            
        }
    }
}

function move_alive(player)
{
    return isdefined(player) && isdefined(player.origin)
        && isdefined(player.var_d2c854047ddd1dbc) && player.var_d2c854047ddd1dbc > 0
        && isdefined(player.var_948fe687565941e7) && player.var_948fe687565941e7 == "playing";
}

function move_enemy(bot,player)
{
    return move_alive(player) && player != bot && isdefined(bot.team) && isdefined(player.team)
        && (bot.team == "free" || player.team != bot.team);
}

function movement_target(bot,now)
{
    // Keep a genuinely detected opponent before the general route selection.
    if (isdefined(bot.mw4_focus_enemy) && move_enemy(bot,bot.mw4_focus_enemy)
        && isdefined(bot.mw4_last_contact) && now - bot.mw4_last_contact <= 1500)
    {
        bot.mw4_move_target = bot.mw4_focus_enemy;
        bot.mw4_move_target_until = now + 1500;
        return bot.mw4_move_target;
    }
    if (isdefined(bot.mw4_move_target) && isdefined(bot.mw4_move_target_until)
        && now < bot.mw4_move_target_until && move_enemy(bot,bot.mw4_move_target))
        return bot.mw4_move_target;
    target = undefined;
    nearest = 999999999;
    for (j = 0; j < level.var_10f4ff41c4b7f0ac.size; j++)
    {
        candidate = level.var_10f4ff41c4b7f0ac[j];
        if (!move_enemy(bot,candidate)) continue;
        range_sq = DistanceSquared(bot.origin,candidate.origin);
        // Reduce target stacking among teammates; retain the selected target briefly.
        for (n = 0; n < level.var_10f4ff41c4b7f0ac.size; n++)
        {
            friend = level.var_10f4ff41c4b7f0ac[n];
            if (bot.team == "free" || !move_alive(friend) || friend == bot || !isdefined(friend.team) || friend.team != bot.team) continue;
            if (isdefined(friend.mw4_move_target) && friend.mw4_move_target == candidate)
                range_sq += 360000;
        }
        if (range_sq < nearest)
        {
            nearest = range_sq;
            target = candidate;
        }
    }
    bot.mw4_move_target = target;
    bot.mw4_move_target_until = now + 6000;
    return target;
}

// Horizontal rays avoid the floor-contact problem of the earlier capsule probes.
// The existing trace wrapper returns physics query results without surface conversion.
function move_clearance(bot,yaw,height = 36,lookahead = 96)
{
    forward = AnglesToForward((0,yaw,0));
    side = AnglesToForward((0,yaw + 90,0));
    mask = namespace_3b62da1a6fe93933::function_277bf0cd461a0ac3(1);
    clearance = 1;
    offsets = [-18,0,18];
    for (r = 0; r < offsets.size; r++)
    {
        start = bot.origin + (0,0,height) + side * offsets[r];
        finish = start + forward * lookahead;
        trace_result = namespace_3b62da1a6fe93933::function_c0049f23b50b55f0(
            start,finish,bot,mask,false);
        if (!isdefined(trace_result) || !isdefined(trace_result["fraction"])) return undefined;
        if (trace_result["fraction"] < clearance) clearance = trace_result["fraction"];
    }
    return clearance;
}

function path_clearance(bot,yaw,lookahead)
{
    low = move_clearance(bot,yaw,20,lookahead);
    high = move_clearance(bot,yaw,58,lookahead);
    if (!isdefined(low) || !isdefined(high)) return undefined;
    if (low < high) return low;
    return high;
}

function movement_heading(bot,wanted,now)
{
    // Recheck direct and cached headings every tick rather than trusting a timer.
    bot.mw4_path_blocked = false;
    // Match direct obstacle anticipation to the local step probe.
    direct = path_clearance(bot,wanted,96);
    bot.mw4_forward_clearance = direct;
    // Keep a safe detour until it has passed the corner, rather than
    // taking the briefly clear direct ray back into the same obstacle.
    if (isdefined(direct) && direct > 0.95 && crowd_penalty(bot,wanted) < 15)
    {
        if (!isdefined(bot.mw4_direct_clear_since)) bot.mw4_direct_clear_since = now;
    }
    else bot.mw4_direct_clear_since = undefined;
    if (isdefined(bot.mw4_move_heading_until) && now < bot.mw4_move_heading_until)
    {
        passed = isdefined(bot.mw4_direct_clear_since) && now - bot.mw4_direct_clear_since >= 600
            && isdefined(bot.mw4_detour_origin) && DistanceSquared(bot.origin,bot.mw4_detour_origin) >= 16384;
        cached = path_clearance(bot,bot.mw4_move_heading,288);
        if (!passed && isdefined(cached) && cached > 0.82 && crowd_penalty(bot,bot.mw4_move_heading) < 40)
        {
            bot.mw4_move_clearance = cached;
            return bot.mw4_move_heading;
        }
    }
    if (isdefined(direct) && direct > 0.9 && crowd_penalty(bot,wanted) < 15)
    {
        bot.mw4_move_heading = wanted;
        bot.mw4_move_clearance = direct;
        bot.mw4_move_heading_until = 0;
        bot.mw4_detour_origin = undefined;
        return wanted;
    }
    offsets = [35,70,105,140,180,-35,-70,-105,-140];
    if (bot.mw4_route_side < 0) offsets = [-35,-70,-105,-140,180,35,70,105,140];
    best = undefined;
    best_fraction = 0;
    best_score = -999;
    for (d = 0; d < offsets.size; d++)
    {
        heading = wanted + offsets[d];
        fraction = path_clearance(bot,heading,288);
        if (!isdefined(fraction) || fraction < 0.6) continue;
        turn = offsets[d];
        if (turn < 0) turn = 0 - turn;
        score = fraction * 100 - turn * 0.15 - crowd_penalty(bot,heading);
        // Prefer continuing along the obstacle over swapping sides repeatedly.
        if (isdefined(bot.mw4_move_heading))
        {
            change = route_angle_delta(heading - bot.mw4_move_heading);
            if (change < 0) change = 0 - change;
            score -= change * 0.12;
        }
        if (score > best_score)
        {
            best = heading;
            best_fraction = fraction;
            best_score = score;
        }
        if (fraction > 0.95 && score > 85) break;
    }
    // In cramped areas, only request a short, slow move in a checked direction.
    if (!isdefined(best))
    {
        short_offsets = [90,-90,180,45,-45,135,-135,0];
        for (s = 0; s < short_offsets.size; s++)
        {
            heading = wanted + short_offsets[s];
            fraction = path_clearance(bot,heading,96);
            if (!isdefined(fraction) || fraction < 0.85) continue;
            best = heading;
            bot.mw4_path_cramped = true;
            best_fraction = fraction;
            break;
        }
    }
    if (!isdefined(best))
    {
        // A stop expires after one tick; the next tick probes all alternatives again.
        bot.mw4_path_blocked = true;
        bot.mw4_move_clearance = 0;
        return wanted;
    }
    bot.mw4_move_heading = best;
    bot.mw4_move_clearance = best_fraction;
    bot.mw4_move_heading_until = now + 1800;
    bot.mw4_detour_origin = bot.origin;
    bot.mw4_direct_clear_since = undefined;
    return best;
}
// Short local traversal probes complement collision avoidance; they do not require navmesh nodes.
function traversal_trace(bot,start,finish)
{
    return namespace_3b62da1a6fe93933::function_c0049f23b50b55f0(
        start,finish,bot,namespace_3b62da1a6fe93933::function_277bf0cd461a0ac3(1),false);
}

function traversal_ground(bot,point)
{
    if (!isdefined(bot) || !isdefined(point)) return undefined;
    ray_start = point + (0,0,80);
    ray_end = point - (0,0,64);
    hit = traversal_trace(bot,ray_start,ray_end);
    if (!isdefined(hit) || !isdefined(hit["fraction"]) || hit["fraction"] >= 0.99) return undefined;
    position = hit["shape_position"];
    normal = hit["contact_normal"];
    if (!isdefined(position)) position = hit["position"];
    if (!isdefined(normal)) normal = hit["normal"];
    if (!isdefined(position) || !isdefined(normal) || normal[2] < 0.65) return undefined;
    return position;
}

// Stair-only ground query. Start near the previous floor instead of tracing
// down from above roofs. The native wrapper returns raw physics hit fields.
function stair_ground(bot,point)
{
    if (!isdefined(bot) || !isdefined(point)) return undefined;
    ray_start = point + (0,0,32);
    ray_end = point - (0,0,48);
    hit = traversal_trace(bot,ray_start,ray_end);
    if (!isdefined(hit) || !isdefined(hit["fraction"]) || hit["fraction"] >= 0.99) return undefined;
    position = hit["shape_position"];
    normal = hit["contact_normal"];
    if (!isdefined(position)) position = hit["position"];
    if (!isdefined(normal)) normal = hit["normal"];
    if (!isdefined(position) || !isdefined(normal)) return undefined;
    if (normal[2] < 0.65) return undefined;
    return position;
}

function stair_profile(bot,yaw)
{
    if (!move_alive(bot) || !isdefined(yaw)) return false;
    origin = bot.origin;
    forward = AnglesToForward((0,yaw,0));
    side = AnglesToForward((0,yaw + 90,0));
    if (!isdefined(forward) || !isdefined(side)) return false;
    base = stair_ground(bot,origin);
    if (!isdefined(base)) return false;
    previous = base;
    distances = [12,24,36,48,60,72,84,96];
    offsets = [-14,14];
    for (sample = 0; sample < distances.size; sample++)
    {
        distance = distances[sample];
        displacement = forward * distance;
        point = origin + displacement;
        // Preserve XY sampling while following rising/descending floor height.
        point = (point[0],point[1],previous[2]);
        floor = stair_ground(bot,point);
        if (!isdefined(floor)) return false;
        rise = floor[2] - previous[2];
        if (rise > 20 || rise < (0 - 20)) return false;
        for (edge = 0; edge < offsets.size; edge++)
        {
            width = offsets[edge];
            body_offset = side * width;
            body_start = previous + (0,0,52);
            body_start = body_start + body_offset;
            body_end = floor + (0,0,52);
            body_end = body_end + body_offset;
            trace = traversal_trace(bot,body_start,body_end);
            if (!isdefined(trace) || !isdefined(trace["fraction"]) || trace["fraction"] < 0.97) return false;
        }
        head_start = previous + (0,0,72);
        head_end = floor + (0,0,72);
        trace = traversal_trace(bot,head_start,head_end);
        if (!isdefined(trace) || !isdefined(trace["fraction"]) || trace["fraction"] < 0.97) return false;
        previous = floor;
    }
    total_rise = previous[2] - base[2];
    return total_rise > 2 || total_rise < (0 - 2);
}

function try_route_door(bot,yaw,now)
{
    if (isdefined(bot.mw4_next_door_check) && now < bot.mw4_next_door_check) return false;
    bot.mw4_next_door_check = now + 800;
    // Same entity query, state predicate and open callback as native bot_think_dynamic_doors.
    doors = function_8f5d374c2e4c65b9("dynamic_door",#targetname,bot.origin,80);
    if (!isdefined(doors)) doors = [];
    for (d = 0; d < doors.size; d++)
    {
        candidate = doors[d];
        if (!isdefined(candidate) || !isdefined(candidate.origin) || !isdefined(candidate.state)
            || !isdefined(candidate.var_69109c5b1f28b53b)) continue;
        delta = route_angle_delta(VectorToAngles(candidate.origin - bot.origin)[1] - yaw);
        if (delta > 65 || delta < (0 - 65)) continue;
        if (!candidate [[ &door::function_6e13b9f909ebf9db ]]()) continue;
        if (isdefined(candidate.mw4_open_request_until) && now < candidate.mw4_open_request_until) continue;
        candidate.mw4_open_request_until = now + 1500;
        candidate thread [[ &door::function_cdb05a5dd922281d ]](bot);
        bot.mw4_traverse_heading = yaw;
        bot.mw4_traverse_until = now + 700;
        bot.mw4_traverse_speed = 0;
        bot.mw4_move_heading_until = 0;
        return true;
    }
    // v1.2: no native door "use" press (it closed doors that stock had just opened; see the header).
    return false;
}

// Wider search runs infrequently; each accepted opening is rechecked on approach.
function traverse_environment(bot,yaw,now)
{
    if (isdefined(bot.mw4_traverse_until) && now < bot.mw4_traverse_until)
    {
        bot BotClearButton("sprint");
        bot.mw4_sprint_active = false;
        bot.mw4_sprint_since = undefined;
        bot BotSetScriptMove(bot.mw4_traverse_heading,0.3,bot.mw4_traverse_speed);
        look = bot.origin + AnglesToForward((0,bot.mw4_traverse_heading,0)) * 128 + (0,0,56);
        bot [[ &bots_util::function_26196082e7a55bbd ]](look,0.25);
        return true;
    }
    if (isdefined(bot.mw4_next_traverse_probe) && now < bot.mw4_next_traverse_probe) return false;
    bot.mw4_next_traverse_probe = now + 400 + (bot.mw4_style_id % 3) * 50;
    low = move_clearance(bot,yaw,20,96);
    if (!isdefined(low)) return false;
    if (low > 0.9) return false;
    if (try_route_door(bot,yaw,now))
    {
        bot BotClearButton("sprint");
        bot.mw4_sprint_active = false;
        bot BotSetScriptMove(yaw,0.3,0);
        return true;
    }
    step_clear = stair_profile(bot,yaw);
    
    if (step_clear)
    {
        
        bot BotClearButton("sprint");
        bot.mw4_sprint_active = false;
        bot.mw4_sprint_since = undefined;
        bot BotSetScriptMove(yaw,0.3,0.65);
        look = bot.origin + AnglesToForward((0,yaw,0)) * 128 + (0,0,72);
        bot [[ &bots_util::function_26196082e7a55bbd ]](look,0.25);
        // No timed blind stair command: recheck floor and headroom on the next tick.
        bot.mw4_next_traverse_probe = now;
        bot.mw4_move_heading_until = 0;
        return true;
    }
    // Ordinary wall avoidance takes over; there are no window detours or jumps here.
    return false;
}

// Smooth only the requested heading; an unsafe arc falls back to the checked heading.
function smooth_move_heading(bot,heading,now)
{
    if (!isdefined(bot.mw4_smooth_heading) || !isdefined(bot.mw4_smooth_heading_time)
        || now - bot.mw4_smooth_heading_time > 800)
    {
        bot.mw4_smooth_heading = heading;
        bot.mw4_smooth_heading_time = now;
        return heading;
    }
    delta = route_angle_delta(heading - bot.mw4_smooth_heading);
    limit = (now - bot.mw4_smooth_heading_time) * 0.14;
    if (limit > 42) limit = 42;
    if (limit < 7) limit = 7;
    step = delta;
    if (step > limit) step = limit;
    if (step < (0 - limit)) step = 0 - limit;
    candidate = bot.mw4_smooth_heading + step;
    if (step != delta)
    {
        clearance = path_clearance(bot,candidate,96);
        if (!isdefined(clearance) || clearance < 0.9) candidate = heading;
    }
    bot.mw4_smooth_heading = candidate;
    bot.mw4_smooth_heading_time = now;
    return candidate;
}

function smooth_look(bot,target,now,amount)
{
    if (!isdefined(bot.mw4_look_point) || !isdefined(bot.mw4_look_time)
        || now - bot.mw4_look_time > 800)
    {
        bot.mw4_look_point = target;
    }
    else
    {
        // Translate the previous look point with the bot before blending its direction.
        previous = bot.mw4_look_point + (bot.origin - bot.mw4_look_origin);
        bot.mw4_look_point = previous + (target - previous) * amount;
    }
    bot.mw4_look_origin = bot.origin;
    bot.mw4_look_time = now;
    return bot.mw4_look_point;
}

function smooth_move_speed(bot,speed)
{
    if (!isdefined(bot.mw4_smooth_speed)) bot.mw4_smooth_speed = 0.55;
    change = speed - bot.mw4_smooth_speed;
    if (change > 0.15) change = 0.15;
    if (change < (0 - 0.25)) change = 0 - 0.25;
    bot.mw4_smooth_speed += change;
    return bot.mw4_smooth_speed;
}

function movement_controller()
{

    for (;;)
    {
        wait 0.2;
        if (isdefined(game["state"]) && game["state"] == "postgame") return;
        if (!isdefined(level.var_10f4ff41c4b7f0ac)) continue;
        now = GetTime();
        for (i = 0; i < level.var_10f4ff41c4b7f0ac.size; i++)
        {
            bot = level.var_10f4ff41c4b7f0ac[i];
            if (!isdefined(bot) || !isdefined(bot.var_3215388132e3d9b5)) continue;
            if (!move_alive(bot))
            {
                bot.mw4_combat_active_until = undefined;
                bot.mw4_focus_enemy = undefined;
                bot.mw4_last_contact = undefined;
                bot.mw4_reload_until = undefined;
                bot.mw4_reposition_until = undefined;
                bot.mw4_burst_until = 0;
                bot.mw4_fire_again = 0;
                bot.mw4_route_anchor = undefined;
                bot.mw4_route_phase = undefined;
                bot.mw4_move_target_until = 0;
                bot.mw4_move_heading_until = 0;
                bot.mw4_move_progress_time = undefined;
                bot.mw4_sprint_since = undefined;
                bot.mw4_slide_sample_time = undefined;
                bot.mw4_slide_moving_until = 0;
                bot.mw4_smooth_heading = undefined;
                bot.mw4_smooth_speed = undefined;
                bot.mw4_look_point = undefined;
                bot.mw4_nav_target = undefined;
                bot.mw4_tactical_hurt = undefined;
                bot.mw4_withdraw_until = undefined;
                bot.mw4_withdraw_retry = undefined;
                bot.mw4_maneuver_until = undefined;
                bot.mw4_maneuver_kind = undefined;
                bot.mw4_maneuver_enemy = undefined;
                bot.mw4_detour_origin = undefined;
                bot.mw4_direct_clear_since = undefined;
                continue;
            }
            if (!isdefined(bot.team)) continue;
            combat_profile(bot);
            assign_route_role(bot);
            if (isdefined(bot.mw4_reposition_until) && now < bot.mw4_reposition_until) continue;
            // Combat remains separate; abandon the flank waypoint after contact.
            if (isdefined(bot.mw4_combat_active_until) && now < bot.mw4_combat_active_until)
            {
                bot.mw4_move_progress_time = now;
                bot.mw4_move_progress_origin = bot.origin;
                bot.mw4_route_phase = 2;
                continue;
            }
            target = movement_target(bot,now);
            if (!isdefined(target)) continue;
            range_sq = DistanceSquared(bot.origin,target.origin);
            height_delta = target.origin[2] - bot.origin[2];
            // Nearby enemies behind walls must not stop navigation to an opening.
            if (range_sq < 65536 && height_delta < 48 && height_delta > (0 - 48)
                && isdefined(bot.Enemy) && bot.Enemy == target
                && isdefined(bot.var_19572a6dcd79331d) && bot.var_19572a6dcd79331d > 0
                && now - bot.var_19572a6dcd79331d <= 250) continue;
            route_point = route_goal(bot,target,now);
            wanted = VectorToAngles(route_point - bot.origin)[1];
            if (!isdefined(bot.mw4_move_progress_time))
            {
                bot.mw4_move_progress_time = now;
                bot.mw4_move_progress_origin = bot.origin;
            }
            if (now - bot.mw4_move_progress_time >= 1200)
            {
                if (DistanceSquared(bot.origin,bot.mw4_move_progress_origin) < 400)
                {
                    bot.mw4_stuck_until = now + 1000;
                    bot.mw4_escape_heading = wanted + 100;
                    if (bot.mw4_route_side < 0) bot.mw4_escape_heading = wanted - 100;
                    bot.mw4_move_heading_until = 0;
                }
                bot.mw4_move_progress_origin = bot.origin;
                bot.mw4_move_progress_time = now;
            }
            bot.mw4_path_cramped = false;
            if (traverse_environment(bot,wanted,now)) continue;
            heading = movement_heading(bot,wanted,now);
            if (bot.mw4_path_blocked)
            {
                bot BotClearButton("sprint");
                bot.mw4_sprint_active = false;
                bot.mw4_sprint_since = undefined;
                bot.mw4_smooth_speed = 0;
                bot BotSetScriptMove(wanted,0.2,0);
                
                continue;
            }
            heading = smooth_move_heading(bot,heading,now);
            heading = movement_actions(bot,heading,wanted,range_sq,now);
            // Actions cannot replace a checked heading with an unchecked wall-facing jump.
            final_clearance = path_clearance(bot,heading,96);
            if (isdefined(final_clearance) && final_clearance < 0.8)
            {
                bot.mw4_jump_until = 0;
                bot.mw4_move_heading_until = 0;
                bot BotClearButton("sprint");
                bot.mw4_sprint_active = false;
                bot.mw4_smooth_speed = 0;
                bot BotSetScriptMove(heading,0.2,0);
                continue;
            }
            if (bot.mw4_path_cramped)
            {
                bot BotClearButton("sprint");
                bot.mw4_sprint_active = false;
                bot.mw4_move_speed = 0.3;
                bot.mw4_move_action = "clear_corner";
            }
            // Every command expires after 0.3 seconds. No persistent zero-speed overrides.
            bot.mw4_move_speed = smooth_move_speed(bot,bot.mw4_move_speed);
            bot BotSetScriptMove(heading,0.3,bot.mw4_move_speed);
            look_point = bot.origin + AnglesToForward((0,heading,0)) * 128 + (0,0,48);
            look_point = smooth_look(bot,look_point,now,0.5);
            bot [[ &bots_util::function_26196082e7a55bbd ]](look_point,0.3);
            
        }
    }
}

// Verified native BotPressButton inputs; finite holds, no new movement controller.
function update_ads(bot,now)
{
    desired = false;
    if (move_alive(bot) && isdefined(bot.Enemy) && move_enemy(bot,bot.Enemy)
        && isdefined(bot.var_19572a6dcd79331d) && bot.var_19572a6dcd79331d > 0
        && now - bot.var_19572a6dcd79331d <= 250
        && (!isdefined(bot.mw4_reload_until) || now >= bot.mw4_reload_until)
        && (!isdefined(bot.mw4_jump_until) || now >= bot.mw4_jump_until)
        && (!isdefined(bot.mw4_sprint_active) || !bot.mw4_sprint_active))
    {
        range_sq = DistanceSquared(bot.origin,bot.Enemy.origin);
        threshold = 102400;
        // Hysteresis: enter beyond320 units, leave below256 units.
        if (isdefined(bot.mw4_ads_active) && bot.mw4_ads_active) threshold = 65536;
        desired = range_sq >= threshold;
    }
    if (desired)
    {
        bot BotPressButton("ads",0.35);
        
        bot.mw4_ads_active = true;
    }
    else if (isdefined(bot.mw4_ads_active) && bot.mw4_ads_active)
    {
        bot BotClearButton("ads");
        bot.mw4_ads_active = false;
    }
}

function consider_slide(bot,heading,wanted,range_sq,now)
{
    // Confirm actual movement, rather than relying on a sprint request alone.
    if (!isdefined(bot.mw4_slide_sample_time))
    {
        bot.mw4_slide_sample_time = now;
        bot.mw4_slide_sample_origin = bot.origin;
        bot.mw4_slide_moving_until = 0;
    }
    if (now - bot.mw4_slide_sample_time >= 400)
    {
        moved = DistanceSquared(bot.origin,bot.mw4_slide_sample_origin);
        bot.mw4_slide_moving_until = 0;
        if (moved >= 1600 && now - bot.mw4_slide_sample_time <= 800)
            bot.mw4_slide_moving_until = now + 450;
        bot.mw4_slide_sample_time = now;
        bot.mw4_slide_sample_origin = bot.origin;
    }
    // Verify the previous request with the native IsSprintSliding predicate.
    
    if (!isdefined(bot.mw4_sprint_since) || now - bot.mw4_sprint_since < 1200
        || now >= bot.mw4_slide_moving_until || bot.mw4_path_cramped
        || (isdefined(bot.mw4_stuck_until) && now < bot.mw4_stuck_until)
        || (isdefined(bot.mw4_jump_until) && now < bot.mw4_jump_until)
        || (isdefined(bot.mw4_ads_active) && bot.mw4_ads_active)
        || (isdefined(bot.mw4_reload_until) && now < bot.mw4_reload_until)) return;
    if (range_sq < 65536 || range_sq > 1048576 || bot.mw4_route_phase != 2) return;
    if (!isdefined(bot.var_19572a6dcd79331d) || bot.var_19572a6dcd79331d <= 0
        || now - bot.var_19572a6dcd79331d <= 250 || now - bot.var_19572a6dcd79331d > 1800) return;
    if (isdefined(bot.mw4_last_slide) && now - bot.mw4_last_slide < 12000 + (bot.mw4_style_id % 3) * 2000) return;
    turn = route_angle_delta(heading - wanted);
    if (turn > 20 || turn < (0 - 20)) return;
    clearance = path_clearance(bot,heading,192);
    if (!isdefined(clearance) || clearance < 0.97) return;
    floor = stair_ground(bot,bot.origin);
    next_floor = stair_ground(bot,bot.origin + AnglesToForward((0,heading,0)) * 128);
    if (!isdefined(floor) || !isdefined(next_floor)) return;
    rise = next_floor[2] - floor[2];
    if (rise > 8 || rise < (0 - 8)) return;
    bot BotPressButton("slide",0.25);
    bot.mw4_last_slide = now;
    bot.mw4_move_action = "slide";

}

function movement_actions(bot,heading,wanted,range_sq,now)
{
    bot.mw4_move_speed = 0.55;
    bot.mw4_move_action = "run";
    stuck = isdefined(bot.mw4_stuck_until) && now < bot.mw4_stuck_until;
    free_path = isdefined(bot.mw4_move_clearance) && bot.mw4_move_clearance > 0.9;
    turn = route_angle_delta(heading - wanted);
    sprint = free_path && !bot.mw4_path_cramped
        && (!isdefined(bot.mw4_reload_until) || now >= bot.mw4_reload_until);
    if (sprint)
    {
        if (!isdefined(bot.mw4_sprint_since)) bot.mw4_sprint_since = now;
        bot BotPressButton("sprint",0.35);
        bot.mw4_sprint_active = true;
        bot.mw4_move_speed = 1;
        bot.mw4_move_action = "sprint";
        consider_slide(bot,heading,wanted,range_sq,now);
    }
    else if (isdefined(bot.mw4_sprint_active) && bot.mw4_sprint_active)
    {
        bot BotClearButton("sprint");
        bot.mw4_sprint_active = false;
        bot.mw4_sprint_since = undefined;
    }
    // Detect a low blockage in front with space above it; do not jump into a tall wall.
    if (stuck && isdefined(bot.mw4_forward_clearance) && bot.mw4_forward_clearance < 0.85
        && (!isdefined(bot.mw4_last_jump) || now - bot.mw4_last_jump > 5000))
    {
        upper_clearance = move_clearance(bot,wanted,80);
        if (isdefined(upper_clearance) && upper_clearance > 0.95)
        {
            bot BotPressButton("jump",0.1);
            bot.mw4_last_jump = now;
            bot.mw4_jump_until = now + 450;
            bot.mw4_jump_heading = wanted;
        }
    }
    if (isdefined(bot.mw4_jump_until) && now < bot.mw4_jump_until)
    {
        // Keep the collision-checked heading while jumping.
        bot.mw4_move_speed = 0.8;
        bot.mw4_move_action = "jump";
    }
    return heading;
}

function route_angle_delta(value)
{
    while (value > 180) value -= 360;
    while (value < (0 - 180)) value += 360;
    return value;
}

function assign_route_role(bot)
{
    if (isdefined(bot.mw4_route_role)) return;
    if (!isdefined(level.mw4_team_roles)) level.mw4_team_roles = [];
    team = bot.team;
    if (!isdefined(level.mw4_team_roles[team])) level.mw4_team_roles[team] = 0;
    role = level.mw4_team_roles[team] % 3;
    level.mw4_team_roles[team]++;
    bot.mw4_route_side = 0;
    bot.mw4_route_role = "direct";
    if (role == 1)
    {
        bot.mw4_route_side = -1;
        bot.mw4_route_role = "left_flank";
    }
    if (role == 2)
    {
        bot.mw4_route_side = 1;
        bot.mw4_route_role = "right_flank";
    }

}

function route_goal(bot,target,now)
{
    seen = isdefined(bot.Enemy) && bot.Enemy == target
        && isdefined(bot.var_19572a6dcd79331d) && bot.var_19572a6dcd79331d > 0
        && now - bot.var_19572a6dcd79331d <= 250;
    // Hold one destination; obstacle avoidance supplies the local detour.
    // Artificial lateral waypoints could be inside walls or outside the walkway.
    if (!isdefined(bot.mw4_nav_target) || bot.mw4_nav_target != target
        || !isdefined(bot.mw4_nav_point) || !isdefined(bot.mw4_nav_until)
        || now >= bot.mw4_nav_until || seen)
    {
        bot.mw4_nav_target = target;
        bot.mw4_nav_point = target.origin;
        bot.mw4_nav_until = now + 6000;
    }
    bot.mw4_route_phase = 2;
    return bot.mw4_nav_point;
}

function crowd_penalty(bot,yaw)
{
    if (bot.team == "free") return 0;
    future = bot.origin + AnglesToForward((0,yaw,0)) * 96;
    penalty = 0;
    for (c = 0; c < level.var_10f4ff41c4b7f0ac.size; c++)
    {
        ally = level.var_10f4ff41c4b7f0ac[c];
        if (!move_alive(ally) || ally == bot || !isdefined(ally.team) || ally.team != bot.team) continue;
        if (DistanceSquared(bot.origin,ally.origin) > 65536) continue;
        separation = DistanceSquared(future,ally.origin);
        if (separation < 16384) penalty += (1 - separation / 16384) * 60;
    }
    return penalty;
}

function combat_profile(bot)
{
    if (isdefined(bot.mw4_style_id)) return;
    if (!isdefined(level.mw4_style_counter)) level.mw4_style_counter = 0;
    bot.mw4_style_id = level.mw4_style_counter;
    level.mw4_style_counter++;
    bot.mw4_step_side = 1;
    if (bot.mw4_style_id % 2 == 0) bot.mw4_step_side = -1;
    bot.mw4_next_step = GetTime() + 900 + bot.mw4_style_id * 170;
}

function combat_fire(bot,enemy,now)
{
    if (isdefined(bot.mw4_reload_until) && now < bot.mw4_reload_until)
    {
        bot BotClearButton("attack");
        return;
    }
    if (now < bot.mw4_reaction_until) return;
    if (now < bot.mw4_burst_until)
    {
        bot BotPressButton("attack",0.2);
        return;
    }
    bot BotClearButton("attack");
    if (now < bot.mw4_fire_again) return;
    range_sq = DistanceSquared(bot.origin,enemy.origin);
    duration = 650 + (bot.mw4_style_id % 3) * 100;
    pause = 230 + (bot.mw4_style_id % 2) * 90;
    if (range_sq > 589824)
    {
        duration = 350 + (bot.mw4_style_id % 3) * 60;
        pause = 300 + (bot.mw4_style_id % 2) * 100;
    }
    bot.mw4_burst_until = now + duration;
    bot.mw4_fire_again = now + duration + pause;
    bot BotPressButton("attack",0.2);
}

// Separate from the aim/fire thread: optional ammo/position logic cannot gate its initialization.
function combat_behavior()
{

    for (;;)
    {
        wait 0.3;
        if (isdefined(game["state"]) && game["state"] == "postgame") return;
        if (!isdefined(level.var_10f4ff41c4b7f0ac)) continue;
        now = GetTime();
        for (b = 0; b < level.var_10f4ff41c4b7f0ac.size; b++)
        {
            bot = level.var_10f4ff41c4b7f0ac[b];
            if (!move_alive(bot) || !isdefined(bot.var_3215388132e3d9b5)) continue;
            combat_profile(bot);
            if (!isdefined(bot.mw4_ammo_check) || now >= bot.mw4_ammo_check)
            {
                bot.mw4_ammo_check = now + 1000;
                // builtin method results into bot fields (local stores would be lost)
                bot.mw4_ammo_w = bot GetCurrentWeapon();
                if (isdefined(bot.mw4_ammo_w))
                {
                    bot.mw4_ammo_clip = bot GetWeaponAmmoClip(bot.mw4_ammo_w);
                    bot.mw4_ammo_res = bot GetWeaponAmmoStock(bot.mw4_ammo_w);
                    if (isdefined(bot.mw4_ammo_clip) && isdefined(bot.mw4_ammo_res) && bot.mw4_ammo_clip == 0 && bot.mw4_ammo_res > 0)
                    {
                        // sprint cancels a reload: keep sprint/fire blocked while the clip is empty
                        bot.mw4_reload_until = now + 1500;
                        bot.mw4_sprint_active = false;
                        bot.mw4_sprint_since = undefined;
                        if (!isdefined(bot.mw4_reload_pressed) || now - bot.mw4_reload_pressed >= 6000)
                        {
                            bot.mw4_reload_pressed = now;
                            bot thread press_reload();
                        }
                    }
                    if (isdefined(bot.mw4_ammo_clip) && bot.mw4_ammo_clip > 0) bot.mw4_reload_until = undefined;
                }
            }
            if (!isdefined(bot.mw4_focus_enemy) || !move_enemy(bot,bot.mw4_focus_enemy)) continue;
            if (!isdefined(bot.mw4_last_contact) || now - bot.mw4_last_contact > 600) continue;
            tactical_movement(bot,bot.mw4_focus_enemy,now);
        }
    }
}

// MWIII overhaul ideas adapted to the existing MW4 controls:
// bounded withdrawal with health hysteresis, distance-aware strafing,
// and a committed direction instead of changing sides on every action.
function tactical_withdraw(bot,now)
{
    if (!isdefined(bot.mw4_tactical_hurt)) bot.mw4_tactical_hurt = false;
    // relative to maxhealth (stock 100 -> 35 / 70 as before)
    bot.mw4_withdraw_max = bot.var_bf80442dd2797c82;
    if (!isdefined(bot.mw4_withdraw_max) || bot.mw4_withdraw_max <= 0) bot.mw4_withdraw_max = 100;
    if (bot.var_d2c854047ddd1dbc < bot.mw4_withdraw_max * 0.35) bot.mw4_tactical_hurt = true;
    else if (bot.var_d2c854047ddd1dbc >= bot.mw4_withdraw_max * 0.7) bot.mw4_tactical_hurt = false;
    if (!bot.mw4_tactical_hurt)
    {
        bot.mw4_withdraw_until = 0;
        return false;
    }
    if ((!isdefined(bot.mw4_withdraw_until) || now >= bot.mw4_withdraw_until)
        && (!isdefined(bot.mw4_withdraw_retry) || now >= bot.mw4_withdraw_retry))
    {
        bot.mw4_withdraw_until = now + 2200;
        bot.mw4_withdraw_retry = now + 6000;
    }
    return isdefined(bot.mw4_withdraw_until) && now < bot.mw4_withdraw_until;
}

function tactical_angle(range_sq,withdraw)
{
    if (withdraw) return 150;
    if (range_sq < 62500) return 115;
    if (range_sq > 490000) return 55;
    return 90;
}

function tactical_movement(bot,enemy,now)
{
    withdraw = tactical_withdraw(bot,now);
    if (!withdraw && now < bot.mw4_next_step) return;
    if (isdefined(bot.mw4_reload_until) && now < bot.mw4_reload_until && !withdraw) return;
    kind = "strafe";
    speed = 0.28;
    if (withdraw)
    {
        kind = "withdraw";
        speed = 0.55;
    }
    range_sq = DistanceSquared(bot.origin,enemy.origin);
    if (!isdefined(bot.mw4_maneuver_until) || now >= bot.mw4_maneuver_until
        || !isdefined(bot.mw4_maneuver_kind) || bot.mw4_maneuver_kind != kind
        || !isdefined(bot.mw4_maneuver_enemy) || bot.mw4_maneuver_enemy != enemy)
    {
        yaw = VectorToAngles(enemy.origin - bot.origin)[1];
        bot.mw4_maneuver_heading = yaw + tactical_angle(range_sq,withdraw) * bot.mw4_step_side;
        bot.mw4_maneuver_angle = tactical_angle(range_sq,withdraw);
        bot.mw4_maneuver_yaw = yaw;
        bot.mw4_maneuver_until = now + 1200;
        bot.mw4_maneuver_kind = kind;
        bot.mw4_maneuver_enemy = enemy;
    }
    heading = bot.mw4_maneuver_heading;
    clearance = path_clearance(bot,heading,128);
    if (!isdefined(clearance) || clearance < 0.95 || crowd_penalty(bot,heading) > 40)
    {
        // Choose the other side only when the committed side is obstructed.
        alternate = bot.mw4_maneuver_yaw - bot.mw4_maneuver_angle * bot.mw4_step_side;
        clearance = path_clearance(bot,alternate,128);
        if (!isdefined(clearance) || clearance < 0.95 || crowd_penalty(bot,alternate) > 40)
        {
            bot.mw4_next_step = now + 600;
            return;
        }
        bot.mw4_step_side *= -1;
        heading = alternate;
        bot.mw4_maneuver_heading = heading;
    }
    heading = smooth_move_heading(bot,heading,now);
    clearance = path_clearance(bot,heading,128);
    if (!isdefined(clearance) || clearance < 0.95 || crowd_penalty(bot,heading) > 40)
    {
        bot.mw4_next_step = now + 600;
        return;
    }
    bot BotClearButton("sprint");
    bot BotClearButton("slide");
    bot.mw4_sprint_active = false;
    bot.mw4_sprint_since = undefined;
    speed = smooth_move_speed(bot,speed);
    bot BotSetScriptMove(heading,0.35,speed);
    bot.mw4_reposition_until = now + 350;
    bot.mw4_next_step = now + 1500 + (bot.mw4_style_id % 3) * 350;
}

function skip_dropped_weapon_think()
{
    // This beta's optional pickup loop fails at HasWeapon("throwingknife_mp").
    // Normal equipped weapons, native thinking and custom combat remain active.
    return;
}

function skip_first_person_blood_fx(vfx,stop_event,timeout)
{
    return;
}

// Own thread: stock bot code never presses "reload"; if the engine refused the name only this thread ends.
function press_reload()
{
    self BotClearButton("attack");
    self BotClearButton("sprint");
    self BotPressButton("reload",0.2);
}
