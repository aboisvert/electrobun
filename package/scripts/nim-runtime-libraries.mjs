import { readFileSync } from "node:fs";
import { join } from "node:path";

export function nimRuntimeLibraryPaths(dist, { bundleWGPU = false } = {}) {
	const manifest = JSON.parse(readFileSync(join(dist, "native-devkit.json"), "utf8"));
	const runtime = manifest.layout?.runtime;
	const paths = [runtime?.coreLibrary, runtime?.nativeWrapper, runtime?.asarLibrary];
	if (bundleWGPU) {
		const auxiliary = runtime?.wgpuAuxiliaryLibraries ?? [];
		if (!Array.isArray(auxiliary)) throw new Error("Invalid WGPU auxiliary library list");
		paths.push(runtime?.wgpuLibrary, ...auxiliary);
	}
	for (const path of paths) {
		if (typeof path !== "string" || !path || path.includes("\\") ||
			path.includes(":") || path.split("/").some((part) => !part || part === "." || part === "..")) {
			throw new Error(`Invalid devkit runtime library path: ${JSON.stringify(path)}`);
		}
	}
	return [...new Set(paths)];
}
