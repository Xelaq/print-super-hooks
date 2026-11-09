# print (super hooks) #

A replacement for the standard hook library in GMOD, built on top of srlion's hook library.

Optimized and extended by the community — **print (super koders)!**

## Additional Features ##

Supports an object as the identifier; if the object is deleted, the hook is deleted as well. The object itself is returned as the first argument of the function (see the example below).
```lua
  hook.Add("Think", Entity(1), function(self)
    print(self) --Entity(1)
  end)
```

## Benchmarks: ##

**Test conditions:** 1000 hooks registered, 1000 calls.

| Library                      |      Run 1 |      Run 2 |      Run 3 |
| :--------------------------- | ---------: | ---------: | ---------: |
| Standard GMOD `hook` library |   27.46 ms |   27.42 ms |   27.49 ms |
| srlion's hook library        |   12.42 ms |   12.58 ms |   12.51 ms |
| **Super Hooks**              | **0.93 ms** | **0.94 ms** | **0.92 ms** |

> **~29× faster** than the stock library, **~13× faster** than srlion's original.

The following code was used for the Benchmarks:
```lua
  local hookCount = 1000
  local callsPerRun = 1000
  local repeats = 3
  local warmupCalls = 200

  local event = "HookSpeedTest_" .. tostring({})
  local call = hook.Call
  local hits = 0

  local callbacks = {
      function(a) hits = hits + a end,
      function(_, b) hits = b + hits end,
      function(_, _, _, d) hits = hits + d end,
  }

  local function measure(calls)
      local before = hits
      local start = SysTime()

      for i = 1, calls do
          call(event, nil, 1, 1, nil, 1)
      end

      local elapsed = (SysTime() - start) * 1000
      assert(hits - before == calls * hookCount, "Not all hooks were executed")
      return elapsed
  end

  if jit then jit.off(measure) end

  local ok, err = xpcall(function()
      for i = 1, hookCount do
          hook.Add(event, tostring(i), callbacks[(i - 1) % #callbacks + 1])
      end

      measure(warmupCalls)

      local times = {}
      for i = 1, repeats do
          times[i] = measure(callsPerRun)
          print(string.format("Run %d — %.2f ms", i, times[i]))
      end

      table.sort(times)
      local middle = (repeats + 1) / 2
      local median = (times[math.floor(middle)] + times[math.ceil(middle)]) / 2

      print(string.format(
          "%d calls × %d hooks, %d repetitions — median %.2f ms",
          callsPerRun, hookCount, repeats, median
      ))
  end, debug.traceback)

  for i = 1, hookCount do
      hook.Remove(event, tostring(i))
  end

  if not ok then error(err, 0) end

```
