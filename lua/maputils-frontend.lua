-- The frontend for the maputils library.  Here, the maputils object
-- will be instantiated and functions that aliases can call will be
-- defined.

require("events")
require("maputils")
require("pluginids")

require("wait")

require("gmcphelper")

local mu
local geo = globaleventobject

local loglevel = log.level.debug

geo:on("install",
       function(event)
         mu = maputils:new("Aardwolf.db", "mazes.db")
         mu:setlevel(gmcp("char.base.tier") * 10 + gmcp("char.status.level"))
         mu.curuid = gmcp("room.info.num")
       end
)

geo:on("close",
       function(event)
         mu:close()
       end
)

geo:on("broadcast",
       function(event)
         local id = event.data.id
         local text = event.data.text
         if id == pluginids.gmcphelper then
           if text == "room.info" then
             mu.curuid = gmcp("room.info.num")
           end
         end
       end
)

function condense(path)
  local dirs = { n = 1, e = 1, s = 1, w = 1, u = 1, d = 1 }
  local cursw = ""
  local result = {}
  for _, cmd in pairs(path) do
    if cmd == "MAZE" then
      mu:note("@YRun will abort at beginning of maze!@W")
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
  return result
end

function pathto(name, line, wildcards)
  local fromuid, touid
  if name == "pathto" or name == "runto" then
    fromuid = mu.curuid
    touid = wildcards[1]

    if fromuid == nil then
      mu:error("I don't know where you are. Move or type look.")
      return
    end
  elseif name == "pathto2" then
    fromuid = wildcards[1]
    touid = wildcards[2]
  end

  local path = mu:findpath(fromuid, touid)
  if path == nil then
    mu:error("Could not find a path from @C" .. fromuid .. "@W to @C" .. touid .. "@W")
    return
  else
    mu:note("Path from @C" .. fromuid .. "@W to @C" .. touid .. "@W:")
    mu:note(table.concat(path, ";"))
  end

  if name == "runto" then
    local realpath = condense(path)
    Execute(table.concat(realpath, ';'))
  end

end
