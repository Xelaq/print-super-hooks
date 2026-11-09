# print (super hooks) #

A replacement for the standard hook library in GMOD, built on top of srlion's hook library.
Optimized and extended by the community — 
## print (super coders)! ##

Supports an identifier in the form of an object; if the object is deleted, the hook is deleted as well (see example below):
```lua
  hook.Add("Think", Entity(1), function(self)
    print(self)
  end)
```

## Benchmarks: ##

Test conditions: 1000 hooks and 1000 calls.

On my PC I got:
```
Standard GMOD library:
Run 1 — 27.46 ms
Run 2 — 27.42 ms
Run 3 — 27.49 ms

Srlion's hook library:
Run 1 — 12.42 ms
Run 2 — 12.58 ms
Run 3 — 12.51 ms

print (super hooks)
Run 1 — 0.93 ms
Run 2 — 0.94 ms
Run 3 — 0.92 ms
```
