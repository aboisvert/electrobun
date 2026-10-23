import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { nimRuntimeLibraryPaths } from "./nim-runtime-libraries.mjs";

test("stages manifest runtime libraries and optional Dawn dependencies", (t) => {
	const dist = mkdtempSync(join(tmpdir(), "nim-runtime-"));
	t.after(() => rmSync(dist, { recursive: true, force: true }));
	const runtime = {
		coreLibrary: "ElectrobunCore.dll", nativeWrapper: "libNativeWrapper.dll",
		asarLibrary: "libasar.dll", wgpuLibrary: "webgpu_dawn.dll",
		wgpuAuxiliaryLibraries: ["d3dcompiler_47.dll"],
	};
	const write = () => writeFileSync(join(dist, "native-devkit.json"), JSON.stringify({ layout: { runtime } }));
	write();
	assert.deepEqual(nimRuntimeLibraryPaths(dist), ["ElectrobunCore.dll", "libNativeWrapper.dll", "libasar.dll"]);
	assert.deepEqual(nimRuntimeLibraryPaths(dist, { bundleWGPU: true }), [
		"ElectrobunCore.dll", "libNativeWrapper.dll", "libasar.dll", "webgpu_dawn.dll", "d3dcompiler_47.dll",
	]);
	for (const invalid of [undefined, "../outside", "/absolute", "C:/outside", "a\\b"]) {
		runtime.wgpuLibrary = invalid;
		write();
		assert.throws(() => nimRuntimeLibraryPaths(dist, { bundleWGPU: true }), /Invalid devkit/);
	}
});
