require("gmcphelper")
require("events")
require("gmcpevents")
require("log")

move_queue = {}

move_queue.alias = {}

move_queue.cur_room = nil

move_queue.logger = log:new(
  log.theme:new({
    all = "@Gmove_queue:@x123 $MSG",
    warn = "@Ymove_queue:@x123 $MSG",
    error = "@Rmove_queue:@x123 $MSG",
    fatal = "@Rmove_queue:@x123 $MSG",
  }),
  log.level.info
)

function move_queue.init()
  local geo = globaleventobject
  geo:on("aard_gmcp_move_room", function()
    move_queue.cur_room = gmcp("room.info.num")
  end)
end

local function mq_get(mq_name)
  return GetVariable("mq" .. mq_name)
end

local function mq_set(mq_name, new_str)
  return SetVariable("mq" .. mq_name, new_str)
end

local function mq_get_command(room)
  return "cqs move mapper goto " .. room
end

local function mq_add_roomid(mq_name, room)
  local queue_str = mq_get(mq_name)
  if queue_str == nil then
    mq_set(mq_name, "")
    queue_str = ""
  end

  queue_str = queue_str .. "," .. room

  mq_set(mq_name, queue_str)
end

function move_queue.alias.delete(name, line, wildcards)
  local mq_name = wildcards[1]
  DeleteVariable("mq" .. mq_name)

  move_queue.logger:note("Move queue " .. mq_name .. " deleted.")
end

function move_queue.alias.add(name, line, wildcards)
  if move_queue.cur_room == nil then
    move_queue.logger:note("Error: I don't know where you are. Try moving or typing 'look'.")
    return
  end

  local mq_name = wildcards[1]
  local queue_str = mq_get(mq_name)

  mq_add_roomid(mq_name, tostring(move_queue.cur_room))

  move_queue.logger:note("Added room " .. move_queue.cur_room .. " to move queue " .. mq_name .. ".")
end

local function mq_get_all()
  local i = 0
  local vl = GetVariableList()
  local nx, t, k = pairs(vl)
  return function()
    k, v = nx(t, k)
    if k == nil then
      return
    end
    -- strip out the mq prefix
    return string.gsub(k, "^mq", ""), v
  end
end

function move_queue.alias.list(name, line, wildcards)
  for k in mq_get_all() do
    move_queue.logger:note(k)
  end
end

-- Use the move
local function mq_use(room_ids, start_room) end

function move_queue.alias.use(name, line, wildcards)
  local mq_name = wildcards[1]
  local room_ids = mq_get(mq_name)

  if room_ids == nil then
    move_queue.logger:error("Move queue " .. mq_name .. " does not exist.")
    return
  end

  Execute("cqs move flush")

  for room_id in string.gmatch(room_ids, "%d+") do
    Execute(mq_get_command(room_id))
  end

  move_queue.logger:note("Loaded up move queue " .. mq_name .. ".")
end

function move_queue.alias.use_partial(name, line, wildcards)
  local cr = move_queue.cur_room
end

function move_queue.alias.migrate(name, line, wildcards)
  for k, v in mq_get_all() do
    move_queue.logger:note("Migrating " .. k)
    v = string.gsub(v, "\n", ",")
    v = string.gsub(v, "^%s+,", "")
    v = string.gsub(v, "cqs move mapper goto ", "")
    mq_set(k, v)
  end
end
