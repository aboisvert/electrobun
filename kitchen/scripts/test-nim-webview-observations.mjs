import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveNimBinary } from "../../package/scripts/nim-toolchain.mjs";

const kitchen = resolve(dirname(fileURLToPath(import.meta.url)), "..");
// Explicitly provided paths are trusted as-is (no version check); the shared
// helper otherwise prefers the vendored toolchain and only falls back to a
// system nim matching the pinned version (see package/scripts/nim-toolchain.mjs).
const nim = process.env.ELECTROBUN_NIM || resolveNimBinary().binary;
if (process.env.ELECTROBUN_NIM && !existsSync(nim)) {
	throw new Error(`Nim compiler is missing: ${nim}. Run the Electrobun package build first.`);
}
const version = spawnSync(nim, ["--version"], { encoding: "utf8", windowsHide: true });
if (version.error || version.status !== 0) {
	throw new Error(`Could not identify Nim compiler: ${version.error?.message || version.stderr}`);
}
const versionLine = version.stdout.split("\n").find((line) => line.startsWith("Nim Compiler Version"));
if (!versionLine) throw new Error("Nim compiler did not report its version");

const temporaryRoot = realpathSync(tmpdir());
const scratch = mkdtempSync(join(temporaryRoot, "electrobun-nim-observations-"));
const sdkPath = join(kitchen, "..", "package", "src", "sdks", "nim");

function run(command, args) {
	const result = spawnSync(command, args, {
		cwd: scratch,
		stdio: "inherit",
		windowsHide: true,
		env: process.env,
	});
	if (result.error || result.status !== 0) {
		throw new Error(`Nim callback isolation tests failed (${result.error?.message || result.status})`);
	}
}

try {
	console.log(`[nim-observations] ${versionLine.trim()}`);
	for (const suite of ["webview_observations", "worker_threads_test"]) {
		const executable = join(scratch, suite + (process.platform === "win32" ? ".exe" : ""));
		console.log(`[nim-observations] Test executable: ${executable}`);
		run(nim, [
			"c",
			"--threads:on",
			"--mm:orc",
			"-o:" + executable,
			`--path:${sdkPath}`,
			join(kitchen, "src", "nim", `${suite}.nim`),
		]);
		run(executable, []);
	}
} catch (error) {
	console.error(`[nim-observations] Retained failed test files: ${scratch}`);
	throw error;
}
