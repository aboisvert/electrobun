## Particle simulation: structure-of-arrays storage and data-oriented update passes.
##
## Nim has no `#soa` pragma; parallel fixed arrays per field give the same
## memory layout and update style as the Odin template.

import std/math

const MaxParticles* = 50_000
const DefaultTarget* = 20_000
const FloatsPerInstance* = 8
const InstanceStride* = FloatsPerInstance * sizeof(float32)
const RngSeed* = 0x9E3779B9'u32

type
  EmitterMode* = enum
    Fountain = 0
    Fireworks = 1
    Vortex = 2

  SimParams* = object
    mode*: EmitterMode
    target*: int
    gravity*: float32
    force*: float32
    paused*: bool

  ParticleFields* = object
    x*, y*, vx*, vy*, life*, lifespan*, size*, hue*: array[MaxParticles, float32]

  Sim* = object
    fields*: ParticleFields
    alive*: int
    rng*: uint32
    emitCarry*: float32
    burstTimer*: float32
    clock*: float32

proc defaultSimParams*(): SimParams =
  SimParams(
    mode: Fountain,
    target: DefaultTarget,
    gravity: 0.5,
    force: 0.5,
    paused: false,
  )

proc simReset*(sim: var Sim) =
  sim.alive = 0
  sim.rng = RngSeed
  sim.emitCarry = 0
  sim.burstTimer = 0
  sim.clock = 0

proc randU32(state: var uint32): uint32 =
  var x = state
  x = x xor (x shl 13)
  x = x xor (x shr 17)
  x = x xor (x shl 5)
  state = x
  x

proc randF32(state: var uint32): float32 =
  float32(randU32(state) shr 8) / float32(1 shl 24)

proc randRange(state: var uint32; lo, hi: float32): float32 =
  lo + (hi - lo) * randF32(state)

proc spawn(sim: var Sim; px, py, pvx, pvy, life, lifespan, size, hue: float32) =
  if sim.alive >= MaxParticles:
    return
  let i = sim.alive
  sim.fields.x[i] = px
  sim.fields.y[i] = py
  sim.fields.vx[i] = pvx
  sim.fields.vy[i] = pvy
  sim.fields.life[i] = life
  sim.fields.lifespan[i] = lifespan
  sim.fields.size[i] = size
  sim.fields.hue[i] = hue
  sim.alive += 1

proc emitFountain(sim: var Sim; params: SimParams; dt: float32) =
  const avgLifespan = 2.2'f32
  let rate = float32(params.target) / avgLifespan
  sim.emitCarry += rate * dt
  var count = int(sim.emitCarry)
  sim.emitCarry -= float32(count)
  let speedBase = 1.15 + params.force * 1.55
  for _ in 0 ..< count:
    if sim.alive >= params.target:
      break
    let angle = (randF32(sim.rng) - 0.5) * 0.55
    let speed = speedBase * randRange(sim.rng, 0.55, 1.0)
    let lifespan = randRange(sim.rng, 1.6, 2.8)
    spawn(
      sim,
      (randF32(sim.rng) - 0.5) * 0.04,
      -0.92,
      sin(angle) * speed,
      cos(angle) * speed,
      lifespan,
      lifespan,
      randRange(sim.rng, 0.006, 0.016),
      0.52 + randF32(sim.rng) * 0.14 + sin(sim.clock * 0.21) * 0.05,
    )

proc emitFireworks(sim: var Sim; params: SimParams; dt, aspect: float32) =
  sim.burstTimer -= dt
  if sim.burstTimer > 0:
    return
  sim.burstTimer = randRange(sim.rng, 0.3, 0.65)
  var burst = clamp(params.target div 8, 150, 4000)
  if sim.alive + burst > params.target:
    burst = max(params.target - sim.alive, 0)
  if burst == 0:
    return
  let originX = (randF32(sim.rng) - 0.5) * 1.3 * aspect
  let originY = randRange(sim.rng, 0.0, 0.65)
  let shellSpeed = 0.55 + params.force * 1.35
  let hue = randF32(sim.rng)
  let tau = PI * 2.0
  for _ in 0 ..< burst:
    let angle = randF32(sim.rng) * tau
    let speed = shellSpeed * (0.35 + 0.65 * sqrt(randF32(sim.rng)))
    let lifespan = randRange(sim.rng, 1.1, 2.1)
    spawn(
      sim,
      originX,
      originY,
      cos(angle) * speed,
      sin(angle) * speed,
      lifespan,
      lifespan,
      randRange(sim.rng, 0.005, 0.012),
      hue + randF32(sim.rng) * 0.08,
    )

