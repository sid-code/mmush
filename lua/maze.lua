-- Originally from Trachx's maze solver

require("gmcphelper")
require("log")
require("pluginids")
require("events")
require("gmcpevents")

maze_solver = {}
maze_solver.alias = {}

geo = globaleventobject
function maze_solver.init()
  maze_solver.logger = log:new(
    log.theme:new({
      all = "@x172MAZE:@w $MSG",
      error = "@x172MAZE @RERROR:@w $MSG",
      fatal = "@x172MAZE @rFATAL:@w $MSG",
    }),
    log.level.debug
  )

  maze_solver.base_area = ""

  maze_solver.room_table = {}

  maze_solver.lastroom = ""
  maze_solver.lastmove = ""
  maze_solver.enable_map = false

  geo:on("install", function()
    maze_solver.alias.help()
  end)

  geo:on("broadcast", function(event)
    maze_solver.broadcast_handler(event.msg, event.id, event.name, event.text)
  end)

  geo:on("aard_gmcp_repop", function()
    local tt = gmcp("room.info")
    local removed = false
    if tt["zone"] then
      for i = #maze_solver.room_table, 1, -1 do
        if maze_solver.room_table[i].area == tt.zone then
          table.remove(maze_solver.room_table, i)
          removed = true
        end
      end

      if removed then
        maze_solver.logger:note("Some rooms were removed due to repop in area " .. tt.zone)
      end
    end
  end)

  geo:on("aard_gmcp_move_room", function()
    if not maze_solver.enable_map then
      return
    end

    local tt = gmcp("room.info")
    local thisroom = tt.num

    maze_solver.enable_map = false
    local roomIsMapped = false

    for i, room in ipairs(maze_solver.room_table) do
      -- add exit in previous room
      if room.num == maze_solver.lastroom then
        room.exits[maze_solver.lastmove] = thisroom
      end
      -- check whether curren room is in table
      if room.num == thisroom then
        roomIsMapped = true
      end
    end

    if not roomIsMapped then
      maze_solver.add_room(tt)
    end
  end)
end

function maze_solver.broadcast_handler(msg, id, name, text)
  -- if repop occured - remove rooms from repop area
  if id == pluginids.mush.gmcphelper and text == "comm.repop" then
  end

  if id == pluginids.mush.gmcphelper and text == "room.info" and maze_solver.enable_map then
  end
end

function maze_solver.alias.next_room_dir(name, line, wildcards)
  dir = wildcards.direction
  local tt = gmcp("room.info")

  maze_solver.logger:note("Try to go " .. dir)
  maze_solver.lastroom = tt.num
  maze_solver.lastmove = dir
  maze_solver.enable_map = true
  Send(dir)
end

function maze_solver.alias.next_room()
  local ok, tt = pcall(function()
    return gmcp("room.info")
  end)
  if not ok then
    maze_solver.logger:error(tt)
    return
  end

  if tt["zone"] then
    thisroom = tt.num

    local done = false

    -- find this room and check whethere there are unmapped exits
    local roomInTable = false
    for i, room in ipairs(maze_solver.room_table) do
      if room.num == thisroom and room.area == tt.zone then
        for k, v in pairs(room.exits) do
          if v == "-1" then
            maze_solver.lastroom = thisroom
            maze_solver.lastmove = k
            maze_solver.enable_map = true
            Send(k)
            done = true
            break
          end
        end
        roomInTable = true
      end -- if this room
    end -- for

    -- there were no unmapped exits in current room - move to next room with unmapped exits
    if roomInTable == false then
      maze_solver.add_room(tt)
    elseif done == false then
      maze_solver.logger:note("Room " .. thisroom .. " is fully mapped, trying to go to first unmapped room")

      for i, room in ipairs(maze_solver.room_table) do
        if room.area == tt.zone then
          for k, v in pairs(room.exits) do
            if v == "-1" then
              path = maze_solver.find_path_from_to(thisroom, room.num)
              maze_solver.logger:note("Trying " .. room.num .. " path " .. path)
              if not (path == "") then
                Send("run " .. path)
                done = true
                break
              end
            end
          end -- for exits in room
        end
        if done == true then
          break
        end
      end -- for
    end
  end -- tt['zone']
end

function maze_solver.alias.dump_db()
  require("sqlite3")
  local db_path = GetInfo(66) .. "mazes.db"
  local db = assert(sqlite3.open(db_path))

  local result = assert(db:execute([[
CREATE TABLE IF NOT EXISTS mexits (fromuid TEXT, touid TEXT, UNIQUE(fromuid, touid));
]]))

  if result ~= 0 then
    maze_solver.logger:fatal("ERROR creating table: " .. db:errmsg())
    db:close()
    return
  end

  local stmt = "BEGIN TRANSACTION;\n"

  for i, room in ipairs(maze_solver.room_table) do
    -- direction doesn't matter
    for _, touid in pairs(room.exits) do
      if tostring(touid) == "-1" then
        maze_solver.logger:warn("Refusing to dump exit ", room.num, touid)
      else
        stmt = stmt .. string.format("INSERT OR IGNORE INTO mexits VALUES ('%s', '%s');\n", room.num, touid)
      end
    end
  end
  stmt = stmt .. "COMMIT;\n"
  --print(stmt)
  local result = assert(db:execute(stmt))
  if result ~= 0 then
    maze_solver.logger:fatal("ERROR adding exits " .. db:errmsg())
    db:close()
    return
  end

  maze_solver.logger:note("Successfully dumped maze to database.")
  db:close()
