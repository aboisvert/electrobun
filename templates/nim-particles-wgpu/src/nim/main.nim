## Nim WGPU particles: CPU simulation in the Nim main process, rendered as
## additive-blended instanced quads on a native <electrobun-wgpu> surface.

import std/[dynlib, json, locks, atomics, options, os]
import electrobun
import particles

const DefaultSecretKey* =
  "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32"

const ParticleShader* = """
struct VSOut {
  @builtin(position) position : vec4<f32>,
  @location(0) local : vec2<f32>,
  @location(1) color : vec4<f32>,
};

@vertex
fn vs_main(
  @location(0) corner : vec2<f32>,
  @location(1) center : vec2<f32>,
  @location(2) size : vec2<f32>,
  @location(3) color : vec4<f32>,
) -> VSOut {
  var out : VSOut;
  out.position = vec4<f32>(center + corner * size, 0.0, 1.0);
  out.local = corner;
  out.color = color;
  return out;
}

@fragment
fn fs_main(
  @location(0) local : vec2<f32>,
  @location(1) color : vec4<f32>,
) -> @location(0) vec4<f32> {
  let d2 = dot(local, local);
  if (d2 > 1.0) {
    discard;
  }
  let core = exp(-d2 * 5.5);
  let halo = pow(max(1.0 - sqrt(d2), 0.0), 2.4) * 0.32;
  let intensity = (core + halo) * color.a;
  return vec4<f32>(color.rgb * intensity, intensity);
}
"""

const DefaultSurfaceFormat = 0x0000001b'u32
const StypeShaderSourceWgsl = 0x00000002'u32
const TextureUsageRenderAttachment = 0x0000000000000010'u64
const CompositeAlphaModeOpaque = 0x00000001'u32
const PresentModeFifo = 0x00000001'u32
const VertexFormatFloat32x2 = 0x0000001d'u32
const VertexFormatFloat32x4 = 0x0000001f'u32
const VertexStepModeVertex = 0x00000001'u32
const VertexStepModeInstance = 0x00000002'u32
const PrimitiveTopologyTriangleList = 0x00000004'u32
const FrontFaceCcw = 0x00000001'u32
const CullModeNone = 0x00000001'u32
const ColorWriteMaskAll = 0x000000000000000f'u64
const BlendOperationAdd = 0x00000001'u32
const BlendFactorOne = 0x00000002'u32
const BufferUsageCopyDst = 0x0000000000000008'u64
const BufferUsageVertex = 0x0000000000000020'u64
const LoadOpClear = 0x00000002'u32
const StoreOpStore = 0x00000001'u32
const DepthSliceUndefined = 0xffffffff'u32

type
  WgpuStringView = object
    data: pointer
    length: uint64

  WgpuShaderSourceWgsl = object
    nextInChain: pointer
    sType: uint32
    code: WgpuStringView

  WgpuShaderModuleDescriptor = object
    nextInChain: pointer
    label: WgpuStringView

  WgpuVertexAttribute = object
    nextInChain: pointer
    format: uint32
    offset: uint64
    shaderLocation: uint32

  WgpuVertexBufferLayout = object
    nextInChain: pointer
    stepMode: uint32
    arrayStride: uint64
    attributeCount: uint64
    attributes: ptr WgpuVertexAttribute

  WgpuBlendComponent = object
    operation: uint32
    srcFactor: uint32
    dstFactor: uint32

  WgpuBlendState = object
    color, alpha: WgpuBlendComponent

  WgpuColorTargetState = object
    nextInChain: pointer
    format: uint32
    blend: ptr WgpuBlendState
    writeMask: uint64

  WgpuVertexState = object
    nextInChain: pointer
    module: pointer
    entryPoint: WgpuStringView
    constantCount: uint64
    constants: pointer
    bufferCount: uint64
    buffers: ptr WgpuVertexBufferLayout

  WgpuFragmentState = object
    nextInChain: pointer
    module: pointer
    entryPoint: WgpuStringView
    constantCount: uint64
    constants: pointer
    targetCount: uint64
    targets: ptr WgpuColorTargetState

  WgpuPrimitiveState = object
    nextInChain: pointer
    topology: uint32
    stripIndexFormat: uint32
    frontFace: uint32
    cullMode: uint32
    unclippedDepth: bool

  WgpuMultisampleState = object
    nextInChain: pointer
    count: uint32
    mask: uint32
    alphaToCoverageEnabled: bool

  WgpuRenderPipelineDescriptor = object
    nextInChain: pointer
    label: WgpuStringView
    layout: pointer
    vertex: WgpuVertexState
    primitive: WgpuPrimitiveState
    depthStencil: pointer
    multisample: WgpuMultisampleState
    fragment: ptr WgpuFragmentState

  WgpuBufferDescriptor = object
    nextInChain: pointer
    label: WgpuStringView
    usage: uint64
    size: uint64
    mappedAtCreation: bool

  WgpuSurfaceConfiguration = object
    nextInChain: pointer
    device: pointer
    format: uint32
    usage: uint64
    width, height: uint32
    viewFormatCount: uint64
    viewFormats: pointer
    alphaMode: uint32
    presentMode: uint32

  WgpuSurfaceTexture = object
    nextInChain: pointer
    texture: pointer
    status: uint32

  WgpuSurfaceCapabilities = object
    nextInChain: pointer
    usages: uint64
    formatCount: uint
    formats: ptr uint32
    presentModeCount: uint
    presentModes: ptr uint32
    alphaModeCount: uint
    alphaModes: ptr uint32

  WgpuColor = object
    r, g, b, a: float64

  WgpuRenderPassColorAttachment = object
    nextInChain: pointer
    view: pointer
    depthSlice: uint32
    resolveTarget: pointer
    loadOp: uint32
    storeOp: uint32
    clearValue: WgpuColor

  WgpuRenderPassDescriptor = object
    nextInChain: pointer
    label: WgpuStringView
    colorAttachmentCount: uint64
    colorAttachments: ptr WgpuRenderPassColorAttachment
    depthStencilAttachment: pointer
    occlusionQuerySet: pointer
    timestampWrites: pointer