proc emitVortex(sim: var Sim; params: SimParams; dt, aspect: float32) =
  const avgLifespan = 2.8'f32
  let rate = float32(params.target) / avgLifespan
  sim.emitCarry += rate * dt
  let count = int(sim.emitCarry)
  sim.emitCarry -= float32(count)
  let ring = 0.72 * min(aspect, 1.0)
  let tau = PI * 2.0
  for _ in 0 ..< count:
    if sim.alive >= params.target:
      break
    let angle = randF32(sim.rng) * tau
    let radius = ring * randRange(sim.rng, 0.85, 1.1)
    let tangent = 0.35 + params.force * 0.6
    let lifespan = randRange(sim.rng, 2.0, 3.6)
    spawn(
      sim,
      cos(angle) * radius,
      sin(angle) * radius,
      -sin(angle) * tangent,
      cos(angle) * tangent,
      lifespan,
      lifespan,
      randRange(sim.rng, 0.005, 0.013),
      0.62 + 0.25 * randF32(sim.rng) + angle * 0.015,
    )

proc palette(t: float32): array[3, float32] =
  let a = [0.54'f32, 0.36'f32, 0.30'f32]
  let b = [0.46'f32, 0.40'f32, 0.44'f32]
  let c = [1.00'f32, 0.92'f32, 0.72'f32]
  let d = [0.04'f32, 0.26'f32, 0.55'f32]
  let tau = PI * 2.0
  for j in 0 ..< 3:
    result[j] = a[j] + b[j] * cos(tau * (c[j] * t + d[j]))

proc simUpdate*(sim: var Sim; params: SimParams; dt, aspect: float32) =
  sim.clock += dt
  case params.mode
  of Fountain:
    emitFountain(sim, params, dt)
  of Fireworks:
    emitFireworks(sim, params, dt, aspect)
  of Vortex:
    emitVortex(sim, params, dt, aspect)

  let n = sim.alive
  var ps = sim.fields

  case params.mode
  of Fountain:
    let g = 0.35 + params.gravity * 2.3
    let turbulence = 0.12 + params.force * 0.5
    let t = sim.clock
    for i in 0 ..< n:
      ps.vy[i] -= g * dt
      ps.vx[i] += sin(ps.y[i] * 3.1 + t * 1.9) * turbulence * dt
  of Fireworks:
    let g = 0.15 + params.gravity * 1.2
    for i in 0 ..< n:
      ps.vy[i] -= g * dt
  of Vortex:
    let swirl = 0.9 + params.force * 2.7
    let pull = 0.22 + params.gravity * 0.85
    for i in 0 ..< n:
      let x = ps.x[i]
      let y = ps.y[i]
      let r = max(sqrt(x * x + y * y), 0.06)
      let invR = 1.0 / r
      let falloff = 0.3 / (0.18 + r)
      ps.vx[i] += (-y * invR * swirl * falloff - x * invR * pull) * dt
      ps.vy[i] += (x * invR * swirl * falloff - y * invR * pull) * dt

  var dragBase: float32
  case params.mode
  of Fountain:
    dragBase = 0.998
  of Fireworks:
    dragBase = 0.984
  of Vortex:
    dragBase = 0.995
  let drag = pow(dragBase, dt * 60.0)
  for i in 0 ..< n:
    ps.vx[i] *= drag
    ps.vy[i] *= drag
    ps.x[i] += ps.vx[i] * dt
    ps.y[i] += ps.vy[i] * dt

  for i in 0 ..< n:
    ps.life[i] -= dt

  let boundX = aspect * 1.4
  var i = 0
  while i < sim.alive:
    let dead =
      ps.life[i] <= 0 or ps.y[i] < -1.3 or ps.y[i] > 1.4 or abs(ps.x[i]) > boundX
    if dead:
      sim.alive -= 1
      let last = sim.alive
      ps.x[i] = ps.x[last]
      ps.y[i] = ps.y[last]
      ps.vx[i] = ps.vx[last]
      ps.vy[i] = ps.vy[last]
      ps.life[i] = ps.life[last]
      ps.lifespan[i] = ps.lifespan[last]
      ps.size[i] = ps.size[last]
      ps.hue[i] = ps.hue[last]
    else:
      i += 1
  sim.fields = ps

proc packInstances*(sim: Sim; instanceOut: var openArray[float32]; aspect: float32): int =
  let n = sim.alive
  let ps = sim.fields
  let invAspect = 1.0 / aspect
  for i in 0 ..< n:
    let t = clamp(ps.life[i] / max(ps.lifespan[i], 0.001), 0.0, 1.0)
    let fade = t * t * (3.0 - 2.0 * t)
    let color = palette(ps.hue[i])
    let base = i * FloatsPerInstance
    instanceOut[base + 0] = ps.x[i] * invAspect
    instanceOut[base + 1] = ps.y[i]
    instanceOut[base + 2] = ps.size[i] * invAspect
    instanceOut[base + 3] = ps.size[i]
    instanceOut[base + 4] = color[0]
    instanceOut[base + 5] = color[1]
    instanceOut[base + 6] = color[2]
    instanceOut[base + 7] = fade
  sim.alive
