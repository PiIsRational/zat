# ZAT

ZAT is a simple SAT solver implemented in zig.

## Requierements

* zig == 0.14.0

## Build

Use `zig build` to build zat preferably with `-Dno-assert=true` which removes larger
assertions.

## Usage

just call:

```bash
./zat path/to/instance.cnf
```

## Features

ZAT does almost have no features (for a SAT solver).
The Features include:
* a simple CDCL implementation.
* eVSIDS and Phase Saving for choosing variables
* Unit propagation using 2 watched literals.
* Parsing DIMACS `*.cnf` files and using the standard Protocol for SAT solvers.
* (Not really a feature) no clause deletion algorithm.
