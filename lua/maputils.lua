-- maputils.
-- provide usable mapping functions because the other one doesn't.
-- Written by Morn, around 22 September 2019
local sqlite3 = require('sqlite3')
require("log")

-- stolen from winklewinkle's plugin
function fixsql(s)
  if s then
    -- surround with ', and ' => ''
    return "'" .. string.gsub(s, "'", "''") .. "'" 
  else
    return "NULL"
  end
end

-- Maputils class
maputils = {}

-- SQL query templates. Note: no semicolons. I want to be able to do
-- janky things like concatenate these without worrying about pesky
-- semicolons.
maputils.sql = {
  roombyuid = 'SELECT * FROM rooms WHERE uid = %s',
  exitsbyuidfrom = 'SELECT fromuid, touid, dir, length(dir) FROM exits WHERE fromuid = %s AND level <= %s AND NOT(touid = "-1")',
  exitsbyuidto = 'SELECT fromuid, touid, dir, length(dir) FROM exits WHERE touid = %s AND (level = NULL or level <= %s)',
  mexitsbyuidfrom = 'SELECT fromuid, touid, "MAZE(" || fromuid || "," || touid || ")" as dir, 0 FROM mazedb.mexits WHERE fromuid = %s',
  mexitsbyuidto = 'SELECT fromuid, touid, "MAZE(" || fromuid || "," || touid || ")" as dir, 0 FROM mazedb.mexits WHERE touid = %s',

  getbounces = 'SELECT data FROM storage WHERE name = \'bounce_recall\' OR name = \'bounce_portal\'',
  getareabyname = "SELECT uid FROM areas WHERE name = %s",
  attachdb = "ATTACH DATABASE %s AS %s",
  detachdb = "DETACH DATABASE %s"
}

-- Constructor a maputils object. Opens a connection to the database
-- specified.
--
-- @param db_path {string} the path to the mapper database.
-- @param maze_db_path {string, optional} the path to the maze exit database.
-- @return {maputils} an instance of maputils
function maputils:new(db_path, maze_db_path)
  local obj = {}
  setmetatable(obj, self)
  self.__index = self

  obj.logger = log:new(
    log.theme:new{
      all = "@GMAPUTILS:@W $MSG",
      warn = "@YMAPUTILS:@W $MSG",
      error = "@RMAPUTILS:@W $MSG",
      fatal = "@RMAPUTILS:@W $MSG"},
    log.level.info)

  obj.db_path = db_path
  obj.maze_db_path = maze_db_path

  obj:opendb()

  obj.roomcache = {}
  obj.pathcache = {}

  obj.bouncerecall = nil
  obj.bounceportal = nil
  obj:readbouncesettings()

  return obj
end

-- Open the MUSHclient mapper database.
function maputils:opendb()
  self.db = assert(sqlite3.open(self.db_path))
end

function maputils:dropcaches()
  self.roomcache = {}
  self.pathcache = {}
end

-- Pass in anything that isn't nil or false to detach it.
function maputils:attachmazedb(detach)
  if self.maze_db_path == nil then
    return
  end

  local query
  if detach then
    query = string.format(
      maputils.sql.detachdb,
      "mazedb")
  else
    query = string.format(
      maputils.sql.attachdb,
      fixsql(self.maze_db_path),
      "mazedb")
  end

  assert(self.db:execute(query))
end

function maputils:log(message, severity)
  self.logger:log(message, severity)
end
 
-- install all the helper log functions like "note" "debug" etc
log.install(maputils)

-- Wrapper around sqlite3.db.nrows. Sometimes it doesn't exist, and we need to
-- fall back on sqlite3.db.rows.
function maputils:dbnrows(query)
  if self.db.nrows == nil then
    return self.db:rows(query)
  else
    return self.db:nrows(query)
  end
end

-- Check if a string is an area name. This is used by the gq bot to
-- disambiguate between room names and area names.
function maputils:isarea(areaname)
  local query = string.format(maputils.sql.getareabyname, fixsql(areaname))
  for row in assert(self:dbnrows(query)) do
    return true
  end
  return false
