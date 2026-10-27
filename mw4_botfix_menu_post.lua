-- MW4 Botfix v1.2 release build (= Lua menu DEV 40, runtime-tested 2026-10-27; log prefix and quiet console only).
-- MW4 Botfix – Debug Options entries.
-- DEV 26: the Botfix entries become real rows of the stock Debug Options list (own category "BOTFIX"),
-- so scrolling, font, hover look and the details panel on the right come from the game. The debug tab
-- data gets a copied category list (the game's lists stay untouched) and OPTIONS.GetSettingDataFromId
-- answers our string ids with GenericButton settings.
-- DEV 27: DEV 26 showed no rows in game: OPTIONS.GetSettingsTabsData does not exist in this build
-- ("tabs=missing", logged on every widget build). Now the tab data of the built Settings menu itself
-- is extended as well (menu.tabMap / tabsData / data), a one-time diagnostic logs the real names, and
-- if no injection works for a menu the DEV 25 TextButton overlay is built instead (from the same entries).
-- DEV 28: DEV 27 log: the debug tab holds only a bundle reference (xhash) instead of the list; the game
-- loads the list later through OPTIONS.GetSettingListFromId. That function is wrapped now: for the debug
-- tab's bundle it returns a copy with our category. The overlay only appears if that list is never served.
-- DEV 29: DEV 28 served the list, then the menu UI crashed in a C __index ("Frame.RunFrame callback error")
-- and restarted: the sub tab copy carried the game object's metatable, whose C accessor cannot read a
-- plain Lua table. The copy now keeps its own fields and reads anything else from the original object.
-- DEV 30: DEV 29 served the list without a crash, but the Debug tab still showed only the stock rows and
-- no row data of ours was requested. Same logic plus a trace of how the game asks for the list and rows
-- (GetSettingListFromId calls, CreateOptionFromId / GetAvailableSettingDataFromId ids) to find the path.
-- DEV 31: DEV 30 trace: the list served by GetSettingListFromId is not what the grid draws (0 requests of
-- our ids, 35 other rows requested; on the second open no list call at all). Engine.GetScriptBundle is
-- wrapped too: for the debug tab's bundle it returns a stand-in whose list has our category (all other
-- fields read from the real bundle). The trace now shows the first row ids requested after the menu opens.
-- DEV 32: DEV 31: bundle calls=0, still 0 requests of our ids at GetSettingDataFromId although the grid
-- calls OPTIONS.GetAvailableSettingDataFromId for every row. That function apparently reaches the data
-- function without going through the OPTIONS table, so our ids got no data and were dropped. Our ids are
-- now answered directly in GetAvailableSettingDataFromId (string ids and their xhash), and every
-- non-xhash id there is traced.
-- DEV 33: DEV 32 in game: the BOTFIX header appears (our entries count as available, 16 requests per
-- open) but no rows are built (no "row built"). The game's own setting data are auto-xhash tables
-- (fields under hashed keys); ours had plain string keys only, and the type value was forced to a string.
-- Every data field is now stored under its name and its xhash, and OptionType values are used as the
-- game defines them (string or xhash). Diagnostic: the field layout of one stock row's data and of ours
-- is logged once ("data layout ...") for comparison.
-- DEV 34: DEV 33 works in game (8 native rows). Target, class, allow, fixed weapon, skin and replacement
-- bots are now dropdown rows like the game's own (OptionType.DROPDOWN with labels, value(), action(element,
-- controller, index), defaultOptionValue()); test and status stay buttons. Without a dropdown type in
-- OPTIONS.OptionType the entries stay cycling buttons. Values sent to GSC are shown until GSC publishes
-- them in its dvars (reset with every Settings menu).
-- DEV 35: settings page instead of test rows (Henrik 2026-10-17). Two categories, BOTFIX: SPIELER
-- (Advanced UAV, my health, unlimited ammo, move speed, my skin) and BOTFIX: BOTS (difficulty, health,
-- freeze, class, allow, fixed weapon, replacement bots). New settings use cmd 6-12 of the GSC receiver
-- mw4_botfix_menu DEV 23, which keeps each value in a dvar (mw4_botfix_auav/_hp/_ammo/_speed/_bdiff/
-- _bhp/_freeze). Test connection, bot status and target are gone.
-- DEV 36: everything the player sees is English (Henrik 2026-10-17): row titles, choices, descriptions.
-- DEV 37: DEV 36 log: this build calls a dropdown action as action(controller, index) (args number, number,
-- nil), not action(element, controller, index) like the decompiled reference, so every pick failed with
-- "no valid choice nil" and the box jumped back. The index is now taken from either call form.
-- DEV 38 (Henrik 2026-10-24/25): new rows Headshots Only (cmd 13), Bot Respawn Delay (14), Bot Names (22,
-- names list from rex\Assets\Lua\mw4_botfix_names_post.lua sent with cmd 23-25 + payload values), and a
-- third category BOTFIX: BOT SKINS (cmd 15-21: mode, skin per team, pool allow/block, skin per single bot).
-- My Skin offers Skin 1..15 until GSC has published the pool size. Weapon rows: living bots switch at once
-- (menu GSC DEV 25).
-- DEV 39: name payload values below 2^24 (10000000 + 3 chars of 6 bits): only values up to ~9.3 million are
-- proven to arrive unchanged; if the engine passes the value on as a 32-bit float, larger ones lose digits.
-- DEV 40 (Henrik 2026-10-26, menu GSC DEV 28): Reset All Settings (cmd 30), Friendly / Enemy Bot Difficulty
-- (cmd 10 / 27) and Bot Health (cmd 11 / 28), Bot Unlimited Ammo (cmd 29), Bot Weapon Class starts at Assault
-- Rifles, descriptions say "Works only during a match." in the main menu, and a one-line probe of what this
-- Lua can store (io/os, Engine/Dvar setters) for saving the settings over a game restart.
-- Bootstrap filename must end with _post.lua in this Rex build.
local VERSION=40
local function read(t,k)
    if not t then return nil end
    local v=t[k]
    if v~=nil then return v end
    if type(xhash)=='function' then return t[xhash(k)] end
end
-- Also tries the lower-case hash (the game hashes lower-case names).
local function readAny(t,k)
    local v=read(t,k)
    if v==nil and t and type(xhash)=='function' then
        local success,value=pcall(function() return t[xhash(string.lower(k))] end)
        if success then v=value end
    end
    return v
end
local function write(t,k,v)
    if t[k]~=nil or type(xhash)~='function' then t[k]=v else t[xhash(k)]=v end
end
-- Release build: diagnostic lines stay out of the console; anything about a failure is always printed.
local QUIET=true
local DIAG={'diag ','trace ','data layout','probe ','keys:','dynamic grid','debug tab ','menu data:','row data hook',
    'data hooks','row built','data request','weapon name','category:','list served','bundle served','overlay:',
    'native BOTFIX rows','dropdown type','dropdown action args','choice ','row type','caption:'}
