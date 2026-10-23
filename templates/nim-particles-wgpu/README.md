# Nim WGPU Particles

An Electrobun template with a Nim main process and an `<electrobun-wgpu>` overlay surface. The webview owns layout and controls; Nim runs a data-oriented particle simulation (~10k–50k particles) on the CPU and renders it as additive-blended instanced quads through a native WGPU pipeline. Three emitter modes: fountain, fireworks, and vortex.

After `hutch electrobun sync` in this directory (requires Hutch ≥ 0.28.2 and
a devkit release that ships the Nim toolchain and SDK entries):

```sh
hutch run dev
```

`hutch run dev` builds the app, launches it, and rebuilds when source files change. This native template has no npm dependencies.

The main process lives in `src/nim/main.nim` (simulation in `src/nim/particles.nim`); the webview lives in `src/mainview`.

## What's Nim-idiomatic here

- **Structure-of-arrays by hand**: particle fields live in parallel `array[MaxParticles, float32]` columns inside `ParticleFields`, matching the layout Odin gets from `#soa` without runtime indirection.
- **Data-oriented update loop**: separate passes over each field array — forces, drag/integration, aging, and swap-remove compaction — each touching only the columns it needs.
- **Deterministic, allocation-free hot path**: fixed-capacity pool, xorshift PRNG, fixed timestep; no per-frame allocations in the simulation.
- Dawn's webgpu C ABI is modeled with Nim objects checked via `static: doAssert sizeof(...)` / `offsetof`, and Electrobun host RPC uses `std/json` plus `{.cdecl.}` callbacks.

## Controls

The webview UI talks to the Nim process over Electrobun's host-message RPC: particle count, emitter mode, gravity and force sliders, and pause/reset all update the simulation live. The Nim side streams frame/particle stats back to the HUD.

## Platform notes / limitations

- The Nim toolchain is pinned to a release vendored by Electrobun (`package/vendors/nim`). Building against a different compiler version may not work.
- **Windows**: requires Visual Studio Build Tools (MSVC `link.exe`). x64 only.
- **macOS**: requires Xcode Command Line Tools.
- **Linux**: requires `clang`.
- No cross-compilation: build on each target platform.