end

-- Read the bounceportal and bouncerecall settings from the mapper
-- database. They seem to be stored in the "storage" table, under the
-- keys "bounce_recall" and "bounce_portal". They are stored as lua
-- code that initializes the object that represents the data. In this
-- case, it's a table with two keys, "uid" and "dir".
function maputils:readbouncesettings()
  -- This creates global variables. I couldn't get it to work with
  -- only local variables. I delete them near the end of this
  -- function.
  for row in assert(self:dbnrows(maputils.sql.getbounces)) do
    loadstring(row.data)()
  end

  if bounce_recall == nil or bounce_recall.uid == nil or bounce_recall.dir == nil then
    self.bouncerecall = nil
    self:debug("No bouncerecall set in mapper db.")
  else
    self.bouncerecall = bounce_recall
    self:debug("bouncerecall initialized to " .. self.bouncerecall.dir .. ".")
  end

  if bounce_portal == nil or bounce_portal.uid == nil or bounce_portal.dir == nil then
    self.bounceportal = nil
    self:debug("No bouncerecall set in mapper db.")
  else
    self.bounceportal = bounce_portal
    self:debug("bounceportal initialized to " .. self.bounceportal.dir .. ".")
  end


  -- delete the global variables....
  bounce_recall = nil
  bounce_portal = nil

  self.pathcache = {}
end

-- Get a room with the specified uid.
-- @param uid {string} the uid of the room
-- @return a row of the database representing a room
function maputils:getroom(uid)
  local query = string.format(maputils.sql.roombyuid, fixsql(uid))
  local attempt = self.roomcache[uid]
  if attempt then
    return attempt
  end

  for row in assert(self:dbnrows(query)) do
    self.roomcache[uid] = row
    return row
  end
end

-- Poor man's enum for specifying the direction in which to search for
-- edges in the directed graph.
local exitdir = {
  to = 0,
  from = 1
}

-- Get rooms "nearby" the room with the specified uid. Here, "nearby"
-- can mean two things, depending on the `direction` parameter. If it
-- is exitdir.to, then we get rooms that have exits to our specified
-- room. If it is exitdir.from, we get rooms to which our specified
-- has exits. These rooms go into the first returned list.
--
-- If the direction is "to," then it is possible that a portal leads
-- to the specified room. If this is the case, the second return list
-- will contain a list of these portal commands.
--
-- @param uid {string} the uid of the room
-- @param direction {exitdir} the direction in which to search
-- @return a list of {room, direction}, and a list of portal commands
function maputils:getnearbyrooms(uid, direction, level)
  if direction == nil then direction = direction.to end
  -- First, we select the correct query template depending on the
  -- direction of the search.
  local querytemplate
  if direction == exitdir.to then
    querytemplate = maputils.sql.exitsbyuidto
    if self.maze_db_path then
      querytemplate = querytemplate .. " UNION " .. maputils.sql.mexitsbyuidto
    end
  elseif direction == exitdir.from then
    querytemplate = maputils.sql.exitsbyuidfrom
    if self.maze_db_path then
      querytemplate = querytemplate .. " UNION " .. maputils.sql.mexitsbyuidfrom
    end
  end

  querytemplate = querytemplate .. " ORDER BY length(dir) DESC"

  -- Perform the actual query and record the results.
  local query
  local sqluid = fixsql(uid)
  local sqllevel = fixsql(tostring(level))
  if self.maze_db_path then
    query = string.format(querytemplate, sqluid, sqllevel, sqluid)
  else
    query = string.format(querytemplate, sqluid, sqllevel)
  end

  if self.maze_db_path then
    self:attachmazedb()
  end

  local nearbyrooms = {}
  local portals = {}
  for row in assert(self:dbnrows(query)) do
    local otheruid
    if direction == exitdir.to then
      otheruid = row.fromuid
    elseif direction == exitdir.from then
      otheruid = row.touid
    end
    if otheruid == '*' then
      table.insert(portals, row.dir)
    else
      local room = self:getroom(otheruid)
      if room then
        table.insert(nearbyrooms, {room, row.dir})
      end
    end
  end

  if self.maze_db_path then
    self:attachmazedb("detach")
  end

  return nearbyrooms, portals
