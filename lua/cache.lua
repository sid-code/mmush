-- Cache class
cache = {}
function cache:new()
  local obj = {}
  setmetatable(obj, self)
  self.__index = self

  obj:clear()
  obj:resetstats()

  return obj
end

function cache:lookup(key)
  local attempt = self.data[key]
  if attempt == nil then
    self.stats.misses = self.stats.misses + 1
    return false, nil
  end

  self.stats.hits = self.stats.hits + 1
  return true, attempt
end

function cache:lookupor(key, orfun)
  local found, val = self:lookup(key)
  if found then
    return val
  else
    return orfun(key)
  end
end

function cache:insert(key, val)
  self.data[key] = val
  return val
end

function cache:clear()
  self.data = {}
end
function cache:resetstats()
  self.stats = { hits = 0, misses = 0 }
end

function cache:getstats()
  return self.stats.hits, self.stats.misses
end
