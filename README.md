# ZAT

ZAT is a simple SAT solver implemented in zig.


## Build

Use `zig build` to build zat preferably with `-Doptimize=ReleaseFast` as the code makes heavy use of assert statements.

## Usage

just call:

```bash
./zat path/to/instance.cnf
```

## Features

ZAT does almost have no features (for a SAT solver).
The Features include:
* DPLL sat solving (with no pure literal assignement).
* Unit propagation using 2 watched literals.
* Parsing DIMACS `*.cnf` files and using the standard Protocol for SAT solvers.
* (while this is not really a feature) no heuristics for variable selection.