static:
  doAssert sizeof(WgpuShaderSourceWgsl) == 32
  doAssert sizeof(WgpuShaderModuleDescriptor) == 24
  doAssert sizeof(WgpuVertexAttribute) == 32
  doAssert sizeof(WgpuVertexBufferLayout) == 40
  doAssert sizeof(WgpuBlendState) == 24
  doAssert sizeof(WgpuColorTargetState) == 32
  doAssert sizeof(WgpuVertexState) == 64
  doAssert sizeof(WgpuFragmentState) == 64
  doAssert sizeof(WgpuPrimitiveState) == 32
  doAssert sizeof(WgpuMultisampleState) == 24
  doAssert sizeof(WgpuRenderPipelineDescriptor) == 168
  doAssert offsetof(WgpuRenderPipelineDescriptor, vertex) == 32
  doAssert offsetof(WgpuRenderPipelineDescriptor, primitive) == 96
  doAssert offsetof(WgpuRenderPipelineDescriptor, multisample) == 136
  doAssert offsetof(WgpuRenderPipelineDescriptor, fragment) == 160
  doAssert sizeof(WgpuBufferDescriptor) == 48
  doAssert sizeof(WgpuSurfaceConfiguration) == 64
  doAssert offsetof(WgpuSurfaceConfiguration, usage) == 24
  doAssert sizeof(WgpuSurfaceTexture) == 24
  doAssert sizeof(WgpuSurfaceCapabilities) == 64
  doAssert offsetof(WgpuSurfaceCapabilities, formats) == 24
  doAssert offsetof(WgpuSurfaceCapabilities, alphaModes) == 56
  doAssert sizeof(WgpuRenderPassColorAttachment) == 72
  doAssert offsetof(WgpuRenderPassColorAttachment, clearValue) == 40
  doAssert sizeof(WgpuRenderPassDescriptor) == 64
  doAssert offsetof(WgpuRenderPassDescriptor, colorAttachments) == 32

