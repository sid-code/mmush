require("log")
require("events")
require("serialize")

local function save_to_var(var_name, data)
  assert(type(var_name) == "string", "variable names must be strings")
  if data == nil then
    return
  end
  Note(data)
  SetVariable(var_name, serialize.save_simple(data))
end

local function load_from_var(var_name)
  local data = GetVariable(var_name)
  if type(data) ~= "string" then
    return nil
  end

  return loadstring("return " .. data)()
end

-- pass loud = true to display a warning if there is no notify command
local function get_notify_cmd(loud)
  local cmd = GetVariable(lbutils.notifycmd_variable_name)
  if cmd == nil and loud then
    lbutils.logger:warn("You have no notify command set! Use @Glbu setnotify <cmd>@w to set it.")
    return
  end
  return cmd
end



lbutils = {}
lbutils.loglevel = log.level.debug
lbutils.logtheme = log.theme:new{
  all = "@x141LBUTILS: @w$MSG",
  error="@RLBUTILS: @w$MSG",
  fatal="@RLBUTILS: @w$MSG",
}
lbutils.logger = log:new(lbutils.logtheme, lbutils.loglevel)
lbutils.watches = {}
lbutils.watch_variable_name = "mm_lbutils_watches"
lbutils.notifycmd_variable_name = "mm_lbutils_notifycmd"

function lbutils.notify(lbnum, bid, item, level)
  local cmd = get_notify_cmd(true)
  if cmd then
    Execute(cmd .. " Market #" .. lbnum .. " has less than 15 minutes! ("
              .. item .. ", level "  .. level .. ", bid " .. bid .. ")")
  end
end

function lbutils.setwatch(lbnum, watch)
  if watch then
    if lbutils.watches[lbnum] then
      lbutils.logger:note("Already watching market #@C" .. lbnum .. "@w.")
    else
      lbutils.watches[lbnum] = true
      lbutils.logger:note("Watching market #@C" .. lbnum .. "@w.")
    end
  else
    if lbutils.watches[lbnum] then
      lbutils.watches[lbnum] = nil
      lbutils.logger:note("No longer watching market #@C" .. lbnum .. "@w.")
    else
      lbutils.logger:note("Market #@C" .. lbnum .. "@w was not being watched")
    end
  end
end


lbutils.alias = {}
function lbutils.alias.setnotify(name, line, wildcards)
  local notifycmd = wildcards[1]
  SetVariable(lbutils.notifycmd_variable_name, notifycmd)
  lbutils.logger:note("Set notify command to @G" .. notifycmd .. "@w.")
end

function lbutils.alias.watch(name, line, wildcards)
  local number = wildcards[1]
  -- Show the warning if there's no notify command
  get_notify_cmd(true)
  lbutils.setwatch(number, true)
end

function lbutils.alias.unwatch(name, line, wildcards)
  local number = wildcards[1]
  -- Show the warning if there's no notify command
  get_notify_cmd(true)
  lbutils.setwatch(number, false)
end

function lbutils.alias.help(name, line, wildcards)
  lbutils.logger:note("Help for lbid utilities.\n" .. GetPluginInfo(GetPluginID(), 3))
end

function lbutils.alias.show(name, line, wildcards)
  lbutils.logger:note("You are watching the following market listings:")
  for number, _ in pairs(lbutils.watches) do
    lbutils.logger:note("Market #@C" .. number)
  end
end

function lbutils.alias.clear(name, line, wildcards)
  lbutils.watches = {}
  lbutils.logger:note("All watches cleared.")
end

lbutils.trigger = {}
function lbutils.trigger.expiringsoon(name, line, wildcards)
  local amount = wildcards[1]
  local name = wildcards[2]
  local level = wildcards[3]
  local lbnum = wildcards[4]

  if lbutils.watches[lbnum] then
    lbutils.setwatch(lbnum, false)
    lbutils.notify(lbnum, amount, name, level)
  end
end


local geo = globaleventobject
geo:on("install", function()
         lbutils.watches = load_from_var(lbutils.watch_variable_name)
end)
geo:on("close", function()
         save_to_var(lbutils.watch_variable_name, lbutils.watches or {})
end)