end

function maze_solver.alias.dump()
  maze_solver.logger:note("Rooms in maze solver tables:")
  for i, room in ipairs(maze_solver.room_table) do
    x = "Room: " .. room.num .. "  " .. room.area .. ", " .. room.name
    for k, v in pairs(room.exits) do
      x = x .. "   " .. k .. "->" .. v
    end

    maze_solver.logger:note(x)
  end
end

function maze_solver.alias.help()
  maze_solver.logger:note(" " .. "---------------------------------------------------------------------------- ")
  maze_solver.logger:note(" " .. "Maze solver by Trachx *experimental*                                ver 1.01 ")
  maze_solver.logger:note(" " .. "---------------------------------------------------------------------------- ")
  maze_solver.logger:note(" " .. "  #maze_help       - this info                                               ")
  maze_solver.logger:note(" " .. "  #maze            - clear Maze Solver tables                                ")
  maze_solver.logger:note(" " .. "  #maze_dump       - display rooms visited so far and exits                  ")
  maze_solver.logger:note(" " .. "  #maze_dump_db    - dump the current maze topology to mazes.db              ")
  maze_solver.logger:note(" " .. "  #maze_next       - try to go to next unmapped room                         ")
  maze_solver.logger:note(" " .. "  #maze_goto <num> - go to room number <num>, use #maze_dump to get <num>    ")
  maze_solver.logger:note(" " .. "  #maze_next_dir <e|s|w|u|d|n> - go into specified direction instead next    ")
  maze_solver.logger:note(" " .. "  How to solve maze: type #maze in first maze room, then use #maze_next      ")
  maze_solver.logger:note(" " .. "  till you map whole maze or use #maze_next_dir if you want to map desired   ")
  maze_solver.logger:note(" " .. "  exit. Sometimes you need to use #maze_goto <room> if you won't be taken    ")
  maze_solver.logger:note(" " .. "  there automatically. Best start just after repop to have enough time to    ")
  maze_solver.logger:note(" " .. "  map maze. While you stay in area repops are detected and clear maze table. ")

  maze_solver.logger:note(" " .. "---------------------------------------------------------------------------- ")
end

function maze_solver.alias.start()
  local tt = gmcp("room.info")
  if tt["zone"] then
    maze_solver.room_table = {}
    maze_solver.add_room(tt)
  end
end

function maze_solver.add_room(tt)
  maze_solver.base_area = tt.zone
  maze_solver.lastroom = tt.num
  exits = tt.exits
  maze_solver.logger:note(
    "New room in area = "
      .. maze_solver.base_area
      .. ", current room: "
      .. maze_solver.lastroom
      .. " details: "
      .. tt.details
  )

  for k, v in pairs(exits) do
    maze_solver.logger:note("area = " .. k .. " v = " .. v)
  end

  troom = {}
  troom.num = tt.num
  troom.exits = exits
  troom.area = tt.zone
  troom.name = tt.name

  table.insert(maze_solver.room_table, troom)
end

function maze_solver.alias.repopsimulate()
  return ""
end

local visited = ""

function maze_solver.alias.goto_room(name, line, wildcards)
  maze_solver.logger:note(wildcards.roomid)
  visited = "-1"
  local tt = gmcp("room.info")
  if tt["zone"] then
    thisroom = tt.num
    if thisroom == wildcards.roomid then
      maze_solver.logger:note("But you are in room id : " .. thisroom)
      return
    end

    path = maze_solver.find_path_from_to(thisroom, wildcards.roomid)
    maze_solver.logger:note("Executing path : " .. path)
    if not (path == "") then
      Send("run " .. path)
    end
  end
end

function maze_solver.find_path_from_to(from, to)
  visited = visited .. "," .. from

  local path = ""

  for i, room in ipairs(maze_solver.room_table) do
    -- find room "from" and check its exits
    if room.num == from then
      -- first check whether one of exits leads directly to required room
      for k, v in pairs(room.exits) do
        if v == to then
          return k
        end
      end

      -- check first room not visited so far
      for k, v in pairs(room.exits) do
        if not string.find(visited, v) then
          path = maze_solver.find_path_from_to(v, to)
          maze_solver.logger:note("Path returned : " .. path)
          if not (path == "") then
            return k .. path
          end
        end
      end

      break
    end -- num == from
  end -- for i,room

  return ""
end
