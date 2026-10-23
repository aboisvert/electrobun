import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const kitchen = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const vendorNim = join(
	kitchen,
	"..",
	"package",
	"vendors",
	"nim",
	"bin",
	process.platform === "win32" ? "nim.exe" : "nim",
);
const nim = process.env.ELECTROBUN_NIM || (existsSync(vendorNim) ? vendorNim : "nim");
if (nim !== "nim" && !existsSync(nim)) {
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
const executable = join(scratch, process.platform === "win32" ? "observations.exe" : "observations");
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
	console.log(`[nim-observations] Test executable: ${executable}`);
	run(nim, [
		"c",
		"-o:" + executable,
		`--path:${sdkPath}`,
		join(kitchen, "src", "nim", "webview_observations.nim"),
	]);
	run(executable, []);
} catch (error) {
	console.error(`[nim-observations] Retained failed test files: ${scratch}`);
	throw error;
}