type
  CreateFn = proc (a, b: pointer): pointer {.cdecl, gcsafe.}
  ReleaseFn = proc (a: pointer) {.cdecl, gcsafe.}
  SetPipelineFn = proc (a, b: pointer) {.cdecl, gcsafe.}
  SetVertexBufferFn = proc (a: pointer; slot: uint32; buf: pointer; off, size: uint64) {.cdecl, gcsafe.}
  DrawFn = proc (a: pointer; v, i, firstV, firstI: uint32) {.cdecl, gcsafe.}
  EndFn = proc (a: pointer) {.cdecl, gcsafe.}
  QueueWriteBufferFn = proc (queue, buf: pointer; off: uint64; data: pointer; size: uint64) {.cdecl, gcsafe.}
  QueueSubmitFn = proc (queue: pointer; count: uint64; cmds: pointer) {.cdecl, gcsafe.}
  ProcessEventsFn = proc (instance: pointer) {.cdecl, gcsafe.}
  SurfaceGetCapabilitiesFn = proc (surface, adapter, caps: pointer): uint32 {.cdecl, gcsafe.}
  SurfaceCapabilitiesFreeMembersFn = proc (caps: WgpuSurfaceCapabilities) {.cdecl, gcsafe.}

  WgpuApi = object
    deviceCreateShaderModule: CreateFn
    deviceCreateRenderPipeline: CreateFn
    deviceCreateBuffer: CreateFn
    deviceCreateCommandEncoder: CreateFn
    textureCreateView: CreateFn
    commandEncoderBeginRenderPass: CreateFn
    renderPassEncoderSetPipeline: SetPipelineFn
    renderPassEncoderSetVertexBuffer: SetVertexBufferFn
    renderPassEncoderDraw: DrawFn
    renderPassEncoderEnd: EndFn
    commandEncoderFinish: CreateFn
    queueWriteBuffer: QueueWriteBufferFn
    queueSubmit: QueueSubmitFn
    instanceProcessEvents: ProcessEventsFn
    textureRelease: ReleaseFn
    textureViewRelease: ReleaseFn
    commandBufferRelease: ReleaseFn
    commandEncoderRelease: ReleaseFn
    surfaceGetCapabilities: SurfaceGetCapabilitiesFn
    surfaceCapabilitiesFreeMembers: SurfaceCapabilitiesFreeMembersFn

  GpuShared = object
    mutex: Lock
    viewId: uint32
    hostWebviewId: uint32
    width, height: uint32
    running: bool
    resetRequested: bool
    params: SimParams

  AppState = object
    core: Core
    bundlePaths: BundlePaths
    mutex: Lock
    webviewId: uint32
    gpu: GpuShared

  GpuPipeline = object
    pipeline: pointer
    cornerBuffer: pointer
    instanceBuffer: pointer

var
  gState: ptr AppState
  gQueueRunning: Atomic[bool]
  gGpuThreadStarted: Atomic[bool]
  gShuttingDown: Atomic[bool]

proc stringView(s: string): WgpuStringView =
  if s.len == 0:
    WgpuStringView(data: nil, length: 0)
  else:
    WgpuStringView(data: unsafeAddr s[0], length: uint64(s.len))

when defined(windows):
  const WgpuLibName = "webgpu_dawn.dll"
elif defined(macosx):
  const WgpuLibName = "libwebgpu_dawn.dylib"
else:
  const WgpuLibName = "libwebgpu_dawn.so"

proc loadWgpuLibrary(): (LibHandle, bool) =
  let (bundlePaths, err) = resolveBundlePaths()
  if err != ebNone:
    return (nil, false)
  let libPath = joinPath(bundlePaths.exeDir, WgpuLibName)
  let handle = loadLib(libPath, globalSymbols = false)
  if handle == nil:
    return (nil, false)
  (handle, true)

proc wgpuSymbol(handle: LibHandle; name: string): pointer =
  cast[pointer](symAddr(handle, name))

proc wgpuApiLoad(): (WgpuApi, bool) =
  let (lib, libOk) = loadWgpuLibrary()
  if not libOk:
    return (default(WgpuApi), false)
  var api: WgpuApi
  template loadSym(field, symName: untyped) =
    block:
      let p = wgpuSymbol(lib, symName)
      if p.isNil:
        stderr.writeLine("[nim-particles] missing wgpu symbol: ", symName)
        return (default(WgpuApi), false)
      field = cast[typeof(field)](p)

  loadSym(api.deviceCreateShaderModule, "wgpuDeviceCreateShaderModule")
  loadSym(api.deviceCreateRenderPipeline, "wgpuDeviceCreateRenderPipeline")
  loadSym(api.deviceCreateBuffer, "wgpuDeviceCreateBuffer")
  loadSym(api.deviceCreateCommandEncoder, "wgpuDeviceCreateCommandEncoder")
  loadSym(api.textureCreateView, "wgpuTextureCreateView")
  loadSym(api.commandEncoderBeginRenderPass, "wgpuCommandEncoderBeginRenderPass")
  loadSym(api.renderPassEncoderSetPipeline, "wgpuRenderPassEncoderSetPipeline")
  loadSym(api.renderPassEncoderSetVertexBuffer, "wgpuRenderPassEncoderSetVertexBuffer")
  loadSym(api.renderPassEncoderDraw, "wgpuRenderPassEncoderDraw")
  loadSym(api.renderPassEncoderEnd, "wgpuRenderPassEncoderEnd")
  loadSym(api.commandEncoderFinish, "wgpuCommandEncoderFinish")
  loadSym(api.queueWriteBuffer, "wgpuQueueWriteBuffer")
  loadSym(api.queueSubmit, "wgpuQueueSubmit")
  loadSym(api.instanceProcessEvents, "wgpuInstanceProcessEvents")
  loadSym(api.textureRelease, "wgpuTextureRelease")
  loadSym(api.textureViewRelease, "wgpuTextureViewRelease")
  loadSym(api.commandBufferRelease, "wgpuCommandBufferRelease")
  loadSym(api.commandEncoderRelease, "wgpuCommandEncoderRelease")
  loadSym(api.surfaceGetCapabilities, "wgpuSurfaceGetCapabilities")
  loadSym(api.surfaceCapabilitiesFreeMembers, "wgpuSurfaceCapabilitiesFreeMembers")
  (api, true)

