-- The frontend for the maputils library.  Here, the maputils object
-- will be instantiated and functions that aliases can call will be
-- defined.

require("events")
require("maputils")
require("pluginids")

require("wait")

require("gmcphelper")

maputils.frontend = {}

-- Tags to echo for synchronising with the MUD.
maputils.frontend.swbegintag = "{speedwalk begin}"
maputils.frontend.swendtag = "{speedwalk end}"
maputils.frontend.prewaittag = "{speedwalk wait}"

-- Minimum level to log
maputils.frontend.loglevel = log.level.debug

-- This will hold the instance of the maputils class
maputils.frontend.object = nil

-- Information about the character that we need to calculate paths.
maputils.frontend.curlevel = -1
maputils.frontend.curuid = nil

local geo = globaleventobject
function maputils.frontend.init()
  geo:on("install",
         function(event)
           SendNoEcho("protocols gmcp sendchar")
           maputils.frontend.object = maputils:new("Aardwolf.db", "mazes.db")
         end
  )

  geo:on("close",
         function(event)
           maputils.frontend.object:close()
         end
  )

  geo:on("broadcast",
         function(event)
           local id = event.data.id
           local text = event.data.text
           if id == pluginids.mush.gmcphelper then
             if text == "room.info" then
               maputils.frontend.curuid = tostring(gmcp("room.info.num"))
             elseif text == "char.status" then
               maputils.frontend.curlevel = gmcp("char.base.tier") * 10 + gmcp("char.status.level")
             end

           end
         end
  )
end

-- Expects a list of string commands, and returns back a pair:
-- (partial: boolean, commands: string list).
--
-- Partial being true means that the speedwalk cannot be completed due
-- to a maze being in the way.
function maputils.frontend.condense(path)
  local dirs = { n = 1, e = 1, s = 1, w = 1, u = 1, d = 1 }
  local cursw = ""
  local result = {}
  local partial = false

  for _, cmd in pairs(path) do
    local mt = string.match(cmd, "MAZE%((%d+,%d+)%)")
    if mt then
      partial = true
      break
    end
    if dirs[cmd] then
      cursw = cursw .. cmd
    else
      if #cursw > 0 then
        table.insert(result, "run " .. cursw)
        cursw = ""
      end
      table.insert(result, cmd)
    end
  end
  if #cursw > 0 then
    table.insert(result, "run " .. cursw)
  end
  return partial, result
end

function maputils.frontend.runsw(path)
  -- Each element of path is a command to be entered. Each command may
  -- contain semicolons.
  local cmd, subcmd
  for _, cmd in pairs(path) do
    for subcmd in string.gmatch(cmd, "[^;]+") do
      maputils.frontend.object:log("Executing: @Y" .. subcmd .. "@W")
      maputils.frontend.execute(subcmd)
    end
  end

  maputils.frontend.quietexecute("echo " .. maputils.frontend.swendtag)
end

function maputils.frontend.quietexecute(cmd)
  local original_echo_setting = GetOption("display_my_input")
  SetOption ("display_my_input", 0)
  Execute(cmd)
  SetOption ("display_my_input", original_echo_setting)
end

function maputils.frontend.execute(cmd)
  local wait_time = string.match(cmd, "wait%((%d+)%)")
  local maze_target = string.match(cmd, "MAZE%((%d+,%d+)%)")

  if wait_time then
    maputils.frontend.quietexecute("echo " .. maputils.frontend.prewaittag)
    wait.match(maputils.frontend.prewaittag, 10, 4)
    maputils.frontend.object:log("Waiting " .. wait_time .. " seconds.")
    wait.time(tonumber(wait_time))
    return
  end

  if maze_target then
    return
  end

  maputils.frontend.quietexecute(cmd)
end

maputils.frontend.alias = {}

function maputils.frontend.alias.pathto(name, line, wildcards)
  if maputils.frontend.curlevel == -1 then
    maputils.frontend.object:error("I don't know your level. Move or type look.")
    return
  end

  local fromuid, touid
  if name == "pathto" or name == "runto" then
    touid = wildcards[1]
    fromuid = maputils.frontend.curuid

    if fromuid== nil then
      maputils.frontend.object:error("I don't know where you are. Move or type look.")
      return
    end
  elseif name == "pathto2" then
    fromuid = wildcards[1]
    touid = wildcards[2]
  end

  local path = maputils.frontend.object:findpath(fromuid, touid, maputils.frontend.curlevel)
  if path == nil then
    maputils.frontend.object:error("Could not find a path from @C" .. fromuid .. "@W to @C" .. touid .. "@W")
    return
  else
    maputils.frontend.object:note("Path from @C" .. fromuid .. "@W to @C" .. touid .. "@W:")
    maputils.frontend.object:note(table.concat(path, ";"))
  end

  if name == "runto" then
    local partial, realpath = maputils.frontend.condense(path)
    wait.make(function()
        maputils.frontend.runsw(realpath)
        wait.match(maputils.frontend.swendtag, 100, 4)
        if partial then
          maputils.frontend.object:note("Speedwalk not completed due to maze.")
        end
    end)
  end

  -- This needs to be done, otherwise any attached databases remain
  -- locked forever.
  -- TODO: find a better way to manage this.
  maputils.frontend.object:close()
  maputils.frontend.object:opendb()

end

function maputils.frontend.alias.dropcache()
  maputils.frontend.object:dropcaches()
  maputils.frontend.object:log("Dropped caches.")
end
