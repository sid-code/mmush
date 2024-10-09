require("gmcphelper")
require("pluginids")
require("events")
require("serialize")

local function register_gmcp_events()
  local geo = globaleventobject
  geo:on("broadcast", function(ev)
    local id = ev.data.id
    local text = ev.data.text
    if id == pluginids.mush.gmcphelper then
      if text == "comm.repop" then
        geo:trigger(event:new("aard_gmcp_repop", nil))
      end
      if text == "room.info" then
        geo:trigger(event:new("aard_gmcp_move_room", nil))
      end
    end
  end)
end

register_gmcp_events()