end

-- function to make a node in the search tree
local function makenode(touid, dir, parent)
  return {
    touid = touid,
    dir = dir,
    parent = parent
  }
end

-- function to extract path from node in search tree
local function getpath(node, reversed)
  local path = {}
  local conductor = node
  while conductor ~= nil do
    if reversed then
      table.insert(path, 1, conductor.dir)
    else
      table.insert(path, conductor.dir)
    end
    conductor = conductor.parent
  end
  return path
end

function maputils:findpath(fromuid, touid, level)
  -- Set of visited uids
  local visited = {}

  -- First, we need to get to a room that can be exited through a
  -- portal. If not, we need to create a pre-path that gets us to a
  -- suitable (portal-able) room.
  local prepath
  local fromroom = self:getroom(fromuid)
  if fromroom.noportal ~= 1 then
    prepath = {}
    -- do nothing, we're good!
  elseif fromroom.norecall ~= 1 and self.bouncerecall then
    -- it is noportal, but not norecall. Easy, we can just bouncerecall
    prepath = {self.bouncerecall.dir}
  else
    -- norecall and noportal. GET TO THE CHOPPA
    prepath = self:GETTODACHOPPA(fromuid, level)
    if prepath == nil then
      return nil, nil
    end
  end


  local found = false

  -- Perform BFS from touid, traversing the graph in the
  -- reverse-directed order. The aim is to find a portal room
  -- (represented by * in the exits table), or the fromuid room.
  local path, portal =
    (function ()
        -- List of searchnodes to explore
        local stack = {makenode(touid, nil, nil)}

        while #stack > 0 do
          local top = table.remove(stack, #stack)
          local topuid = top.touid
          if visited[topuid] then goto continue end -- yuck
          
          if topuid == fromuid then
            return top, nil
          end
          
          local roomsfrom, portals = self:getnearbyrooms(topuid, exitdir.to, level)
          if #portals > 0 then
            return top, portals[1]
          end
          
          for _, connection in pairs(roomsfrom) do
            local fromuid = connection[1].uid
            local dir = connection[2]
            table.insert(stack, 1, makenode(fromuid, dir, top))
          end
          
          visited[topuid] = true
          ::continue::
        end

        return nil, nil
    end)()

  if path == nil then
    return nil
  end

  -- Now, we build up the path
  local exitpath = {}

  if portal ~= nil then
    for i = 1, #prepath do
      table.insert(exitpath, prepath[i])
    end

    table.insert(exitpath, portal)
  end

  local pathtodest = getpath(path)
  for i = 1, #pathtodest do
    table.insert(exitpath, pathtodest[i])
  end

  return exitpath
end

function maputils:GETTODACHOPPA(fromuid, level)
  -- We do a bfs to a portallable room.  This is code duplication,
  -- but I prefer that to creating convoluted abstractions.
  local stack = {makenode(fromuid, nil, nil)}
  -- set of visited nodes
  local visited = {}

  while #stack > 0 do
    local top = table.remove(stack, #stack)
    local topuid = top.touid
    if visited[topuid] then goto continue end

    local toproom = self:getroom(topuid)
    if toproom.norecall ~= 1 and self.bouncerecall.dir then
      -- pass 1 to reverse path
      local path = getpath(top, 1)
      table.insert(path, self.bouncerecall.dir)
      return path
    elseif toproom.noportal ~= 1 then
      return getpath(top, 1)
    end

    local roomsto, _ = self:getnearbyrooms(top.touid, exitdir.from)
    for _, connection in pairs(roomsto) do
      local touid = connection[1].uid
      local dir = connection[2]
      table.insert(stack, 1, makenode(touid, dir, top))
    end

    visited[topuid] = true
    ::continue::
  end

  return nil
end

-- Close the mapper database.
function maputils:close()
  self.db:close()
end
