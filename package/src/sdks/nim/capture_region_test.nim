import std/unittest
import electrobun

var captureTestX: float64
var captureTestY: float64
var captureTestWidth: uint32
var captureTestHeight: uint32

proc captureRegionTestStub(
  x, y: float64; width, height: uint32; outRgba: pointer; outLen: uint64
): bool {.cdecl, raises: [].} =
  captureTestX = x
  captureTestY = y
  captureTestWidth = width
  captureTestHeight = height
  let pixels = cast[ptr UncheckedArray[byte]](outRgba)
  for i in 0 ..< int(outLen):
    pixels[i] = byte(i mod 251)
  true

proc captureRegionFailureStub(
  x, y: float64; width, height: uint32; outRgba: pointer; outLen: uint64
): bool {.cdecl, raises: [].} =
  discard x; discard y; discard width; discard height
  discard outRgba; discard outLen
  false

suite "capture region":
  test "allocates rgba and floors origin":
    var core = Core()
    core.symbols.captureScreenRegion = captureRegionTestStub
    let (pixels, err) = core.captureScreenRegion(Rect(x: 12.75, y: -3.125, width: 2, height: 3))
    check err == ebNone
    check pixels.len == 24
    check captureTestX == 12.0
    check captureTestY == -4.0
    check captureTestWidth == 2'u32
    check captureTestHeight == 3'u32
    check pixels[23] == byte(23)

  test "rejects invalid dimensions":
    var core = Core()
    let (_, zeroErr) = core.captureScreenRegion(Rect(width: 0, height: 1))
    let (_, fractionalErr) = core.captureScreenRegion(Rect(width: 1.5, height: 1))
    let (_, overflowErr) = core.captureScreenRegion(Rect(width: 4294967295'f64, height: 4294967295'f64))
    check zeroErr == ebInvalidScreenCaptureRegion
    check fractionalErr == ebInvalidScreenCaptureRegion
    check overflowErr == ebInvalidScreenCaptureRegion

  test "releases pixels when native capture fails":
    var core = Core()
    core.symbols.captureScreenRegion = captureRegionFailureStub
    let (pixels, err) = core.captureScreenRegion(Rect(width: 2, height: 3))
    check pixels.len == 0
    check err == ebElectrobunCoreFailure
