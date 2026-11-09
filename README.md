# print (super hooks) #

A replacement for the standard hook library in GMOD, built on top of srlion's hook library.

Optimized and extended by the community — print (super koders)!

Supports an identifier in the form of an object; if the object is deleted, the hook is deleted as well (see example below):
```lua
  hook.Add("Think", Entity(1), function(self)
    print(self)
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


