
log = {}
log.level = {
  fatal = 0,
  error = 1,
  warn = 2,
  note = 3,
  debug = 4
}

log.driver = "mush"

function log:new(theme, level)
  local obj = {}
  setmetatable(obj, self)
  self.__index = self

  obj.theme = theme or error("invalid argument #1 to log:new, expected a log.theme")
  obj.level = level or log.level.debug

  return obj
end

function log:log(message, severity)
  if severity == nil then
    severity = log.level.debug
  end
  if severity <= self.level then
    local full_message = self:preparemessage(message, severity)
    log.drivers[log.driver].print(full_message)
  end
end

function log:fatal(message)
  self:log(message, log.level.fatal)
end
function log:error(message)
  self:log(message, log.level.error)
end
function log:warn(message)
  self:log(message, log.level.error)
end
function log:note(message)
  self:log(message, log.level.note)
end
function log:debug(message)
  self:log(message, log.level.error)
end

function log:preparemessage(message, severity)
  local pattern = self.theme:getpatternfor(severity)
  return string.gsub(pattern, "$MSG", message)
end

-- Static methods

function log.install(obj)
  function obj:debug(message)
    self:log(message, log.level.debug)
  end
  function obj:note(message)
    self:log(message, log.level.note)
  end
  function obj:warn(message)
    self:log(message, log.level.warn)
  end
  function obj:error(message)
    self:log(message, log.level.error)
  end
  function obj:fatal(message)
    self:log(message, log.level.fatal)
  end
end


-- Drivers (one per client).
--
-- Add an entry to log.drivers and define a print function under it,
-- just like the mushclient example below.

log.drivers = {}
log.drivers.mush = {}
log.drivers.mush.initialized = false
function log.drivers.mush.print(message)
  if not log.drivers.mush.initialized then
    dofile(GetInfo(60) .. "aardwolf_colors.lua")
    log.drivers.mush.initialized = true
  end

  AnsiNote(stylesToANSI(ColoursToStyles(message)))
end

log.theme = {}

-- A log theme maps severity to a pattern. The pattern looks like
-- "blahblah: $MSG" The special severity "all" can be used to set a
-- default for any severity not specified. If this is not provided,
-- the template "$MSG" is used.
-- 
-- For example:
--
-- local theme = log.theme:new{all = "LOG: $MSG", fatal = "@RFATAL: @W$MSG"}
function log.theme:new(cases)
  local obj = {}
  setmetatable(obj, self)
  self.__index = self

  obj.cases = {}
  for severity, value in pairs(cases) do
    if severity == "all" then
      obj.cases.all = value
    elseif log.level[severity] then
      obj.cases[log.level[severity]] = value
    else
      error("log.theme.new: invalid severity " .. severity)
    end
  end
  if obj.cases.all == nil then
    obj.cases.all = "$MSG"
  end
  return obj
end

function log.theme:getpatternfor(severity)
  return self.cases[severity] or self.cases.all
end