proc requestShutdown() =
  if gShuttingDown.exchange(true):
    return
  if gState != nil:
    acquire(gState.gpu.mutex)
    gState.gpu.running = false
    gState.gpu.viewId = 0
    gState.gpu.hostWebviewId = 0
    release(gState.gpu.mutex)
  gQueueRunning.store(false)

proc mainWindowClosed(_: uint32) {.cdecl, raises: [].} =
  requestShutdown()

proc appState(): ptr AppState =
  if gState.isNil:
    raise newException(CatchableError, "nim-particles state not initialized")
  gState

const CornerVertexCount = 6
const CornerStride = 2 * sizeof(float32)
const CornerBufferSize = CornerVertexCount * CornerStride
const InstanceBufferSize = MaxParticles * InstanceStride

proc createParticlePipeline(
  api: WgpuApi; ctx: WgpuContext; queue: pointer; surfaceFormat: uint32
): (GpuPipeline, bool) =
  var pipeline: GpuPipeline
  var shaderCode = ParticleShader
  var shaderSource = WgpuShaderSourceWgsl(
    sType: StypeShaderSourceWgsl,
    code: stringView(shaderCode),
  )
  var shaderDescriptor = WgpuShaderModuleDescriptor(nextInChain: addr shaderSource)
  let shaderModule = api.deviceCreateShaderModule(ctx.devicePtr, addr shaderDescriptor)
  if shaderModule.isNil:
    stderr.writeLine("[nim-particles] failed to create shader module")
    return (default(GpuPipeline), false)

  var cornerAttributes = [WgpuVertexAttribute(format: VertexFormatFloat32x2, offset: 0, shaderLocation: 0)]
  var instanceAttributes = [
    WgpuVertexAttribute(format: VertexFormatFloat32x2, offset: 0, shaderLocation: 1),
    WgpuVertexAttribute(format: VertexFormatFloat32x2, offset: 8, shaderLocation: 2),
    WgpuVertexAttribute(format: VertexFormatFloat32x4, offset: 16, shaderLocation: 3),
  ]
  var bufferLayouts = [
    WgpuVertexBufferLayout(
      stepMode: VertexStepModeVertex,
      arrayStride: CornerStride,
      attributeCount: 1,
      attributes: addr cornerAttributes[0],
    ),
    WgpuVertexBufferLayout(
      stepMode: VertexStepModeInstance,
      arrayStride: InstanceStride,
      attributeCount: 3,
      attributes: addr instanceAttributes[0],
    ),
  ]

  var blend = WgpuBlendState(
    color: WgpuBlendComponent(
      operation: BlendOperationAdd, srcFactor: BlendFactorOne, dstFactor: BlendFactorOne),
    alpha: WgpuBlendComponent(
      operation: BlendOperationAdd, srcFactor: BlendFactorOne, dstFactor: BlendFactorOne),
  )
  var colorTarget = WgpuColorTargetState(
    format: surfaceFormat, blend: addr blend, writeMask: ColorWriteMaskAll)
  var fragmentState = WgpuFragmentState(
    module: shaderModule,
    entryPoint: stringView("fs_main"),
    targetCount: 1,
    targets: addr colorTarget,
  )

  var pipelineDescriptor = WgpuRenderPipelineDescriptor(
    vertex: WgpuVertexState(
      module: shaderModule,
      entryPoint: stringView("vs_main"),
      bufferCount: 2,
      buffers: addr bufferLayouts[0],
    ),
    primitive: WgpuPrimitiveState(
      topology: PrimitiveTopologyTriangleList,
      frontFace: FrontFaceCcw,
      cullMode: CullModeNone,
    ),
    multisample: WgpuMultisampleState(count: 1, mask: 0xffffffff'u32),
    fragment: addr fragmentState,
  )

  pipeline.pipeline = api.deviceCreateRenderPipeline(ctx.devicePtr, addr pipelineDescriptor)
  if pipeline.pipeline.isNil:
    stderr.writeLine("[nim-particles] failed to create render pipeline")
    return (default(GpuPipeline), false)

  var cornerDescriptor = WgpuBufferDescriptor(
    usage: BufferUsageVertex or BufferUsageCopyDst,
    size: CornerBufferSize,
  )
  pipeline.cornerBuffer = api.deviceCreateBuffer(ctx.devicePtr, addr cornerDescriptor)
  if pipeline.cornerBuffer.isNil:
    stderr.writeLine("[nim-particles] failed to create corner buffer")
    return (default(GpuPipeline), false)

  var instanceDescriptor = WgpuBufferDescriptor(
    usage: BufferUsageVertex or BufferUsageCopyDst,
    size: InstanceBufferSize,
  )
  pipeline.instanceBuffer = api.deviceCreateBuffer(ctx.devicePtr, addr instanceDescriptor)
  if pipeline.instanceBuffer.isNil:
    stderr.writeLine("[nim-particles] failed to create instance buffer")
    return (default(GpuPipeline), false)

  var corners: array[CornerVertexCount * 2, float32] = [
    -1.0, -1.0, 1.0, -1.0, 1.0, 1.0,
    -1.0, -1.0, 1.0, 1.0, -1.0, 1.0,
  ]
  api.queueWriteBuffer(queue, pipeline.cornerBuffer, 0, addr corners[0], CornerBufferSize)
  (pipeline, true)

proc pickSurfaceConfiguration(api: WgpuApi; ctx: WgpuContext): (uint32, uint32, bool) =
  result[0] = DefaultSurfaceFormat
  result[1] = CompositeAlphaModeOpaque
  var capabilities = default(WgpuSurfaceCapabilities)
  let status = api.surfaceGetCapabilities(ctx.surfacePtr, ctx.adapterPtr, addr capabilities)
  api.surfaceCapabilitiesFreeMembers(capabilities)
  if status != 1 or capabilities.formatCount == 0 or capabilities.formats.isNil:
    return
  result[0] = capabilities.formats[]
  if capabilities.alphaModeCount > 0 and not capabilities.alphaModes.isNil:
    result[1] = capabilities.alphaModes[]
  result[2] = true

proc configureSurface(
  core: Core; ctx: WgpuContext; width, height, surfaceFormat, alphaMode: uint32
): EbError =
  var config = WgpuSurfaceConfiguration(
    device: ctx.devicePtr,
    format: surfaceFormat,
    usage: TextureUsageRenderAttachment,
    width: width,
    height: height,
    alphaMode: alphaMode,
    presentMode: PresentModeFifo,
  )
  core.wgpuSurfaceConfigureMainThread(ctx.surfacePtr, addr config)

proc renderFrame(
  core: Core; api: WgpuApi; ctx: WgpuContext; pipeline: GpuPipeline; queue: pointer;
  instanceData: openArray[float32]; instanceCount: int
): bool =
  api.instanceProcessEvents(ctx.instancePtr)
  if instanceCount > 0:
    api.queueWriteBuffer(
      queue,
      pipeline.instanceBuffer,
      0,
      unsafeAddr instanceData[0],
      uint64(instanceCount * InstanceStride),
    )

  var surfaceTexture = default(WgpuSurfaceTexture)
  if core.wgpuSurfaceGetCurrentTextureMainThread(ctx.surfacePtr, addr surfaceTexture) != ebNone:
    return false
  if (surfaceTexture.status != 1 and surfaceTexture.status != 2) or surfaceTexture.texture.isNil:
    return false
  defer: api.textureRelease(surfaceTexture.texture)

  let textureView = api.textureCreateView(surfaceTexture.texture, nil)
  if textureView.isNil:
    return false
  defer: api.textureViewRelease(textureView)

  let encoder = api.deviceCreateCommandEncoder(ctx.devicePtr, nil)
  if encoder.isNil:
    return false
  defer: api.commandEncoderRelease(encoder)

  var colorAttachment = WgpuRenderPassColorAttachment(
    view: textureView,
    depthSlice: DepthSliceUndefined,
    loadOp: LoadOpClear,
    storeOp: StoreOpStore,
    clearValue: WgpuColor(r: 0.004, g: 0.005, b: 0.010, a: 1.0),
  )
  var passDescriptor = WgpuRenderPassDescriptor(
    colorAttachmentCount: 1,
    colorAttachments: addr colorAttachment,
  )

  let pass = api.commandEncoderBeginRenderPass(encoder, addr passDescriptor)
  if pass.isNil:
    return false
  api.renderPassEncoderSetPipeline(pass, pipeline.pipeline)
  api.renderPassEncoderSetVertexBuffer(pass, 0, pipeline.cornerBuffer, 0, CornerBufferSize)
  api.renderPassEncoderSetVertexBuffer(pass, 1, pipeline.instanceBuffer, 0, InstanceBufferSize)
  if instanceCount > 0:
    api.renderPassEncoderDraw(pass, CornerVertexCount, uint32(instanceCount), 0, 0)
  api.renderPassEncoderEnd(pass)

  let commandBuffer = api.commandEncoderFinish(encoder, nil)
  if commandBuffer.isNil:
    return false
  defer: api.commandBufferRelease(commandBuffer)

  var commands = [commandBuffer]
  api.queueSubmit(queue, 1, addr commands[0])
  let (_, presentErr) = core.wgpuSurfacePresentMainThread(ctx.surfacePtr)
  presentErr == ebNone

proc sendGpuFrame(
  webviewId, viewId: uint32; frame: uint64; width, height: uint32; alive: int
) =
  let state = appState()
  discard state.core.sendHostMessageToWebview(
    webviewId,
    %*{
      "type": "message",
      "id": "gpuFrame",
      "payload": {
        "id": viewId,
        "frame": frame,
        "width": width,
        "height": height,
        "alive": alive,
      },
    },
  )

proc gpuRenderLoopImpl() =
  let state = appState()
  var native: WgpuNative
  var nativeErr: EbError
  (native, nativeErr) = wgpuNativeLoad()
  if nativeErr != ebNone:
    stderr.writeLine("[nim-particles] failed to load WGPU library: ", nativeErr)
    return
  defer: native.close()

  let (api, apiOk) = wgpuApiLoad()
  if not apiOk:
    return

  let buffers = newParticleBuffers()

  var activeViewId: uint32
  var ctx: WgpuContext
  var hasContext = false
  var pipeline: GpuPipeline
  var queue: pointer
  var configuredWidth, configuredHeight: uint32
  var frame: uint64
  var surfaceFormat = DefaultSurfaceFormat
  var alphaMode = CompositeAlphaModeOpaque
  var loggedFirstFrame = false
  const dt = 1.0 / 60.0

  while gQueueRunning.load():
    acquire(state.gpu.mutex)
    let running = state.gpu.running
    let viewId = state.gpu.viewId
    let hostWebviewId = state.gpu.hostWebviewId
    let width = state.gpu.width
    let height = state.gpu.height
    let params = state.gpu.params
    let resetRequested = state.gpu.resetRequested
    state.gpu.resetRequested = false
    release(state.gpu.mutex)

    if not running or viewId == 0:
      sleep(16)
      continue

    if resetRequested:
      simReset(buffers.sim)

    if not hasContext or activeViewId != viewId:
      var ctxErr: EbError
      (ctx, ctxErr) = createForWgpuView(state.core, native, viewId)
      if ctxErr != ebNone:
        stderr.writeLine("[nim-particles] failed to create WGPU context: ", ctxErr)
        sleep(250)
        continue
      queue = getQueue(ctx, native)
      if queue.isNil:
        stderr.writeLine("[nim-particles] failed to get WGPU queue")
        sleep(250)
        continue
      let (selectedFormat, selectedAlpha, capabilitiesOk) = pickSurfaceConfiguration(api, ctx)
      if not capabilitiesOk:
        stderr.writeLine("[nim-particles] failed to read surface capabilities")
        sleep(250)
        continue
      let (newPipeline, pipelineOk) = createParticlePipeline(api, ctx, queue, selectedFormat)
      if not pipelineOk:
        sleep(250)
        continue
      pipeline = newPipeline
      surfaceFormat = selectedFormat
      alphaMode = selectedAlpha
      hasContext = true
      activeViewId = viewId
      configuredWidth = 0
      configuredHeight = 0
      loggedFirstFrame = false
      echo "[nim-particles] WGPU context ready for view ", viewId,
        " (format=", surfaceFormat, " alpha=", alphaMode, ")"

    if configuredWidth != width or configuredHeight != height:
      if configureSurface(state.core, ctx, width, height, surfaceFormat, alphaMode) != ebNone:
        stderr.writeLine("[nim-particles] failed to configure surface")
        sleep(250)
        continue
      configuredWidth = width
      configuredHeight = height

    let aspect = float32(width) / max(float32(height), 1.0)
    var paramsLocal = params
    if not paramsLocal.paused:
      simUpdate(buffers.sim, paramsLocal, dt, aspect)
    let instanceCount = packInstances(buffers.sim, buffers.instances, aspect)

    if not renderFrame(state.core, api, ctx, pipeline, queue, buffers.instances, instanceCount):
      sleep(100)
      continue
    if not loggedFirstFrame:
      loggedFirstFrame = true
      echo "[nim-particles] first frame submitted (", instanceCount, " instances)"

    if frame mod 30 == 0 and hostWebviewId != 0:
      sendGpuFrame(hostWebviewId, viewId, frame, width, height, buffers.sim.alive)

    inc frame
    sleep(16)

proc gpuRenderLoop() {.thread.} =
  {.cast(gcsafe).}:
    gpuRenderLoopImpl()

var gpuThread: Thread[void]

proc ensureGpuThread() =
  if gGpuThreadStarted.exchange(true):
    return
  createThread(gpuThread, gpuRenderLoop)

proc objString(obj: JsonNode; name: string): Option[string] =
  if name notin obj or obj[name].kind != JString:
    none(string)
  else:
    some(obj[name].getStr)

proc objF64(obj: JsonNode; name: string; fallback: float64): float64 =
  if name notin obj:
    return fallback
  case obj[name].kind
  of JInt:
    float64(obj[name].getInt)
  of JFloat:
    obj[name].getFloat
  else:
    fallback

proc objU32(obj: JsonNode; name: string; fallback: uint32): uint32 =
  let value = objF64(obj, name, float64(fallback))
  if value < 0:
    fallback
  else:
    uint32(min(value, float64(high uint32)))

proc objBool(obj: JsonNode; name: string; fallback: bool): bool =
  if name notin obj or obj[name].kind != JBool:
    fallback
  else:
    obj[name].getBool

proc rectDimension(params: JsonNode; name: string; fallback: uint32): uint32 =
  if "rect" notin params or params["rect"].kind != JObject:
    return fallback
  clamp(objU32(params["rect"], name, fallback), 1'u32, 4096'u32)

proc sendRpcSuccess(webviewId: uint32; requestId: uint64) =
  let state = appState()
  let err = state.core.sendHostMessageToWebview(
    webviewId,
    %*{"type": "response", "id": requestId, "success": true, "payload": {"ok": true}},
  )
  if err != ebNone:
    stderr.writeLine("[nim-particles] failed to send response: ", err)

proc sendRpcError(webviewId: uint32; requestId: uint64; message: string) =
  let state = appState()
  let err = state.core.sendHostMessageToWebview(
    webviewId,
    %*{"type": "response", "id": requestId, "success": false, "error": message},
  )
  if err != ebNone:
    stderr.writeLine("[nim-particles] failed to send error response: ", err)

proc configureGpuFromParams(state: ptr AppState; webviewId: uint32; params: JsonNode): bool =
  let viewId = objU32(params, "id", 0)
  if viewId == 0:
    return false
  acquire(state.gpu.mutex)
  defer: release(state.gpu.mutex)
  state.gpu.viewId = viewId
  state.gpu.hostWebviewId = webviewId
  state.gpu.width = rectDimension(params, "width", state.gpu.width)
  state.gpu.height = rectDimension(params, "height", state.gpu.height)
  let modeIndex = min(objU32(params, "mode", uint32(state.gpu.params.mode)), 2)
  state.gpu.params.mode = EmitterMode(modeIndex)
  state.gpu.params.target = int(
    clamp(objU32(params, "count", uint32(state.gpu.params.target)), 1000'u32, uint32(MaxParticles)))
  state.gpu.params.gravity = clamp(
    float32(objF64(params, "gravity", float64(state.gpu.params.gravity) * 100.0)) / 100.0,
    0.0, 1.0)
  state.gpu.params.force = clamp(
    float32(objF64(params, "force", float64(state.gpu.params.force) * 100.0)) / 100.0,
    0.0, 1.0)
  state.gpu.params.paused = objBool(params, "paused", state.gpu.params.paused)
  true

proc handleRpcRequest(webviewId: uint32; requestId: uint64; rpcMethod: string; params: JsonNode) =
  let state = appState()
  case rpcMethod
  of "startGpu":
    if params.kind != JObject or not configureGpuFromParams(state, webviewId, params):
      sendRpcError(webviewId, requestId, "InvalidParams")
      return
    acquire(state.gpu.mutex)
    state.gpu.running = true
    let startedViewId = state.gpu.viewId
    release(state.gpu.mutex)
    echo "[nim-particles] starting WGPU view ", startedViewId
    ensureGpuThread()
    sendRpcSuccess(webviewId, requestId)
  of "configureGpu":
    if params.kind != JObject or not configureGpuFromParams(state, webviewId, params):
      sendRpcError(webviewId, requestId, "InvalidParams")
      return
    sendRpcSuccess(webviewId, requestId)
  of "resetSim":
    acquire(state.gpu.mutex)
    state.gpu.resetRequested = true
    release(state.gpu.mutex)
    sendRpcSuccess(webviewId, requestId)
  else:
    sendRpcError(webviewId, requestId, "Unknown RPC request")

proc handleHostMessage(webviewId: uint32; message: string) =
  if message.len == 0:
    return
  let parsed =
    try:
      parseJson(message)
    except CatchableError:
      stderr.writeLine("[nim-particles] failed to parse RPC packet")
      return
  if parsed.kind != JObject:
    return
  let packetType = objString(parsed, "type")
  if packetType.isNone or packetType.get != "request":
    return
  if "id" notin parsed:
    return
  var requestId: uint64
  case parsed["id"].kind
  of JInt:
    let v = parsed["id"].getInt
    if v < 0:
      return
    requestId = uint64(v)
  else:
    return
  let rpcMethodName = objString(parsed, "method")
  if rpcMethodName.isNone:
    return
  let params =
    if "params" in parsed:
      parsed["params"]
    else:
      newJNull()
  handleRpcRequest(webviewId, requestId, rpcMethodName.get, params)

proc hostBridge(webviewId: uint32; message: cstring) {.cdecl, raises: [].} =
  try:
    handleHostMessage(webviewId, $message)
  except CatchableError:
    discard

proc drainHostMessageQueueImpl() =
  while gQueueRunning.load():
    if gState.isNil:
      sleep(10)
      continue
    var drainedAny = false
    while gQueueRunning.load():
      var webviewId: uint32
      let message = gState.core.popNextQueuedHostMessage(webviewId)
      if message.isNil:
        break
      handleHostMessage(webviewId, $message)
      gState.core.freeCoreString(message)
      drainedAny = true
    if not drainedAny:
      sleep(10)

proc drainHostMessageQueue() {.thread.} =
  {.cast(gcsafe).}:
    drainHostMessageQueueImpl()

proc createUiImpl() =
  let state = appState()
  sleep(150)
  if state.core.configureWebviewRuntimeFromExecutableDir(state.bundlePaths, 0) != ebNone:
    stderr.writeLine("[nim-particles] failed to configure webview runtime")
    return

  var windowOptions = defaultWindowOptions("Nim Particles")
  windowOptions.frame = Rect(x: 160, y: 100, width: 1080, height: 740)
  windowOptions.callbacks.close = mainWindowClosed
  let (windowId, windowErr) = state.core.createWindow(windowOptions)
  if windowErr != ebNone:
    stderr.writeLine("[nim-particles] failed to create window: ", windowErr)
    return

  var webviewOptions = defaultWebviewOptions(windowId)
  webviewOptions.url = "views://mainview/index.html"
  webviewOptions.frame = Rect(x: 0, y: 0, width: 1080, height: 740)
  webviewOptions.secretKey = DefaultSecretKey
  webviewOptions.sandbox = false
  webviewOptions.callbacks = WebviewCallbacks(
    decideNavigation: allowAllNavigation,
    event: noopWebviewEvent,
    eventBridge: noopWebviewPostMessage,
    hostBridge: hostBridge,
  )

  let (webviewId, webviewErr) = state.core.createWebview(webviewOptions)
  if webviewErr != ebNone:
    stderr.writeLine("[nim-particles] failed to create webview: ", webviewErr)
    discard state.core.closeWindow(windowId)
    return

  acquire(state.mutex)
  state.webviewId = webviewId
  release(state.mutex)

proc createUi() {.thread.} =
  {.cast(gcsafe).}:
    createUiImpl()

proc runMainProcess() =
  gQueueRunning.store(true)
  gGpuThreadStarted.store(false)
  gShuttingDown.store(false)

  var core: Core
  var coreErr: EbError
  (core, coreErr) = load()
  if coreErr != ebNone:
    stderr.writeLine("[nim-particles] failed to load Electrobun core: ", coreErr)
    quit 1
  defer: core.close()

  var bundlePaths: BundlePaths
  var bundleErr: EbError
  (bundlePaths, bundleErr) = resolveBundlePaths()
  if bundleErr != ebNone:
    stderr.writeLine("[nim-particles] failed to resolve bundle paths: ", bundleErr)
    quit 1
  defer: bundlePaths.deinit()

  var ownedAppInfo: OwnedAppInfo
  var appInfoErr: EbError
  (ownedAppInfo, appInfoErr) = resolveAppInfoFromBundle(bundlePaths)
  if appInfoErr != ebNone:
    stderr.writeLine("[nim-particles] failed to resolve app info: ", appInfoErr)
    quit 1
  defer: ownedAppInfo.deinit()
  let appInfo = ownedAppInfo.borrowed()

  var state = AppState(
    core: core,
    bundlePaths: bundlePaths,
    gpu: GpuShared(params: defaultSimParams(), width: 640, height: 420),
  )
  initLock(state.gpu.mutex)
  initLock(state.mutex)
  gState = addr state
  defer:
    gState = nil
    deinitLock(state.gpu.mutex)
    deinitLock(state.mutex)

  var uiThread: Thread[void]
  var queueThread: Thread[void]
  createThread(uiThread, createUi)
  createThread(queueThread, drainHostMessageQueue)
  defer: requestShutdown()

  let runErr = state.core.runMainThread(appInfo)
  if runErr != ebNone:
    stderr.writeLine("[nim-particles] main thread exited with error: ", runErr)

when isMainModule:
  runMainProcess()
