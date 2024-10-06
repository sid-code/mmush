binsearch = {}
-- cmp should return 1 if its first argument is greater than its
-- second, -1 if the second is greater than the first, and 0 if they
-- are equal.
function binsearch.insert_sorted(tbl, nv, cmp)
  local low = 1
  local high = #tbl

  if high == 0 or cmp(nv, tbl[high]) > 0 then
    table.insert(tbl, high + 1, nv)
    return
  end

  while low < high do
    local mid = math.floor((low + high) / 2)
    local cmpr = cmp(tbl[mid], nv)
    if cmpr > 0 then
      high = mid
    elseif cmpr < 0 then
      low = mid
    else
      table.insert(tbl, mid, nv)
      return
    end
  end
  table.insert(tbl, low, nv)
end
