-- An event system for MUSHclient to replace the weird mess of
-- callbacks.


eventtarget = {}

function eventtarget:new()
  local obj = {}
  setmetatable(obj, self)
  self.__index = self

  obj.handlers = {}
  return obj
end

function eventtarget:on(etype, handler)
  if not self.handlers[etype] then
    self.handlers[etype] = {}
  end
  
  table.insert(self.handlers[etype], handler)
end

function eventtarget:deregister(etype, handlertoremove)
  if not self.handlers[etype] then
    return
  end
  local handlers = self.handlers[etype]
  local indextodelete = -1
  for i, handler in pairs(handlers) do
    if handler == handlertoremove then
      indextodelete = i
      break
    end
  end
  if indextodelete > -1 then
    return table.remove(handlers, indextodelete)
  end
end

function eventtarget:trigger(event)
  local etype = event.etype
  if not self.handlers[etype] then
    return
  end

  for _, fn in pairs(self.handlers[etype]) do
    -- prevent direct modification of the event object
    local eventcopy = event:copy()
    fn(eventcopy)
  end
end

event = {}
function event:new(etype, data)
  local obj = {}
  setmetatable(obj, self)
  self.__index = self

  obj.etype = etype
  obj.data = data
  return obj
end

-- shallow copy
function event:copy()
  return event:new(self.etype, self.data)
end

-- global event object
globaleventobject = eventtarget:new()

function OnPluginInstall()
  local e = event:new("install", {})
  globaleventobject:trigger(e)
end
function OnPluginConnect()
  local e = event:new("connect", {})
  globaleventobject:trigger(e)
end
function OnPluginClose()
  local e = event:new("close", {})
  globaleventobject:trigger(e)
end
function OnPluginDisable()
  local e = event:new("disable", {})
  globaleventobject:trigger(e)
end

function OnPluginBroadcast(msg, id, name, text)
  local data = {
    msg = msg,
    name = name,
    id = id,
    text = text
  }
  local e = event:new("broadcast", data)
  globaleventobject:trigger(e)
end


