import std/[math, unittest]
import particles

suite "particle simulation":
  test "reset clears live set":
    var sim: Sim
    sim.alive = 42
    sim.rng = 123
    simReset(sim)
    check sim.alive == 0
    check sim.rng == RngSeed

  test "fountain stays finite and in bounds":
    var sim: Sim
    simReset(sim)
    var params = defaultSimParams()
    params.mode = Fountain
    params.target = 4000
    let aspect = 1.5'f32
    const dt = 1.0 / 60.0
    for _ in 0 ..< 720:
      simUpdate(sim, params, dt, aspect)
    check sim.alive > 100
    for i in 0 ..< sim.alive:
      check not isNaN(sim.fields.x[i])
      check not isNaN(sim.fields.y[i])
      check sim.fields.y[i] >= -1.31
      check sim.fields.y[i] <= 1.41
      check abs(sim.fields.x[i]) <= aspect * 1.41

  test "pack instances matches alive count":
    var sim: Sim
    simReset(sim)
    var params = defaultSimParams()
    params.target = 500
    simUpdate(sim, params, 1.0 / 30.0, 1.0)
    var buffer: array[MaxParticles * FloatsPerInstance, float32]
    let count = packInstances(sim, buffer, 1.0)
    check count == sim.alive
    if count > 0:
      check buffer[7] >= 0.0
      check buffer[7] <= 1.0