local function quiet(s)
    if not QUIET then return false end
    if string.find(s,'fail',1,true) or string.find(s,'error',1,true) then return false end
    for _,p in ipairs(DIAG) do if string.sub(s,1,#p)==p then return true end end
    return false
end
local function log(s)
    if quiet(s) then return end
    local fn=read(CLUA,'Log') or DebugPrint or print
    if type(fn)=='function' then fn('MW4 Botfix v1.2 menu: '..s) end
end
local logged={}
local function logOnce(key,s) if not logged[key] then logged[key]=true;log(s) end end
local unpackArgs=unpack or table.unpack
local function pack(...) return {n=select('#',...),...} end
local function call(object,key,...)
    local fn=object and read(object,key)
    if type(fn)~='function' then return false end
    return (pcall(fn,object,...))
end
local function invoke(object,key,...)
    local fn=read(object,key)
    assert(type(fn)=='function','Missing native method '..key)
    return fn(object,...)
end
log('file entered')
pcall(function()
    local parts={}
    local function kind(t,k)
        local ok,v=pcall(function() return read(t,k) end)
        if not ok then return 'error' end
        return type(v)
    end
    local io_=rawget(_G,'io')
    local os_=rawget(_G,'os')
    parts[#parts+1]='io='..type(io_)..' io.open='..(type(io_)=='table' and type(rawget(io_,'open')) or '-')
    parts[#parts+1]='os='..type(os_)..' os.getenv='..(type(os_)=='table' and type(rawget(os_,'getenv')) or '-')
    for _,name in ipairs({'SetDvarString','SetDvarInt','SetDvarBool','ExecNow','Exec','SetProfileData','GetProfileData',
        'SetPlayerData','GetPlayerData','SetLocalProfileData','GetLocalProfileData'}) do
        parts[#parts+1]='Engine.'..name..'='..kind(rawget(_G,'Engine'),name)
    end
    for _,name in ipairs({'SetDvarString','SetDvarInt','SetDvarBool','GetDvarString'}) do
        parts[#parts+1]='Dvar.'..name..'='..kind(rawget(_G,'Dvar'),name)
    end
    log('probe storage: '..table.concat(parts,' '))
end)
local ok,err=pcall(function()
    local builder=read(_G,'MenuBuilder')
    assert(builder and type(read(builder,'BuildRegisteredType'))=='function','MenuBuilder unavailable')
    local runtime=rawget(_G,'MW4BotfixMenuRuntime')
    local currentBuild=read(builder,'BuildRegisteredType')
    if runtime and runtime.hook==currentBuild and runtime.version==VERSION then log('already installed; hook verified'); return end
    if runtime then runtime.complete=false end
    -- Never wrap our own (or an older menu build's) hook: start from the build it wrapped.
    local originalBuild=currentBuild
    if runtime and runtime.hook==currentBuild and runtime.originalBuild then originalBuild=runtime.originalBuild end
    local legacy=rawget(_G,'MW4BotfixDebugButtonsRuntime')
    if legacy and legacy.hook==currentBuild and legacy.originalBuild then originalBuild=legacy.originalBuild end
    if runtime or legacy then log('reinstalling after reload') end
    local RT=runtime or {}
    RT.wrappers=RT.wrappers or setmetatable({},{__mode='k'})
    RT.active=RT.active or {}
    RT.ourLists=RT.ourLists or setmetatable({},{__mode='k'})
    local TOKEN={}   -- this file instance; data hooks of an older instance are re-wrapped

    -- DEV 20: one carrier, NotifyServer("splash_shown", value) (runtime-confirmed in DEV 19);
    -- custom names and dvar mailboxes never reach GSC. Values 9170000 + cmd*1000 + arg:
    --   1 bot class mask, 2 bot fixed weapon, 3 my skin, 4 log dump,
    --   5 replacement bots: 100 Auto, 0 off, 1..99 count (-> mw4_bot_fallback),
    --   6 Advanced UAV (0 off, 2 on), 7 my health, 8 unlimited ammo, 9 move speed,
    --   10 bot difficulty, 11 bot health, 12 freeze bots (index values, see DEFS).
    -- GSC publishes the current settings in dvars, which Lua reads for the labels.
    -- Same order as lr_groups() in GSC: bit i-1 of mw4_botfix_allow.
    local CLASSES={{'weapon_assault','Assault Rifles'},{'weapon_smg','SMGs'},{'weapon_battle','Battle Rifles'},
        {'weapon_dmr','DMRs'},{'weapon_lmg','LMGs'},{'weapon_sniper','Sniper Rifles'},{'weapon_shotgun','Shotguns'}}
    -- Menu-local choices (reset for every new Settings menu, as the DEV 25 buttons did).
    local classIndex=1   -- DEV 40: Assault Rifles (Shotguns are blocked by default, so Blocked did nothing)
    local function dvarInt(name,default)
        local fn=read(read(_G,'Dvar'),'GetDvarInt')
        if type(fn)~='function' or type(xhashdvar)~='function' then return default end
        local success,value=pcall(fn,xhashdvar(name),default)
        if success and type(value)=='number' then return value end
        return default
    end
    local function dvarString(name,default)
        local fn=read(read(_G,'Dvar'),'GetDvarString')
        if type(fn)~='function' or type(xhashdvar)~='function' then return default end
        local success,value=pcall(fn,xhashdvar(name))
        if success and type(value)=='string' and value~='' then return value end
        return default
    end
    -- Values sent to GSC, shown until GSC publishes a new value in that dvar (reset with every
    -- Settings menu, so a value GSC never applied is not shown forever).
    local pending={}
    local function liveInt(name,default)
        local value=dvarInt(name,default)
        local wanted=pending[name]
        if wanted==nil then return value end
        if value~=wanted.before then pending[name]=nil;return value end
        return wanted.value
    end
    local function expect(name,value,default)
        pending[name]={value=value,before=dvarInt(name,default)}
    end
    -- The same for string dvars (DEV 38: per-slot bot skin codes).
    local pendingText={}
    local function liveText(name,default)
        local value=dvarString(name,default)
        local wanted=pendingText[name]
        if wanted==nil then return value end
        if value~=wanted.before then pendingText[name]=nil;return value end
        return wanted.value
    end
    local function expectText(name,value,default)
        pendingText[name]={value=value,before=dvarString(name,default)}
    end
    -- Comma list -> table; empty entries are kept ("a,,c" -> {'a','','c'}).
    local function splitList(text)
        local out={}
        if text==nil or text=='' then return out end
        local start=1
        while true do
            local stop=string.find(text,',',start,true)
            if not stop then out[#out+1]=string.sub(text,start);break end
            out[#out+1]=string.sub(text,start,stop-1)
            start=stop+1
        end
        return out
    end
    local function notify(value,what,quiet)
        local fn=read(read(_G,'Engine'),'NotifyServer')
        assert(type(fn)=='function','Engine.NotifyServer unavailable')
        -- Exactly two arguments; a number value takes the native int path.
        local success,result=pcall(fn,'splash_shown',value)
        if not quiet or not success then
            log('send '..what..' value='..value..' ok='..tostring(success)
                ..' gscReady='..tostring(dvarInt('mw4_botfix_menu_ready',0)))
        end
        assert(success,tostring(result))
    end
    local function command(cmd,arg,what,quiet) notify(9170000+cmd*1000+arg,what,quiet) end
    -- DEV 38: bot skins. A skin is addressed by its number in GSC skin_pairs(team); in lists that mix both
    -- teams it is a code: allies skin k = k, axis skin k = 100+k.
    local function skinCount(team)
        local n=dvarInt('mw4_botfix_bs_count_'..team,0)
        if n<=0 then n=(team=='allies') and 15 or 5 end   -- pool sizes of this build until GSC has published them
        return n
    end
    local function skinCodeName(code)
        if code>100 then return 'Axis '..(code-100) end
        return 'Allies '..code
    end
    local function skinCodes(first)
        local values={}
        if first then values[1]={first,0} end
        for k=1,skinCount('allies') do values[#values+1]={'Allies '..k,k} end
        for k=1,skinCount('axis') do values[#values+1]={'Axis '..k,100+k} end
        return values
    end
    local function teamSkins(team,first)
        local values={{first,0}}
        for k=1,skinCount(team) do values[#values+1]={'Skin '..k,k} end
        return values
    end
    local function bitSet(mask,index)
        local bit=2^(index-1)
        return math.floor(mask/bit)%2==1
    end
    -- Per-slot skin codes of single bots (GSC: mw4_botfix_bs_slots, 17 entries).
    local BOT_SLOTS=17
    local function slotCodes()
        local list=splitList(liveText('mw4_botfix_bs_slots',''))
        local codes={}
        for i=1,BOT_SLOTS do codes[i]=tonumber(list[i] or '') or 0 end
        return codes
    end
    local botSkinShown   -- choices of the single-bot skin row at the last data request
    -- DEV 38: custom bot names from rex\Assets\Lua\mw4_botfix_names_post.lua (global MW4BotfixBotNames).
    local NAME_ALPHABET=' ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_'
    local NAME_MAX,NAMES_MAX=20,32
    local function nameList()
        local raw=rawget(_G,'MW4BotfixBotNames')
        local out,seen={},{}
        if type(raw)~='table' then return out end
        for _,name in ipairs(raw) do
            if type(name)=='string' then
                local clean=string.gsub(name,'[^ A-Za-z0-9_]','_')
                clean=string.match(clean,'^%s*(.-)%s*$') or ''
                clean=string.sub(clean,1,NAME_MAX)
                clean=string.match(clean,'^(.-)%s*$') or ''
                if clean~='' and not seen[clean] and #out<NAMES_MAX then seen[clean]=true;out[#out+1]=clean end
            end
        end
        return out
    end
    local function nameIndex(c) return (string.find(NAME_ALPHABET,c,1,true) or 64)-1 end
    local function nameSignature(list)
        local sum=#list
        for _,name in ipairs(list) do
            for i=1,#name do sum=sum+nameIndex(string.sub(name,i,i))*i end
        end
        return sum%1000
    end
    local currentMenu
    -- cmd 23 n / per name cmd 24 len + payload values 10000000 + 3 chars of 6 bits (first char lowest; all
    -- values stay below 2^24, exact even as a float) / cmd 25 sig.
    -- Sent in small bursts on a UI timer of the Settings menu; the next burst only after GSC has counted
    -- the previous one (dvar mw4_botfix_bn_rx, +1 per value), so the client's reliable command queue never
    -- fills up. Without a timer everything goes out at once.
    local NAME_BURST,NAME_TICK=10,150
    local transfer
    local function nameValues(list)
        local values={9170000+23000+#list}
        for _,name in ipairs(list) do
            values[#values+1]=9170000+24000+#name
            for first=1,#name,3 do
                local value,factor=0,1
                for i=first,math.min(first+2,#name) do
                    value=value+nameIndex(string.sub(name,i,i))*factor
                    factor=factor*64
                end
                values[#values+1]=10000000+value
            end
        end
        values[#values+1]=9170000+25000+nameSignature(list)
        return values
    end
    local function transferTick()
        if not transfer then return end
        local acked=(dvarInt('mw4_botfix_bn_rx',0)-transfer.base)%100000
        if acked<transfer.pos then
            transfer.waits=transfer.waits+1
            if transfer.waits>20 then
                log('bot names: transfer stopped at '..acked..'/'..#transfer.values..' values (no answer from GSC)')
                transfer=nil
            end
            return
        end
        transfer.waits=0
        if transfer.pos>=#transfer.values then
            log('bot names: '..transfer.count..' names transferred ('..#transfer.values..' values)')
            transfer=nil
            return
        end
        for i=transfer.pos+1,math.min(transfer.pos+NAME_BURST,#transfer.values) do
            notify(transfer.values[i],'bot names',true)
            transfer.pos=i
        end
    end
    local function nameTimer(menu)
        if menu==nil then return false end
        if rawget(RT,'namesTimerMenu')==menu then return true end
        local timerType=read(read(_G,'LUI'),'UITimer')
        local new=read(timerType,'new')
        if type(new)~='function' then return false end
        local success=pcall(function()
            local timer=new({interval=NAME_TICK,event='mw4_botfix_names_tick'})
            invoke(menu,'addElement',timer)
            invoke(menu,'registerEventHandler','mw4_botfix_names_tick',function()
                local done,failure=pcall(transferTick)
                if not done then log('bot names: '..tostring(failure));transfer=nil end
            end)
        end)
        if success then RT.namesTimerMenu=menu end
        return success
    end
    local function sendNames(list)
        local values=nameValues(list)
        if nameTimer(currentMenu) then
            transfer={values=values,pos=0,waits=0,count=#list,base=dvarInt('mw4_botfix_bn_rx',0)}
            log('sending '..#list..' bot names in '..#values..' values (bursts of '..NAME_BURST..', signature '
                ..nameSignature(list)..')')
            transferTick()
            return
        end
        for _,value in ipairs(values) do notify(value,'bot names',true) end
        log('sent '..#list..' bot names in '..#values..' values at once (no UI timer, signature '..nameSignature(list)..')')
    end

    local function classAllowed(mask,index)
        local bit=2^(index-1)
        return math.floor(mask/bit)%2==1
    end
    -- Display names as the game's own UI resolves them (WEAPON.GetName, else the
    -- weapon data "name" string through Engine.Localize); falls back to the code name.
    local displayNames={}
    local function weaponName(root)
        if root==nil or root=='' then return 'Off' end
        if displayNames[root] then return displayNames[root] end
        local weapon=read(_G,'WEAPON')
        local name
        local getName=read(weapon,'GetName')
        if type(getName)=='function' then
            local success,value=pcall(getName,root)
            if success and type(value)=='string' and value~='' then name=value end
        end
        if not name then
            local getData=read(weapon,'GetWeaponData')
            local localize=read(read(_G,'Engine'),'Localize')
            if type(getData)=='function' then
                local success,data=pcall(getData,root)
                local ref=success and data and read(data,'name')
                if type(ref)=='string' and ref~='' then
                    if type(localize)=='function' then
                        local okText,text=pcall(localize,ref)
                        if okText and type(text)=='string' and text~='' then name=text end
                    end
                    name=name or ref
                end
            end
        end
        name=name or root
        displayNames[root]=name
        log('weapon name '..root..' = '..name)
        return name
    end
    local function weaponPool()
        local pool={}
        for root in string.gmatch(dvarString('mw4_botfix_pool',''),'[^,]+') do pool[#pool+1]=root end
        return pool
    end
    local fixedIndex,skinIndex,botCount
    -- DEV 23: replacement bots for matches where the lobby bots do not connect.
    local BOT_COUNTS={100,2,4,6,8,10,11,0}
    local function syncIndices()
        fixedIndex=liveInt('mw4_botfix_fixed',0)
        skinIndex=liveInt('mw4_botfix_skin',0)
        botCount=liveInt('mw4_botfix_fb_count',100)
    end
    syncIndices()
    local function nextBotCount()
        for i,value in ipairs(BOT_COUNTS) do
            if value==botCount then return BOT_COUNTS[i%#BOT_COUNTS+1] end
        end
        for _,value in ipairs(BOT_COUNTS) do
            if value>botCount and value<100 then return value end
        end
        return 0
    end

    -- Entries. Buttons have title() and press(). Choice entries (dropdown rows) have label, choices(),
    -- current() (1-based index into choices()) and choose(index); their title() and press() for the
    -- overlay fallback and for button rows are derived below ("label: choice", next choice).
    -- title()/choices() are evaluated whenever the game asks for the setting data (tab open, scrolling).
    local CATEGORY_TEXT='BOTFIX'
    -- Two categories; the header ids are only used when the game cannot show a plain category name.
    local GROUPS={{id='player',text='BOTFIX: PLAYER',header='mw4_botfix_header'},
        {id='bots',text='BOTFIX: BOTS',header='mw4_botfix_header_bots'},
        {id='skins',text='BOTFIX: BOT SKINS',header='mw4_botfix_header_skins'}}
    local GROUP_BY_HEADER={}
    for _,group in ipairs(GROUPS) do GROUP_BY_HEADER[group.header]=group end
    local BOT_MAX=17
    local function column(list,index)
        local out={}
        for i,item in ipairs(list) do out[i]=item[index] end
        return out
    end
    -- Settings GSC keeps in a dvar (cmd 6-12): values = {label, value sent and stored}.
    -- In the main menu there is no match, so the GSC side never gets a pick.
    local function inFrontend()
        local fn=read(read(_G,'Engine'),'InFrontend')
        if type(fn)~='function' then return false end
        local success,value=pcall(fn)
        return success and value==true
    end
    local function setting(def)
        local function values()
            if type(def.values)=='function' then return def.values() end
            return def.values
        end
        def.choices=function()
            def.shown=values()
            return column(def.shown,1)
        end
        def.current=function()
            local value=liveInt(def.dvar,def.default)
            for i,item in ipairs(def.shown or values()) do if item[2]==value then return i end end
            return 1
        end
        def.choose=function(index)
            local value=(def.shown or values())[index][2]
            command(def.cmd,value,def.what)
            expect(def.dvar,value,def.default)
            if def.needsMode and value>0 and liveInt('mw4_botfix_bs_mode',0)==0 then expect('mw4_botfix_bs_mode',1,0) end
        end
        return def
    end
    local DEFS
    DEFS={
        setting{id='mw4_botfix_set_auav',group='player',label='Advanced UAV',cmd=6,dvar='mw4_botfix_auav',
            default=2,what='advanced UAV',values={{'On',2},{'Off',0}},
            desc='Shows every enemy with its facing direction on your minimap for the whole match, like a permanent '
                ..'Advanced UAV. Only for you, not for the bots.'},
        setting{id='mw4_botfix_set_hp',group='player',label='My Health',cmd=7,dvar='mw4_botfix_hp',
            default=0,what='my health',
            values={{'Default',0},{'150',1},{'200',2},{'300',3},{'500',4},{'Invulnerable',5}},
            desc='Your maximum health, right away and after every spawn. Invulnerable = you take no damage at all, '
                ..'not even from death zones or the map border.'},
        setting{id='mw4_botfix_set_ammo',group='player',label='Unlimited Ammo',cmd=8,dvar='mw4_botfix_ammo',
            default=0,what='unlimited ammo',values={{'Off',0},{'On',1}},
            desc='Keeps the magazine and reserve ammo of your weapons, your lethal and your tactical topped up.'},
        setting{id='mw4_botfix_set_speed',group='player',label='Movement Speed',cmd=9,dvar='mw4_botfix_speed',
            default=0,what='move speed',values={{'Normal',0},{'110 %',1},{'125 %',2},{'150 %',3}},
            desc='How fast you walk and sprint.'},
        {id='mw4_botfix_skin',group='player',label='My Skin',
            desc='Changes your own operator skin. Default = the skin from your loadout.',
            choices=function()
                local count=dvarInt('mw4_botfix_skin_count',0)
                local list={'Default'}
                -- Until GSC has published the size of my team's pool, the smaller pool (axis, 5 skins): GSC turns
                -- an index above my pool into Default.
                for i=1,math.max(count>0 and count or 5,skinIndex) do
                    if count>0 then list[i+1]='Skin '..i..'/'..count else list[i+1]='Skin '..i end
                end
                return list
            end,
            current=function() return skinIndex+1 end,
            choose=function(index)
                command(3,index-1,'my skin')
                skinIndex=index-1
                expect('mw4_botfix_skin',skinIndex,0)
            end},
        {id='mw4_botfix_reset',group='player',label='Reset All Settings',
            desc='Sets every BOTFIX setting back to its default: your settings, the bot settings, bot weapons, bot '
                ..'skins and bot names (the names file stays as it is).',
            choices=function() return {'No','Yes, Reset Everything'} end,
            current=function() return 1 end,
            -- the overlay fallback cycles rows with one press: no reset from there
            press=function() end,
            choose=function(index)
                if index~=2 then return end
                transfer=nil   -- a running name transfer must not switch Custom names on afterwards
                command(30,0,'reset all settings')
                for _,d in ipairs(DEFS) do
                    if d.dvar and d.default~=nil then expect(d.dvar,d.default,d.default) end
                end
                classIndex=1
                fixedIndex=0
                skinIndex=0
                botCount=100
                expect('mw4_botfix_allow',63,63)
                expect('mw4_botfix_fixed',0,0)
                expect('mw4_botfix_skin',0,0)
                expect('mw4_botfix_fb_count',100,100)
                expect('mw4_botfix_bn_mode',0,0)
                expect('mw4_botfix_bs_block_allies',0,0)
                expect('mw4_botfix_bs_block_axis',0,0)
                expectText('mw4_botfix_bs_slots','','')
            end},
        setting{id='mw4_botfix_set_bdiff',group='bots',label='Friendly Bot Difficulty',cmd=10,dvar='mw4_botfix_bdiff',
            default=0,what='friendly bot difficulty',
            values={{'Lobby Setting',0},{'Recruit',1},{'Regular',2},{'Hardened',3},{'Veteran',4}},
            desc='Difficulty of the bots on your team, replacement bots included. Lobby Setting = as set in the lobby.'},
        setting{id='mw4_botfix_set_bdiff_e',group='bots',label='Enemy Bot Difficulty',cmd=27,dvar='mw4_botfix_bdiff_e',
            default=0,what='enemy bot difficulty',
            values={{'Lobby Setting',0},{'Recruit',1},{'Regular',2},{'Hardened',3},{'Veteran',4}},
            desc='Difficulty of the enemy bots (in Free-for-All: all bots), replacement bots included. Lobby Setting = '
                ..'as set in the lobby.'},
        setting{id='mw4_botfix_set_bhp',group='bots',label='Friendly Bot Health',cmd=11,dvar='mw4_botfix_bhp',
            default=0,what='friendly bot health',values={{'Default',0},{'50',1},{'150',2},{'200',3},{'300',4}},
            desc='Maximum health of the bots on your team, right away and after every spawn.'},
        setting{id='mw4_botfix_set_bhp_e',group='bots',label='Enemy Bot Health',cmd=28,dvar='mw4_botfix_bhp_e',
            default=0,what='enemy bot health',values={{'Default',0},{'50',1},{'150',2},{'200',3},{'300',4}},
            desc='Maximum health of the enemy bots (in Free-for-All: all bots), right away and after every spawn.'},
        setting{id='mw4_botfix_set_freeze',group='bots',label='Freeze Bots',cmd=12,dvar='mw4_botfix_freeze',
            default=0,what='freeze bots',values={{'Off',0},{'On',1}},
            desc='Stops all bots: they do not move, aim or shoot until you switch it off again.'},
        setting{id='mw4_botfix_set_bammo',group='bots',label='Bot Unlimited Ammo',cmd=29,dvar='mw4_botfix_bammo',
            default=0,what='bot unlimited ammo',values={{'Off',0},{'On',1}},
            desc='Keeps the reserve ammo of every bot\'s primary and secondary weapon full. (With Bot Fixed Weapon the '
                ..'fixed weapon is always kept full.)'},
        {id='mw4_botfix_class',group='bots',label='Bot Weapon Class',also='mw4_botfix_allow',
            desc='Selects the weapon class that the next row allows or blocks for bots.',
            choices=function() return column(CLASSES,2) end,
            current=function() return classIndex end,
            choose=function(index) classIndex=index end},
        {id='mw4_botfix_allow',group='bots',label=function() return CLASSES[classIndex][2]..' for Bots' end,
            desc='Allows or blocks the selected weapon class for bots. Living bots switch weapons right away.',
            choices=function() return {'Allowed','Blocked'} end,
            current=function() return classAllowed(liveInt('mw4_botfix_allow',63),classIndex) and 1 or 2 end,
            choose=function(index)
                local mask=liveInt('mw4_botfix_allow',63)
                local allowed=classAllowed(mask,classIndex)
                if allowed==(index==1) then return end
                local bit=2^(classIndex-1)
                if allowed then mask=mask-bit else mask=mask+bit end
                command(1,mask,'bot class mask '..CLASSES[classIndex][1])
                expect('mw4_botfix_allow',mask,63)
            end},
        {id='mw4_botfix_fixed',group='bots',label='Bot Fixed Weapon',
            desc='Gives every bot the same primary weapon, right away. Off = normal classes.',
            choices=function()
                local pool=weaponPool()
                local list={'Off'}
                for i=1,math.max(#pool,fixedIndex) do
                    local root=pool[i]
                    if not root and i==fixedIndex then root=dvarString('mw4_botfix_fixed_name','') end
                    if root and root~='' then list[i+1]=weaponName(root) else list[i+1]='Weapon '..i end
                end
                return list
            end,
            current=function() return fixedIndex+1 end,
            choose=function(index)
                command(2,index-1,'bot fixed weapon')
                fixedIndex=index-1
                expect('mw4_botfix_fixed',fixedIndex,0)
            end},
        {id='mw4_botfix_bots',group='bots',label='Replacement Bots',
            desc='Bots that are added automatically after a map restart or a new match. Auto = as in the lobby '
                ..'(count, teams, difficulty), number = fixed count, Off = none.',
            choices=function()
                local recorded=dvarInt('mw4_botfix_lb_total',-1)
                local list={'Auto ('..(recorded>0 and recorded or 11)..')','Off'}
                local most=BOT_MAX
                if botCount>most and botCount<100 then most=botCount end
                for n=1,most do list[n+2]=tostring(n) end
                return list
            end,
            current=function()
                if botCount>=100 then return 1 end
                if botCount<=0 then return 2 end
                return botCount+2
            end,
            choose=function(index)
                local value=index==1 and 100 or index-2
                command(5,value,'replacement bots')
                botCount=value
                expect('mw4_botfix_fb_count',value,100)
            end,
            -- The overlay fallback keeps the short DEV 23 cycle.
            press=function()
                local value=nextBotCount()
                command(5,value,'replacement bots')
                botCount=value
                expect('mw4_botfix_fb_count',value,100)
            end},
        setting{id='mw4_botfix_set_hsonly',group='bots',label='Headshots Only',cmd=13,dvar='mw4_botfix_hsonly',
            default=0,what='headshots only',values={{'Off',0},{'On',1}},
            desc='Training mode: bots only take damage from your headshots. Body shots, explosives, melee and '
                ..'killstreaks deal no damage to bots. Death zones and falls still kill them.'},
        setting{id='mw4_botfix_set_brespawn',group='bots',label='Bot Respawn Delay',cmd=14,dvar='mw4_botfix_brespawn',
            default=0,what='bot respawn delay',
            values={{'Default',0},{'Instant',1},{'1 s',2},{'2 s',3},{'3 s',4},{'5 s',5},{'10 s',6},{'15 s',7}},
            desc='How long bots wait before they respawn, after the short death animation. Default = the game mode '
                ..'setting. Has no effect in modes with limited lives or wave respawns.'},
        {id='mw4_botfix_names',group='bots',label='Bot Names',
            desc=function()
                return 'Custom names for the bots the mod adds itself (replacement bots after a map restart or a new '
                    ..'match). Lobby bots keep their names. Names are read from rex\\Assets\\Lua\\mw4_botfix_names_post.lua ('
                    ..#nameList()..' names); restart the game after editing it. Default = the game\'s names.'
            end,
            choices=function()
                local count=#nameList()
                if count==0 then return {'Default','Custom (no names file)'} end
                return {'Default','Custom ('..count..' names)'}
            end,
            current=function() return liveInt('mw4_botfix_bn_mode',0)==1 and 2 or 1 end,
            choose=function(index)
                if index==1 then
                    transfer=nil   -- a running transfer must not switch Custom on afterwards
                    command(22,0,'bot names default')
                    expect('mw4_botfix_bn_mode',0,0)
                    return
                end
                local list=nameList()
                if #list==0 then
                    log('bot names: MW4BotfixBotNames is missing or empty (mw4_botfix_names_post.lua)')
                    return
                end
                -- GSC switches custom names on itself once the complete list has arrived
                sendNames(list)
                expect('mw4_botfix_bn_mode',1,0)
            end},
        setting{id='mw4_botfix_bs_mode',group='skins',label='Bot Skins',cmd=15,dvar='mw4_botfix_bs_mode',default=0,
            what='bot skins',values={{'Game Default',0},{'Custom: Keep for Match',1},{'Custom: New Every Respawn',2}},
            desc='Game Default = the game picks the bot skins. Custom = the rows below decide: a skin for single bots, '
                ..'a skin per team, otherwise a random skin from the pool. Keep for Match = a bot keeps its random skin '
                ..'until the match ends; New Every Respawn = a new random skin after every death.'},
        setting{id='mw4_botfix_bs_allies',group='skins',label='Allies Bot Skin',cmd=16,dvar='mw4_botfix_bs_fix_allies',
            default=0,what='allies bot skin',values=function() return teamSkins('allies','Random from Pool') end,
            needsMode=true,also='mw4_botfix_bs_mode',
            desc='Skin of all Allies bots. Random from Pool = every bot gets its own random skin from the allowed skins.'},
        setting{id='mw4_botfix_bs_axis',group='skins',label='Axis Bot Skin',cmd=17,dvar='mw4_botfix_bs_fix_axis',
            default=0,what='axis bot skin',values=function() return teamSkins('axis','Random from Pool') end,
            needsMode=true,also='mw4_botfix_bs_mode',
            desc='Skin of all Axis bots. Random from Pool = every bot gets its own random skin from the allowed skins.'},
        setting{id='mw4_botfix_bs_pool',group='skins',label='Pool Skin',cmd=18,dvar='mw4_botfix_bs_psel',default=1,
            what='pool skin',also='mw4_botfix_bs_use',values=function() return skinCodes(nil) end,
            desc='Selects a skin. The next row allows or blocks it for the random pool of its team.'},
        {id='mw4_botfix_bs_use',group='skins',label=function()
                return skinCodeName(liveInt('mw4_botfix_bs_psel',1))..' in Pool'
            end,
            desc='Allowed / Blocked: the selected skin may (not) be picked for random bot skins. Allow All = every '
                ..'skin of that team. Only This Skin = block all other skins of that team.',
            choices=function() return {'Allowed','Blocked','Allow All','Only This Skin'} end,
            current=function()
                local code=liveInt('mw4_botfix_bs_psel',1)
                local team=code>100 and 'axis' or 'allies'
                local k=code>100 and code-100 or code
                return bitSet(liveInt('mw4_botfix_bs_block_'..team,0),k) and 2 or 1
            end,
            choose=function(index)
                local code=liveInt('mw4_botfix_bs_psel',1)
                local team=code>100 and 'axis' or 'allies'
                local k=code>100 and code-100 or code
                local dvar='mw4_botfix_bs_block_'..team
                local mask=liveInt(dvar,0)
                local all=2^skinCount(team)-1
                local bit=2^(k-1)
                local blocked=bitSet(mask,k)
                local new=mask
                if index==1 and blocked then new=mask-bit
                elseif index==2 and not blocked then new=mask+bit
                elseif index==3 then new=0
                elseif index==4 then new=all-bit end
                command(19,index-1,'pool skin use '..skinCodeName(code))
                -- GSC refuses to block the last allowed skin (and says so on screen)
                if new~=mask and new<all then expect(dvar,new,0) end
            end},
        setting{id='mw4_botfix_bs_bot',group='skins',label='Single Bot',cmd=20,dvar='mw4_botfix_bs_bsel',default=1,
            what='single bot',also='mw4_botfix_bs_botskin',
            values=function()
                local names=splitList(dvarString('mw4_botfix_bs_names',''))
                local count=math.max(#names,dvarInt('mw4_botfix_bs_bots',0))
                if count<=0 then count=BOT_SLOTS end
                local values={}
                for i=1,math.min(count,BOT_SLOTS) do
                    local name=names[i]
                    if name and name~='' then values[i]={'Bot '..i..': '..name,i} else values[i]={'Bot '..i,i} end
                end
                return values
            end,
            desc='Selects a bot (numbered in join order). The next row gives this bot its own skin.'},
        {id='mw4_botfix_bs_botskin',group='skins',also='mw4_botfix_bs_mode',
            label=function() return 'Skin of Bot '..liveInt('mw4_botfix_bs_bsel',1) end,
            desc='Own skin for the selected bot; it stays after respawns. Team Setting = the bot uses its team row. '
                ..'An Allies skin on an Axis bot (or the other way round) may not show in team modes.',
            choices=function()
                botSkinShown=skinCodes('Team Setting')
                return column(botSkinShown,1)
            end,
            current=function()
                local code=slotCodes()[liveInt('mw4_botfix_bs_bsel',1)] or 0
                for i,item in ipairs(botSkinShown or skinCodes('Team Setting')) do if item[2]==code then return i end end
                return 1
            end,
            choose=function(index)
                local values=botSkinShown or skinCodes('Team Setting')
                local code=values[index][2]
                local slot=liveInt('mw4_botfix_bs_bsel',1)
                command(21,code,'single bot skin')
                if code>0 and liveInt('mw4_botfix_bs_mode',0)==0 then expect('mw4_botfix_bs_mode',1,0) end
                local codes=slotCodes()
                codes[slot]=code
                expectText('mw4_botfix_bs_slots',table.concat(codes,','),'')
            end},
    }
    local function labelOf(def)
        if type(def.label)=='function' then return def.label() end
        return def.label
    end
    local DEF_BY_ID={}
    for _,def in ipairs(DEFS) do
        assert(def.group=='player' or def.group=='bots' or def.group=='skins','entry without group: '..def.id)
        if def.choices then
            def.title=def.title or function()
                local list=def.choices()
                return labelOf(def)..': '..tostring(list[def.current()] or list[1])
            end
            def.press=def.press or function()
                local list=def.choices()
                def.choose(def.current()%#list+1)
            end
        end
        DEF_BY_ID[def.id]=def
    end
    do
        local others={}
        for _,def in ipairs(DEFS) do if def.id~='mw4_botfix_reset' then others[#others+1]=def.id end end
        DEF_BY_ID['mw4_botfix_reset'].also=others
    end

    -- Overlay buttons of the current menu (DEV 25 fallback), by entry id.
    local overlay={buttons={}}
    -- Every widget built for an id (the grid recycles widgets, a tab reset builds hidden ones).
    local registry={}
    local function remember(id,widget)
        local set=registry[id]
        if not set then set=setmetatable({},{__mode='k'});registry[id]=set end
        set[widget]=true
    end
    local function liveWidgets(id)
        local list={}
        for widget in pairs(registry[id] or {}) do
            local success,widgetId=pcall(read,widget,'id')
            if success and widgetId==id then list[#list+1]=widget end
        end
        return list
    end
    local function titleElement(widget)
        return read(widget,'Title') or read(read(widget,'GenericOptionButtonBase'),'Title')
            or read(read(widget,'OptionButtonBase'),'Title')
    end
    local function showTitle(def,text)
        text=text or def.title()
        for _,widget in ipairs(liveWidgets(def.id)) do
            local name=text
            local box=def.choices and read(widget,'DropdownButton')
            if box~=nil then
                -- Dropdown row: the title is the label, the box shows the current choice.
                name=labelOf(def)
                local index=def.current()
                pcall(write,widget,'_currentValue',index)
                call(read(box,'Text'),'setText',tostring(def.choices()[index] or ''))
            end
            call(titleElement(widget),'setText',name)
            pcall(function() widget.buttonName=name end)
            if read(widget,'isDisplayed') then
                -- Same as the stock blocked-players row: keep the details panel in step.
                call(read(currentMenu,'DetailsOption'),'UpdateOptionName',{buttonName=name})
            end
        end
        local button=overlay.buttons[def.id]
        if button and overlay.setText then overlay.setText(button,text) end
    end
    -- Rows whose title or box depend on this row (def.also: one id or a list of ids).
    local function showAlso(def)
        if not def.also then return end
        local list=def.also
        if type(list)~='table' then list={list} end
        for _,id in ipairs(list) do if DEF_BY_ID[id] then showTitle(DEF_BY_ID[id]) end end
    end
    local function onPress(def)
        local success,failure=pcall(function()
            local override=def.press()
            showTitle(def,override)
            showAlso(def)
        end)
        if not success then log('row '..def.id..' failed: '..tostring(failure)) end
    end
    -- A pick in a dropdown row (index into the labels the row was built with).
    local function onChoose(def,index,count)
        local success,failure=pcall(function()
            if type(index)~='number' or index<1 or index>count or index~=math.floor(index) then
                error('no valid choice '..tostring(index))
            end
            log('choice '..def.id..' = '..index..' ('..tostring(def.choices()[index])..')')
            def.choose(index)
        end)
        if not success then log('row '..def.id..' failed: '..tostring(failure)) end
        -- Also when the command failed: the box then shows the real value again.
        local shown,problem=pcall(function()
            showTitle(def)
            showAlso(def)
        end)
        if not shown then log('row '..def.id..' failed: '..tostring(problem)) end
    end
    local function optionType(name,default)
        local value=read(read(read(_G,'OPTIONS'),'OptionType'),name)
        if value==nil then return default end
        return value
    end
    -- Setting data like the game's (auto-xhash tables): every field under its name and its xhash.
    local function dataTable(fields)
        local t={}
        for k,v in pairs(fields) do
            rawset(t,k,v)
            if type(xhash)=='function' then
                local success,h=pcall(xhash,k)
                if success and h~=nil and h~=k then pcall(rawset,t,h,v) end
            end
        end
        return t
    end
    -- Setting data for one entry, built fresh for every request (callers modify it).
    local function buildData(id)
        -- hideInSearch: the stock search looks rows up by a prefixed hash of the id, which a
        -- string id never matches (ipairs(nil) in SearchUtils), so our rows stay out of it.
        local fields={id=id,settingBundle=id,applyable=false,applyableOverride=true,resetDisabled=true,
            lockedFavorite=true,skipLockedFavoriteDescription=true,hideInSearch=true}
        if GROUP_BY_HEADER[id] then
            fields.type=optionType('CATEGORY','SubCategory')
            fields.name=GROUP_BY_HEADER[id].text
            fields.index=2
            return dataTable(fields)
        end
        local def=DEF_BY_ID[id]
        syncIndices()
        fields.description=def.desc
        if type(def.desc)=='function' then fields.description=def.desc() end
        if inFrontend() then fields.description=tostring(fields.description)..' Works only during a match.' end
        fields.specificAction=function(_,widget)
            remember(id,widget)
            logOnce('built '..id,'row built '..id..' title='..tostring(titleElement(widget)~=nil)
                ..(def.choices and (' dropdown='..tostring(read(widget,'DropdownButton')~=nil)) or ''))
        end
        local dropdown=def.choices and optionType('DROPDOWN',nil)
        if dropdown~=nil then
            -- Dropdown row like the game's own (OptionsData): labels, value() = 1-based index of the
            -- current choice, action on a pick, defaultOptionValue() for the reset logic (= current,
            -- nothing to reset). This build calls action(controller, index) (DEV 36 log: number, number,
            -- nil); the decompiled reference has action(element, controller, index). Both are accepted.
            local labels=def.choices()
            local function index()
                local i=def.current()
                if type(i)~='number' or i<1 or i>#labels then return 1 end
                return i
            end
            logOnce('dropdown type','dropdown type '..type(dropdown)..':'..tostring(dropdown))
            fields.type=dropdown
            fields.name=labelOf(def)
            fields.labels=labels
            fields.value=function() return index() end
            fields.defaultOptionValue=function() return index() end
            fields.action=function(a,b,c)
                logOnce('choice args','dropdown action args: '..type(a)..':'..tostring(a)..', '
                    ..type(b)..':'..tostring(b)..', '..type(c)..':'..tostring(c))
                local function valid(i) return type(i)=='number' and i>=1 and i<=#labels and i==math.floor(i) end
                local picked
                if type(c)=='number' then
                    picked=c                                   -- action(element, controller, index)
                elseif type(a)=='number' and type(b)=='number' then
                    -- action(controller, index); the controller is normally 0, the index is 1-based
                    picked=b
                    if not valid(b) and valid(a) then picked=a end
                elseif type(a)=='number' and b==nil then
                    picked=a                                   -- action(index)
                else
                    -- no index at all: the widget's current value
                    local success,current=pcall(read,a,'_currentValue')
                    if success then picked=current end
                end
                onChoose(def,picked,#labels)
            end
            return dataTable(fields)
        end
        fields.type=optionType('GENERIC_BUTTON','GenericButton')
        logOnce('type','row type '..type(fields.type)..':'..tostring(fields.type))
        fields.name=def.title()
        fields.action=function() onPress(def) end
        return dataTable(fields)
    end

    -- Tab data: debug tab -> sub tabs -> categories -> entries. Keys of the game's lists are
    -- hashes; they are taken from the game's own tables where possible.
    local function isHashKey(k) local kind=type(k); return kind~='string' and kind~='number' and kind~='boolean' end
    local function try(fn,...) local success,a,b=pcall(fn,...); if success then return a,b end end
    local function keyByHash(t,name)
        if type(xhash)~='function' then return nil end
        local key=xhash(name)
        if try(function() return t[key] end)~=nil then return key end
    end
    local function scanKey(t,accept,exclude)
        return try(function()
            for k,v in pairs(t) do
                if k~=exclude and isHashKey(k) and accept(v) then return k end
            end
        end)
    end
    local function isList(v) local kind=type(v); return kind=='table' or kind=='function' end
    local function isRef(v) local kind=type(v); return kind~='table' and kind~='function' and kind~='boolean' and kind~='nil' end
    local function listOf(t,key)
        local value=try(function() return t[key] end)
        if type(value)=='function' then value=try(value) end
        return value
    end
    local function copyArray(list)
        return try(function()
            local copy={}
            for i,v in ipairs(list) do copy[i]=v end
            return copy
        end)
    end
    -- Copy of a game object with one field replaced. Never the game object's own metatable (its C
    -- accessor only works on the real object): missing fields are read from the original instead.
    local function copyWith(t,key,value)
        local copy={}
        try(function() for k,v in pairs(t) do copy[k]=v end end)
        copy[key]=value
        return setmetatable(copy,{__index=function(_,k) return t[k] end})
    end
    local categoryMode
    local function decideCategory()
        if categoryMode then return categoryMode end
        local localize=read(read(_G,'Engine'),'Localize')
        local text=type(localize)=='function' and try(localize,CATEGORY_TEXT) or nil
        categoryMode=(text==CATEGORY_TEXT) and 'native' or 'pseudo'
        log('category: Localize("'..CATEGORY_TEXT..'") -> '..tostring(text)..' => '..categoryMode)
        return categoryMode
    end
    local function listKeyOf(t)
        local key=keyByHash(t,'optionslist')
        if key~=nil then return key,'xhash' end
        return scanKey(t,isList),'scan'
    end
    -- New category list = the game's categories + ours (nil,status if not possible).
    local function injectCategories(categories,listKey,how)
        local newCategories=categories and copyArray(categories)
        if not newCategories then return nil,'categories not copyable' end
        for _,category in ipairs(newCategories) do
            if RT.ourLists[category] then return nil,'already' end
        end
        local nameKey,bundleKey
        if how=='xhash' then
            -- xhash matches the game's hashes: use it for the other keys as well.
            nameKey,bundleKey=xhash('name'),xhash('settingbundle')
        else
            -- Take the keys from a stock category that has entries (name = its other key).
            for _,category in ipairs(newCategories) do
                local list=listOf(category,listKey)
                local sampleEntry=type(list)=='table' and list[1] or nil
                if sampleEntry~=nil then
                    bundleKey=scanKey(sampleEntry,isRef,listKey)
                    nameKey=scanKey(category,isRef,listKey)
                    if bundleKey~=nil then break end
                end
            end
        end
        if bundleKey==nil then return nil,'no bundle key' end
        logOnce('keys','keys: list='..how..' name='..tostring(nameKey~=nil)..' bundle='..tostring(bundleKey~=nil)
            ..' xhashList='..tostring(type(xhash)=='function' and listKey==xhash('optionslist')))
        local native=decideCategory()=='native' and nameKey~=nil
        local stock=#newCategories
        for _,group in ipairs(GROUPS) do
            local entries={}
            if not native then entries[#entries+1]={[bundleKey]=group.header} end
            for _,def in ipairs(DEFS) do
                if def.group==group.id then entries[#entries+1]={[bundleKey]=def.id} end
            end
            local category={[listKey]=entries}
            if native then category[nameKey]=group.text end
            RT.ourLists[category]=true
            newCategories[#newCategories+1]=category
        end
        RT.ourLists[newCategories]=true
        return newCategories,'+'..#DEFS..' rows in '..#GROUPS..' categories ('..(native and 'native' or 'pseudo')
            ..' headers, '..stock..' stock categories)'
    end
    -- New sub tab list whose first sub tab has our category (nil,status if not possible).
    local function injectSubtabs(subtabs,listKey,how)
        if RT.ourLists[subtabs] then return nil,'already' end
        local first=try(function() return subtabs[1] end)
        if first==nil then return nil,'no first sub tab' end
        if listKey==nil then listKey,how=listKeyOf(first) end
        if listKey==nil then return nil,'no list key' end
        local newCategories,status=injectCategories(listOf(first,listKey),listKey,how)
        if not newCategories then return nil,status end
        local newSubtabs=copyArray(subtabs)
        if not newSubtabs then return nil,'sub tabs not copyable' end
        newSubtabs[1]=copyWith(first,listKey,newCategories)
        RT.ourLists[newSubtabs]=true
        return newSubtabs,status
    end
    -- Returns status, injected, bundle reference (when the tab only names its settings bundle).
    local function injectTab(tab)
        local listKey,how=listKeyOf(tab)
        if listKey==nil then
            -- No list under a known key: look for a value that GetSettingListFromId resolves
            -- (the tab may only name its settings bundle, and all its values are hashes).
            local getList=readAny(read(_G,'OPTIONS'),'GetSettingListFromId')
            local found=type(getList)=='function' and try(function()
                for k,v in pairs(tab) do
                    if isHashKey(k) and isRef(v) and type(try(getList,v))=='table' then return v end
                end
            end) or nil
            if found~=nil then return 'bundle reference',false,found end
            return 'no list key',false
        end
        local subtabs=listOf(tab,listKey)
        if subtabs==nil then return 'no sub tabs',false end
        if RT.ourLists[subtabs] then return 'already',true end
        if type(subtabs)~='table' and try(function() return subtabs[1] end)==nil then
            return 'bundle reference',false,subtabs
        end
        local newSubtabs,status=injectSubtabs(subtabs,listKey,how)
        if not newSubtabs then return status,status=='already' end
        tab[listKey]=newSubtabs
        return status,true
    end
    local function debugId() return read(read(read(_G,'OPTIONS'),'TabIds'),'DEBUG') or 'debug' end
    local function isDebugTab(tab)
        local id=try(function() return read(tab,'id') end)
        return id~=nil and (id==debugId() or id=='debug')
    end
    local function debugTab(tabs,map)
        local entry=type(map)=='table' and map[debugId()]
        local data=entry and read(entry,'data')
        if data then return data end
        if type(tabs)=='table' then
            for _,tab in ipairs(tabs) do
                if isDebugTab(tab) then return tab end
            end
        end
    end
    local function wrapTabsData(base)
        return function(...)
            local results=pack(base(...))
            local success,failure=pcall(function()
                local tab=debugTab(results[1],results[2])
                if not tab then return end
                local status=injectTab(tab)
                logOnce('inject '..status,'inject: '..status)
            end)
            if not success then logOnce('inject failed '..tostring(failure),'inject failed: '..tostring(failure)) end
            return unpackArgs(results,1,results.n)
        end
    end
    -- The debug tab's settings bundle (captured from the built menu); its list gets our category.
    -- Trace (limited): how the game asks for lists and rows while a Settings menu is open.
    local trace={lists=0,rows=0,avail=0,ours=0,limit=60}
    local function traceLog(s) if trace.limit>0 then trace.limit=trace.limit-1;log('trace '..s) end end
    local function showv(v) return type(v)..':'..tostring(v) end
    local function wrapListFromId(base)
        return function(id,sub,...)
            local results=pack(base(id,sub,...))
            trace.lists=trace.lists+1
            local isDebugBundle=RT.debugBundle~=nil and try(function() return id==RT.debugBundle end) or false
            if RT.tracing then
                traceLog('list #'..trace.lists..' id='..showv(id)..' debug='..tostring(isDebugBundle)..' sub='..showv(sub)
                    ..' result='..type(results[1]))
            end
            local bundle=RT.debugBundle
            if bundle~=nil and results[1]~=nil and (sub==nil or sub==1) then
                local same=try(function() return id==bundle end)
                if same then
                    local success,list,status=pcall(function()
                        if sub==nil then return injectSubtabs(results[1]) end
                        local listKey,how=listKeyOf(try(function() return results[1][1] end) or {})
                        if listKey==nil and type(xhash)=='function' then listKey,how=xhash('optionslist'),'xhash' end
                        return injectCategories(results[1],listKey,how)
                    end)
                    if success and list then
                        results[1]=list
                        RT.served=true
                        logOnce('served '..tostring(sub)..tostring(status),'list served for the debug tab ('
                            ..(sub==nil and 'sub tabs' or 'categories')..'): '..tostring(status))
                    elseif not success then
                        logOnce('serve failed '..tostring(list),'list inject failed: '..tostring(list))
                    else
                        logOnce('serve '..tostring(status),'list not injected: '..tostring(status))
                        if status=='already' then RT.served=true end
                    end
                end
            end
            return unpackArgs(results,1,results.n)
        end
    end
    -- Engine.GetScriptBundle: the debug tab's bundle as a stand-in with our category in its list.
    local bundleProxies=setmetatable({},{__mode='k'})
    local function wrapScriptBundle(base)
        return function(id,...)
            local results=pack(base(id,...))
            local bundle=RT.debugBundle
            local original=results[1]
            if bundle~=nil and original~=nil and try(function() return id==bundle end) then
                trace.bundles=(trace.bundles or 0)+1
                local proxy=try(function() return bundleProxies[original] end)
                if not proxy then
                    local success,list,status,listKey=pcall(function()
                        local key,how=listKeyOf(original)
                        if key==nil and type(xhash)=='function' then key,how=xhash('optionslist'),'xhash' end
                        local subtabs=listOf(original,key)
                        if subtabs==nil then return nil,'no list in bundle' end
                        local newSubtabs,st=injectSubtabs(subtabs)
                        return newSubtabs,st,key
                    end)
                    if success and list then
                        proxy=setmetatable({[listKey]=list},{__index=function(_,k) return original[k] end})
                        pcall(function() bundleProxies[original]=proxy end)
                        logOnce('bundle '..tostring(status),'bundle served for the debug tab: '..tostring(status))
                        RT.served=true
                    else
                        logOnce('bundle no '..tostring(list)..tostring(status),'bundle not injected: '..tostring(success and status or list))
                    end
                end
                if proxy then results[1]=proxy;RT.served=true end
            end
            return unpackArgs(results,1,results.n)
        end
    end
    local requested={}
    -- Our id for a requested id: the string itself or its xhash.
    local hashToId
    local function ourId(id)
        if type(id)=='string' then
            if DEF_BY_ID[id] or GROUP_BY_HEADER[id] then return id end
            return nil
        end
        if id==nil or type(xhash)~='function' then return nil end
        if not hashToId then
            hashToId={}
            for _,def in ipairs(DEFS) do try(function() hashToId[xhash(def.id)]=def.id end) end
            for header in pairs(GROUP_BY_HEADER) do try(function() hashToId[xhash(header)]=header end) end
        end
        return try(function() return hashToId[id] end)
    end
    local function answer(id,via)
        trace.ours=trace.ours+1
        if not requested[id] then requested[id]=true;log('data request '..id..' via '..via) end
        local success,data=pcall(buildData,id)
        if success then return data end
        log('data '..id..' failed: '..tostring(data))
        return nil
    end
    local function wrapDataFromId(base)
        return function(id,...)
            local mine=ourId(id)
            if mine then return answer(mine,'GetSettingDataFromId') end
            return base(id,...)
        end
    end
    local function installDataHooks(reason)
        local options=read(_G,'OPTIONS')
        if type(options)~='table' then return false end
        local function hook(name,wrap)
            local current=readAny(options,name)
            if type(current)~='function' then return 'missing' end
            if RT.active[name]==current and RT.token==TOKEN then return 'kept' end
            local base=RT.wrappers[current] or current
            local wrapped=wrap(base)
            RT.wrappers[wrapped]=base
            RT.active[name]=wrapped
            write(options,name,wrapped)
            return 'installed'
        end
        local data=hook('GetSettingDataFromId',wrapDataFromId)
        -- Engine.GetScriptBundle lives on Engine, not OPTIONS.
        local engine=read(_G,'Engine')
        local bundles='missing'
        if type(engine)=='table' then
            local current=readAny(engine,'GetScriptBundle')
            if type(current)=='function' then
                if RT.active.GetScriptBundle==current and RT.token==TOKEN then bundles='kept'
                else
                    local base=RT.wrappers[current] or current
                    local wrapped=wrapScriptBundle(base)
                    RT.wrappers[wrapped]=base
                    RT.active.GetScriptBundle=wrapped
                    write(engine,'GetScriptBundle',wrapped)
                    bundles='installed'
                end
            end
        end
        local tabs=hook('GetSettingsTabsData',wrapTabsData)
        local lists=hook('GetSettingListFromId',wrapListFromId)
        hook('CreateOptionFromId',function(base)
            return function(a,b,c,id,...)
                trace.rows=trace.rows+1
                if RT.tracing then traceLog('row #'..trace.rows..' CreateOptionFromId id='..show(id)) end
                return base(a,b,c,id,...)
            end
        end)
        -- Rows of the grid come through here; answer ours directly (see DEV 32 note).
        local avail=hook('GetAvailableSettingDataFromId',function(base)
            return function(id,...)
                trace.avail=trace.avail+1
                trace.availSince=(trace.availSince or 0)+1
                local mine=ourId(id)
                if mine then return answer(mine,'GetAvailableSettingDataFromId') end
                if RT.tracing and type(id)~='xhash' then
                    trace.odd=(trace.odd or 0)+1
                    if trace.odd<=20 then traceLog('avail non-hash id #'..trace.odd..' '..showv(id)) end
                elseif RT.tracing and trace.availSince<=5 then traceLog('avail #'..trace.availSince..' id='..showv(id)) end
                local results=pack(base(id,...))
                -- Once: the field layout of a stock row's data (keys and value types) for comparison.
                if RT.tracing and not logged['layout stock'] and type(results[1])=='table' then
                    logged['layout stock']=true
                    local parts={}
                    try(function()
                        for k,v in pairs(results[1]) do
                            if #parts<40 then parts[#parts+1]=tostring(k)..'='..type(v)..(type(v)~='table' and type(v)~='function' and (':'..tostring(v)) or '') end
                        end
                    end)
                    local mt=try(function() return getmetatable(results[1]) end)
                    log('data layout stock '..showv(id)..' mt='..type(mt)..' ('..#parts..'): '..table.concat(parts,' '))
                    local ours=try(buildData,DEFS[3].id)
                    local mine={}
                    try(function()
                        for k,v in pairs(ours or {}) do
                            if #mine<40 then mine[#mine+1]=tostring(k)..'='..type(v) end
                        end
                    end)
                    log('data layout ours ('..#mine..'): '..table.concat(mine,' '))
                end
                -- Once: a stock dropdown row (fields and labels) in case ours do not open.
                if RT.tracing and not logged['layout dropdown'] and type(results[1])=='table' then
                    local dropdown=optionType('DROPDOWN',nil)
                    if dropdown~=nil and try(function() return read(results[1],'type') end)==dropdown then
                        logged['layout dropdown']=true
                        local parts={}
                        try(function()
                            for k,v in pairs(results[1]) do
                                if #parts<40 then parts[#parts+1]=tostring(k)..'='..type(v) end
                            end
                        end)
                        local labels=try(function() return read(results[1],'labels') end)
                        log('data layout stock dropdown '..showv(id)..' ('..#parts..'): '..table.concat(parts,' ')
                            ..' labels='..type(labels))
                    end
                end
                return unpackArgs(results,1,results.n)
            end
        end)
        logOnce('avail '..avail,'row data hook GetAvailableSettingDataFromId='..avail)
        RT.version=VERSION
        RT.token=TOKEN
        -- Only the data hook is required; the tab data is also extended on the built menu.
        RT.complete=data~='missing'
        -- Log changes only (DEV 26 logged "tabs=missing" on every widget build).
        logOnce('hooks '..data..' '..tabs..' '..lists..' '..bundles,'data hooks ('..reason..'): data='..data..' tabs='..tabs
            ..' lists='..lists..' bundles='..bundles)
        return data~='missing'
    end

    -- One-time diagnostic of the real names in this build.
    local function describe(v)
        local kind=type(v)
        if kind=='table' then
            local n=try(function() local c=0; for _ in pairs(v) do c=c+1 end; return c end)
            return 'table#'..tostring(n)
        end
        return kind
    end
    local function diagnose(menu)
        if logged['diag'] then return end
        logged['diag']=true
        local options=read(_G,'OPTIONS')
        local parts={}
        for _,name in ipairs({'GetSettingsTabsData','GetSettingListFromId','GetSettingDataFromId',
            'GetAvailableSettingDataFromId','CreateOptionList','InitOptionsData','UseDynamicGridInSettings',
            'GetOptionsContextualData','CreateOptionFromId','TabIds','OptionType','Menu'}) do
            parts[#parts+1]=name..'='..type(readAny(options,name))
        end
        log('diag OPTIONS '..type(options)..': '..table.concat(parts,' '))
        local names,hashed={},0
        try(function()
            for k,v in pairs(options) do
                if type(k)=='string' then
                    if string.find(k,'Tab') or string.find(k,'SettingList') or string.find(k,'SettingData') then
                        names[#names+1]=k..':'..type(v)
                    end
                else hashed=hashed+1 end
            end
        end)
        table.sort(names)
        log('diag OPTIONS tab/setting keys ('..#names..', hashed keys '..hashed..'): '..table.concat(names,' ',1,math.min(#names,40)))
        local fields={}
        for _,name in ipairs({'tabsData','tabMap','data','menuId','activeTabId','OptionWindow','DetailsOption','Tabs'}) do
            fields[#fields+1]=name..'='..describe(try(function() return read(menu,name) end))
        end
        log('diag menu: '..table.concat(fields,' '))
        local tab=debugTab(try(function() return read(menu,'tabsData') end),try(function() return read(menu,'tabMap') end))
            or (isDebugTab(try(function() return read(menu,'data') end)) and read(menu,'data')) or nil
        if tab then
            local keys={}
            try(function()
                for k,v in pairs(tab) do keys[#keys+1]=tostring(k)..'('..type(k)..')='..describe(v) end
            end)
            log('diag debug tab: '..table.concat(keys,' ',1,math.min(#keys,16)))
        else
            log('diag debug tab: not found in menu data')
        end
    end

    -- DEV 25 overlay (fallback when the list cannot be extended).
    local function buildOverlay(menu,options,isNative,deferred)
        local controller=(options and read(options,'controllerIndex')) or read(menu,'_controllerIndex') or 0
        local buttons={}
        local upperLogged=false
        local captionOf={}
        local function setText(button,s)
            captionOf[button]=s
            local label=read(button,'Label') or read(button,'LABEL')
            if type(read(button,'SetText'))=='function' then invoke(button,'SetText',s)
            else
                assert(label,'TextButton label unavailable')
                invoke(label,'setText',s)
            end
            -- If the widget's SetText upper-cased the string, put the text on the label directly.
            local getText=label and read(label,'getText')
            if type(getText)=='function' then
                local success,shown=pcall(getText,label)
                if success and type(shown)=='string' and shown~=s and string.upper(shown)==string.upper(s) then
                    invoke(label,'setText',s)
                    if not upperLogged then upperLogged=true;log('caption: SetText upper-cased the text, label set directly') end
                end
            end
        end
        overlay={buttons={},setText=setText}
        local function isDebug()
            local nativeDebugId=read(read(read(_G,'OPTIONS'),'TabIds'),'DEBUG')
            local function matches(id)
                return id~=nil and (id=='debug' or (nativeDebugId~=nil and id==nativeDebugId)
                    or (type(xhash)=='function' and id==xhash('debug')))
            end
            return matches(read(menu,'menuId')) or matches(read(menu,'activeTabId'))
                or matches(read(read(menu,'data'),'id'))
        end
        -- Layout from DEV 25 (runtime-checked by Henrik): header in the old first-row slot,
        -- rows with the stock spacing, captions where the stock titles start.
        local ROW_LEFT=88
        local ROW_RIGHT=947
        local HEADER_TOP=495
        local HEADER_HEIGHT=32
        local HEADER_GAP=8
        local FIRST_ROW_TOP=HEADER_TOP+HEADER_HEIGHT+HEADER_GAP
        local LABEL_LEFT=41
        local ROW_HEIGHT=52
        local ROW_STEP=60
        -- FONTS answers every unknown key with the Dev font and stores it, so its entries are
        -- looked up raw (never read(FONTS,...) / FONTS[name]); FONTS.GetFont is RegisterFont.
        local function fontByName(name)
            local fonts=read(_G,'FONTS')
            local register=read(_G,'RegisterFont')
            if type(fonts)~='table' or type(register)~='function' then return nil end
            local function raw(key)
                local value=rawget(fonts,key)
                if value==nil and type(xhash)=='function' then value=rawget(fonts,xhash(key)) end
                return value
            end
            local entry,dev=raw(name),raw('Dev')
            local file=type(entry)=='table' and read(entry,'File') or nil
            if file==nil or (type(dev)=='table' and read(dev,'File')==file) then return nil end
            local success,font=pcall(register,file)
            if success and font~=nil then return font end
        end
        local donor
        local function findDonor()
            if donor then return donor end
            local getWidgets=read(read(read(_G,'OPTIONS'),'Menu'),'GetOptionWidgets')
            if type(getWidgets)~='function' then return nil end
            local success,widgets=pcall(getWidgets,menu)
            if not success or type(widgets)~='table' then return nil end
            for _,widget in ipairs(widgets) do
                local title=titleElement(widget)
                local fn=title and read(title,'GetCurrentFont')
                local okFont,font=false,nil
                if type(fn)=='function' then okFont,font=pcall(fn,title) end
                if okFont and font~=nil then
                    local sizeFn=read(title,'GetFontSize')
                    local okSize,size=false,nil
                    if type(sizeFn)=='function' then okSize,size=pcall(sizeFn,title) end
                    donor={font=font,size=(okSize and type(size)=='number' and size>0) and size or nil}
                    local rgbFn=read(title,'GetRGB')
                    if type(rgbFn)=='function' then
                        local okRgb,r,g,b=pcall(rgbFn,title)
                        if okRgb and type(r)=='table' then donor.rgb=r
                        elseif okRgb and type(r)=='number' and type(g)=='number' and type(b)=='number' then donor.rgb={r=r,g=g,b=b} end
                    end
                    log('style: font copied from stock row '..tostring(read(widget,'id'))..' size='..tostring(donor.size)
                        ..' rgb='..tostring(donor.rgb~=nil))
                    return donor
                end
            end
        end
        local fallbackFont
        local styleReport
        local function matchSettingsText(button)
            -- Never shrink/reposition the native Label vertically: a zero-height label makes
            -- its caption disappear in this Rex LUI build.
            local label=read(button,'Label') or read(button,'LABEL')
            if not label then return end
            local lui=read(_G,'LUI')
            local d=findDonor()
            local font,source=d and d.font,'donor'
            if font==nil then
                if fallbackFont==nil then
                    fallbackFont=fontByName('PrimaryRegular') or fontByName('SecondaryRegular') or false
                end
                font,source=fallbackFont or nil,fallbackFont and 'fallback' or 'none'
            end
            local fontOk=font~=nil and call(label,'SetFont',font)
            local sizeOk=d~=nil and d.size~=nil and call(label,'SetFontSize',d.size)
            if sizeOk then call(label,'SetMinFontSize',d.size) end
            local regular=read(read(lui,'CaseStyle'),'Regular') or 0
            local caseOk=call(label,'setCaseStyleInC',regular)
            caseOk=call(label,'setCaseStyle',regular) or caseOk
            local trackingOk=call(label,'SetTracking',0,0)
            local left=read(read(lui,'Alignment'),'Left')
            if left~=nil then call(label,'SetAlignment',left) end
            local leftOk=call(button,'SetTextLeft',LABEL_LEFT) or call(label,'SetLeft',LABEL_LEFT)
            local colourOk=false
            if d and d.rgb then colourOk=call(label,'SetRGB',d.rgb,0) end
            local report='font='..source..':'..tostring(fontOk)..' size='..tostring(sizeOk)
                ..' left='..tostring(leftOk)..' rgb='..tostring(colourOk)
                ..' case='..tostring(caseOk)..' tracking='..tostring(trackingOk)
            if report~=styleReport then log('style: captions '..report);styleReport=report end
        end
        local function buildStockHeader()
            local success,widget=pcall(originalBuild,'SubHeaderWithPrompt',{controllerIndex=controller})
            if not success or not widget then return nil end
            local setIn=read(read(_G,'OPTIONS'),'SetElementInOptionsMenuLayout')
            if type(setIn)=='function' then pcall(setIn,controller,widget,true) end
            call(widget,'UpdateAnimationState')
            local text=read(widget,'Text')
            assert(text and call(text,'setText',CATEGORY_TEXT),'SubHeaderWithPrompt.Text unavailable')
            local animate=read(read(_G,'ACTIONS'),'AnimateSequence')
            if type(animate)=='function' then pcall(animate,widget,'Small') end
            local refreshAnimation=read(read(read(_G,'LUI'),'UIElement'),'RefreshAnimation')
            if type(refreshAnimation)=='function' then pcall(refreshAnimation,widget,'InstantFocus') end
            return widget
        end
        local header
        local function addHeader()
            local success,widget=pcall(buildStockHeader)
            if not success or not widget then log('overlay header unavailable: '..tostring(widget)); return end
            write(widget,'id','MW4BotfixHeader')
            invoke(widget,'SetAnchorsAndPosition',0,1,0,1,ROW_LEFT,ROW_RIGHT,HEADER_TOP,HEADER_TOP+HEADER_HEIGHT)
            invoke(widget,'setPriority',20)
            invoke(menu,'addElement',widget)
            header=widget
        end
        local function add(index,def)
            local button=originalBuild('TextButton',{controllerIndex=controller})
            assert(button,'Native TextButton unavailable')
            write(button,'id','MW4BotfixDebug'..index)
            invoke(button,'SetAnchorsAndPosition',0,1,0,1,ROW_LEFT,ROW_RIGHT,
                FIRST_ROW_TOP+(index-1)*ROW_STEP,
                FIRST_ROW_TOP+ROW_HEIGHT+(index-1)*ROW_STEP)
            invoke(button,'setPriority',20)
            setText(button,def.title())
            matchSettingsText(button)
            invoke(button,'addEventHandler','button_action',function()
                if not isDebug() then return false end
                onPress(def)
                return true
            end)
            invoke(menu,'addElement',button)
            setText(button,def.title())
            buttons[#buttons+1]=button
            overlay.buttons[def.id]=button
        end
        local lastVisible
        local function show(element,visible)
            if type(read(element,'SetVisible'))=='function' then invoke(element,'SetVisible',visible)
            else invoke(element,'SetAlpha',visible and 1 or 0) end
        end
        local function refresh()
            if isDebug() then
                log('debug tab shown: list calls='..trace.lists..' bundle calls='..tostring(trace.bundles or 0)..' CreateOptionFromId='..trace.rows
                    ..' GetAvailableSettingDataFromId='..trace.avail..' our data requests='..trace.ours)
            end
            local native=isNative()
            local visible=isDebug() and not native
            if native and not logged['native '..tostring(menu)] then
                logged['native '..tostring(menu)]=true
                log('native BOTFIX rows in use, overlay '..(#buttons>0 and 'hidden' or 'not built'))
            end
            if visible and #buttons==0 then
                addHeader()
                for index,def in ipairs(DEFS) do add(index,def) end
                log('overlay: TextButtons attached to Debug Options')
            elseif visible then
                -- Labels follow the settings GSC published (also after a new match).
                syncIndices()
                for index,def in ipairs(DEFS) do
                    if buttons[index] then setText(buttons[index],def.title());matchSettingsText(buttons[index]) end
                end
            end
            if header then show(header,visible) end
            for _,button in ipairs(buttons) do
                show(button,visible)
                if type(read(button,'SetButtonDisabled'))=='function' then invoke(button,'SetButtonDisabled',not visible)
                elseif type(read(button,'SetDisabled'))=='function' then invoke(button,'SetDisabled',not visible) end
            end
            if lastVisible~=visible then log('debug tab visible='..tostring(visible));lastVisible=visible end
        end
        local function safeRefresh()
            local success,failure=pcall(refresh)
            if not success then log('overlay failed: '..tostring(failure)) end
        end
        local tabs=read(menu,'Tabs') or read(menu,'TABS')
        local originalSetTabs=read(tabs,'SetTabs')
        if type(originalSetTabs)=='function' then
            write(tabs,'SetTabs',function(self,definitions,...)
                local wrapped={}
                for i,definition in ipairs(definitions) do
                    local item={};for k,v in pairs(definition) do item[k]=v end
                    local nativeFocus=read(definition,'focusFunction')
                    if type(nativeFocus)=='function' then
                        write(item,'focusFunction',function(...)
                            local results=pack(nativeFocus(...));safeRefresh()
                            return unpackArgs(results,1,results.n)
                        end)
                    end
                    wrapped[i]=item
                end
                return originalSetTabs(self,wrapped,...)
            end)
        end
        local originalUpdate=read(menu,'UpdateMenu')
        if type(originalUpdate)=='function' then
            write(menu,'UpdateMenu',function(self,...)
                local results=pack(originalUpdate(self,...));safeRefresh()
                return unpackArgs(results,1,results.n)
            end)
        end
        invoke(menu,'addEventHandler','menu_create',safeRefresh)
        -- With the list wrapper armed the decision waits for the tab events (the list is served
        -- when the tab is set up); otherwise refresh right away as DEV 25 did.
        if not deferred then safeRefresh() end
        log('overlay: Settings menu hook attached (deferred='..tostring(deferred)..')')
    end

    -- After the Settings menu is built: extend its own tab data (works without the tabs hook),
    -- otherwise fall back to the overlay.
    local function attach(menu,options)
        diagnose(menu)
        local injected,status=false,'no debug tab in menu data'
        local seen={}
        RT.served=false
        local function consider(tab)
            if tab==nil or seen[tab] or not isDebugTab(tab) then return end
            seen[tab]=true
            local text,okTab,bundle=injectTab(tab)
            status=text
            injected=injected or okTab
            if bundle~=nil then RT.debugBundle=bundle end
        end
        consider(debugTab(try(function() return read(menu,'tabsData') end),try(function() return read(menu,'tabMap') end)))
        try(function() for _,tab in ipairs(read(menu,'tabsData') or {}) do consider(tab) end end)
        consider(try(function() return read(menu,'data') end))
        local armed=RT.debugBundle~=nil and RT.active.GetSettingListFromId~=nil
        log('menu data: '..status..' injected='..tostring(injected)..' listWrapper='..tostring(armed)
            ..' bundle='..tostring(RT.debugBundle)..' lists before='..trace.lists)
        RT.tracing=true
        trace.limit=60
        trace.availSince=0
        overlay={buttons={}}
        if not injected then
            if not armed then log('falling back to the DEV 25 overlay buttons') end
            buildOverlay(menu,options,function() return RT.served end,armed)
        end
    end

    local hook=function(name,options,...)
        local isOptions=name=='OptionsMenuLayout' or (type(xhash)=='function' and name==xhash('OptionsMenuLayout'))
        -- Until the data hook is in place (OPTIONS may appear after this file), try on every build;
        -- always before the Settings menu itself, whose PostLoad reads the tab data.
        if isOptions or RT.token~=TOKEN or not RT.complete then
            local success,failure=pcall(installDataHooks,isOptions and 'menu build' or 'build')
            if not success then logOnce('hooks failed '..tostring(failure),'data hooks failed: '..tostring(failure)) end
        end
        if isOptions then
            classIndex=1
            for name in pairs(pending) do pending[name]=nil end
            for name in pairs(pendingText) do pendingText[name]=nil end
        end
        local results=pack(originalBuild(name,options,...))
        if isOptions then
            currentMenu=results[1]
            if transfer then
                log('bot names: transfer resumed in the new Settings menu ('..transfer.pos..'/'..#transfer.values..' values)')
                if not nameTimer(currentMenu) then transfer=nil end
            end
            local useGrid=read(read(_G,'OPTIONS'),'UseDynamicGridInSettings')
            if type(useGrid)=='function' then logOnce('grid','dynamic grid='..tostring(try(useGrid,currentMenu))) end
            local success,failure=pcall(attach,results[1],options)
            if not success then log('Settings hook failed: '..tostring(failure)) end
        end
        return unpackArgs(results,1,results.n)
    end
    write(builder,'BuildRegisteredType',hook)
    RT.hook=hook
    RT.originalBuild=originalBuild
    rawset(_G,'MW4BotfixMenuRuntime',RT)
    local success,failure=pcall(installDataHooks,'startup')
    if not success then log('data hooks failed: '..tostring(failure)) end
    log('installed; open Settings > Debug Options normally')
end)
if not ok then log('setup failed: '..tostring(err)) end
