require("gmcphelper")
require("events")
require("gmcpevents")
require("log")
require("wait")

local geo = globaleventobject
move_queue = {}

move_queue.alias = {}

move_queue.cur_room = nil

-- TODO: make this more general
local log_color = "@x123"
local highlight_color = "@Y"

local function highlight(str)
  return highlight_color .. str .. log_color
end

move_queue.logger = log:new(
  log.theme:new({
    all = "@Gmove_queue:" .. log_color .. " $MSG",
    warn = "@Ymove_queue:" .. log_color .. " $MSG",
    error = "@Rmove_queue:" .. log_color .. " $MSG",
    fatal = "@Rmove_queue:" .. log_color .. " $MSG",
  }),
  log.level.info
)

function move_queue.init()
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

-- @param room_ids {function} an iterator that returns successive string room IDs
-- @param start_room {string|nil} an optional start room
local function mq_use(room_ids, start_room)
  local adding = false
  if start_room == nil then
    adding = true
  end

  Execute("cqs move flush")

  for room_id in room_ids do
    if adding then
      Execute(mq_get_command(room_id))
    end

    if tostring(start_room) == room_id then
      adding = true
    end
  end
end

function move_queue.alias.use(name, line, wildcards)
  local mq_name = wildcards[1]
  local room_ids = mq_get(mq_name)

  if room_ids == nil then
    move_queue.logger:error("Move queue " .. highlight(mq_name) .. " does not exist.")
    return
  end

  local start_room
  if name == "mq_use_part" then
    start_room = move_queue.cur_room
    if start_room == nil then
      move_queue.logger:error(
        "Cannot partially load move queue because current location is unknown. Loading entire queue."
      )
    else
      move_queue.logger:note(
        "Attempting to load " .. highlight(mq_name) .. " partially, starting at " .. highlight(start_room) .. "."
      )
    end
  else
    start_room = nil
  end

  mq_use(string.gmatch(room_ids, "%d+"), start_room)
  move_queue.logger:note("Loaded up move queue " .. highlight(mq_name) .. ".")
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

local function mq_record(mq_name)
  if move_queue.current_recording ~= nil then
    move_queue.logger:error("You are already recording a move queue.")
    move_queue.logger:error(
      "Use " .. highlight("mq record end") .. " or " .. highlight("mq record abort") .. " before recording a new one."
    )
  end

  move_queue.current_recording = {}

  local rec = move_queue.current_recording
  rec.name = mq_name
  rec.rooms = {}
  rec.index = 1

  local function record_room()
    local room_id = gmcp("room.info.num")
    print(room_id, rec.name)
    if rec.rooms[rec.index - 1] == room_id then
      move_queue.logger:note(
        "Not adding duplicate room " .. highlight(room_id) .. " to move queue " .. highlight(rec.name) .. "."
      )
      return
    end

    move_queue.logger:note("Adding " .. highlight(room_id) .. " to move queue " .. highlight(rec.name) .. ".")
    rec.rooms[rec.index] = room_id
    rec.index = rec.index + 1
  end

  local function deregister_handlers()
    geo:deregister("aard_gmcp_move_room", record_room)
    geo:deregister("mq_record_end", end_recording)
    geo:deregister("mq_record_abort", abort_recording)
  end

  local function save_recording()
    move_queue.logger:note("Saving recording of move queue " .. highlight(rec.name) .. ".")
    mq_set(rec.name, table.concat(rec.rooms, ","))
  end

  local function end_recording()
    deregister_handlers()
    save_recording()
    move_queue.current_recording = nil
  end
  local function abort_recording()
    move_queue.logger:note("Aborting recording!")
    deregister_handlers()
    move_queue.current_recording = nil
  end

  geo:on("aard_gmcp_move_room", record_room)
  geo:on("mq_record_end", end_recording)
  geo:on("mq_record_abort", abort_recording)
end

function move_queue.alias.record(name, line, wildcards)
  local mq_name = wildcards[1]

  mq_record(mq_name)
end

function move_queue.alias.record_event(name, line, wildcards)
  geo:trigger(event:new(name))
end
