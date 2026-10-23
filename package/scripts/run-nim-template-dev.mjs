#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
	chmodSync,
	copyFileSync,
	cpSync,
	existsSync,
	mkdirSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { selectHutchBinary } from "./hutch-launcher.mjs";
import { readElectrobunConfig } from "./template-config.mjs";
import { nimCompilerOptions, resolveNimBinary } from "./nim-toolchain.mjs";
import { nimRuntimeLibraryPaths } from "./nim-runtime-libraries.mjs";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(packageRoot, "..");

function usage() {
	console.log(`Usage: node scripts/run-nim-template-dev.mjs <template-name> [options]

Build and run a Nim Electrobun template against the local package devkit.

Options:
  --hutch         Use Hutch (electrobun sync/build/run) instead of a repo-local
                  bundle. Requires a Hutch build with the unreleased Nim
                  integration (not published 0.28.2-canary.3) and a devkit with Nim
                  entries; set HUTCH_BINARY to override the resolved hutch.
  --build-only    Stage and compile without launching the app
  --no-devkit-build
                  Do not run package build.ts when dist/ is incomplete
  -h, --help      Show this help
`);
}

function parseArgs(argv) {
	let templateName = "";
	const options = {
		hutch: false,
		buildOnly: false,
		devkitBuild: true,
		help: false,
	};
	for (const arg of argv) {
		if (arg === "--hutch") options.hutch = true;
		else if (arg === "--build-only") options.buildOnly = true;
		else if (arg === "--no-devkit-build") options.devkitBuild = false;
		else if (arg === "-h" || arg === "--help") options.help = true;
		else if (!templateName) templateName = arg;
		else throw new Error(`Unknown argument: ${arg}`);
	}
	if (!templateName && !options.help) {
		throw new Error("Missing template name.");
	}
	return { templateName, options };
}

function run(logPrefix, label, command, args, cwd, env = process.env) {
	console.log(`[${logPrefix}] ${label}...`);
	const result = spawnSync(command, args, { cwd, env, stdio: "inherit" });
	if (result.error) throw result.error;
	if (result.status !== 0) {
		throw new Error(
			`${label} failed with exit code ${result.status ?? "unknown"}`,
		);
	}
}

function copyRuntimeLibraries(dist, destDir, app) {
	for (const path of nimRuntimeLibraryPaths(dist, app)) {
		cpSync(join(dist, path), join(destDir, basename(path)));
	}
}



function resolveSdkPath() {
	const built = join(packageRoot, "dist", "nim-sdk", "electrobun.nim");
	if (existsSync(built)) return join(packageRoot, "dist", "nim-sdk");
	return join(packageRoot, "src", "sdks", "nim");
}

function distRequirements(app) {
	const dist = join(packageRoot, "dist");
	const manifest = join(dist, "native-devkit.json");
	if (!existsSync(manifest)) return [manifest];
	return [
		...nimRuntimeLibraryPaths(dist, app).map((name) => join(dist, name)),
		join(dist, "preload-full.js"),
		join(dist, "preload-sandboxed.js"),
		join(dist, "nim-sdk", "electrobun.nim"),
	];
}

function missingDistArtifacts(app) {
	return distRequirements(app).filter((path) => !existsSync(path));
}

// Bun-like runtime resolution for running/bundling TS. The pinned hutch
// launcher (its engine is Bun-compatible and `hutch build` passes `bun build`
// flags straight through, verified for the flags used by bundleMainview) is
// preferred so template tasks use the same runtime that builds the devkit.
// Otherwise fall back to a package-local bun shim, then plain `bun` from PATH.
// (An earlier `~/.asdf/shims` arm here — plus an ASDF_BUN_VERSION env override
// in the bundle environment — hard-coded one machine's asdf setup and was
// removed rather than made generic.)
function resolveBunLikeBinary() {
	const hutch = selectHutchBinary();
	if (hutch !== "hutch" && existsSync(hutch)) return hutch;
	const local = join(
		packageRoot,
		"node_modules",
		".bin",
		process.platform === "win32" ? "bun.exe" : "bun",
	);
	if (existsSync(local)) return local;
	return process.platform === "win32" ? "bun.exe" : "bun";
}

function ensureDevkit(logPrefix, allowBuild, app) {
	const missing = missingDistArtifacts(app);
	if (missing.length === 0) return;

	if (!allowBuild) {
		throw new Error(
			`Electrobun devkit is incomplete. Missing:\n${missing.map((path) => `  - ${path}`).join("\n")}\nRun "hutch build.ts" from package/ first, or rerun without --no-devkit-build.`,
		);
	}

	console.log(
		`[${logPrefix}] Local devkit is missing runtime files; building package (first run can take several minutes)...`,
	);
	const buildScript = join(packageRoot, "build.ts");
	run(logPrefix, "Building Electrobun devkit", resolveBunLikeBinary(), [buildScript], packageRoot);

	const stillMissing = missingDistArtifacts(app);
	if (stillMissing.length > 0) {
		throw new Error(
			`Devkit build finished but required files are still missing:\n${stillMissing.map((path) => `  - ${path}`).join("\n")}`,
		);
	}
}

async function parseTemplateMetadata(templateRoot) {
	const config = await readElectrobunConfig(templateRoot);
	const configPath = join(templateRoot, "electrobun.config.ts");
	const app = config?.app ?? {};
	const name = typeof app.name === "string" ? app.name : undefined;
	const identifier =
		typeof app.identifier === "string" ? app.identifier : undefined;
	const version = typeof app.version === "string" ? app.version : undefined;
	const nimEntry =
		typeof config?.build?.nim?.entrypoint === "string"
			? config.build.nim.entrypoint
			: "src/nim/main.nim";
	const bundlesMainview = config?.build?.views?.mainview !== undefined;
	const target = process.platform === "darwin" ? "mac" : process.platform === "win32" ? "win" : "linux";
	const bundleWGPU = config?.build?.[target]?.bundleWGPU === true;
	if (!name || !identifier || !version) {
		throw new Error(`Could not read app metadata from ${configPath}`);
	}
	return { name, identifier, version, nimEntry, bundlesMainview, bundleWGPU };
}

function writeBundleMetadata(resourcesDir, app) {
	writeFileSync(
		join(resourcesDir, "version.json"),
		`${JSON.stringify(
			{
				identifier: app.identifier,
				name: app.name,
				version: app.version,
				channel: "dev",
			},
			null,
			2,
		)}\n`,
	);
	writeFileSync(
		join(resourcesDir, "build.json"),
		`${JSON.stringify(
			{
				mainProcess: "nim",
				defaultRenderer: "native",
				availableRenderers: ["native"],
				buildEnvironment: "dev",
				runtime: { exitOnLastWindowClosed: true },
			},
			null,
			2,
		)}\n`,
	);
}

function bundleMainview(logPrefix, templateRoot, viewsDir) {
	const entry = join(templateRoot, "src", "mainview", "index.ts");
	if (!existsSync(entry)) {
		throw new Error(`Missing mainview entrypoint at ${entry}`);
	}
	const viewSdk = join(packageRoot, "dist", "api", "browser", "index.ts");
	if (!existsSync(viewSdk)) {
		throw new Error(
			`Missing browser SDK at ${viewSdk}. Build the package devkit first.`,
		);
	}
	const tmpOut = join(templateRoot, "build", "mainview-bundle");
	rmSync(tmpOut, { recursive: true, force: true });
	mkdirSync(tmpOut, { recursive: true });
	run(
		logPrefix,
		"Bundling mainview",
		resolveBunLikeBinary(),
		[
			"build",
			entry,
			"--outdir",
			tmpOut,
			"--target",
			"browser",
			"--format",
			"esm",
			"--minify",
			`--alias:electrobun/view=${viewSdk}`,
		],
		templateRoot,
	);
	copyFileSync(join(tmpOut, "index.js"), join(viewsDir, "index.js"));
}

function syncMainviewAssets(logPrefix, templateRoot, viewsDir, bundlesMainview) {
	const htmlPath = join(templateRoot, "src", "mainview", "index.html");
	if (!existsSync(htmlPath)) {
		throw new Error(`Missing mainview HTML at ${htmlPath}`);
	}
	copyFileSync(htmlPath, join(viewsDir, "index.html"));
	const cssPath = join(templateRoot, "src", "mainview", "index.css");
	if (existsSync(cssPath)) {
		copyFileSync(cssPath, join(viewsDir, "index.css"));
	}
	if (bundlesMainview) {
		bundleMainview(logPrefix, templateRoot, viewsDir);
	}
}

function stageLocalBundle(logPrefix, templateRoot, app) {
	const dist = join(packageRoot, "dist");
	const bundleRoot = join(templateRoot, "build", "local-run");
	rmSync(bundleRoot, { recursive: true, force: true });

	const executableBase =
		process.platform === "win32" ? `${app.name}.exe` : app.name;

	if (process.platform === "darwin") {
		const macosDir = join(bundleRoot, `${app.name}.app`, "Contents", "MacOS");
		const resourcesDir = join(
			bundleRoot,
			`${app.name}.app`,
			"Contents",
			"Resources",
		);
		const viewsDir = join(resourcesDir, "app", "views", "mainview");
		mkdirSync(macosDir, { recursive: true });
		mkdirSync(viewsDir, { recursive: true });

		copyRuntimeLibraries(dist, macosDir, app);
		copyFileSync(join(dist, "preload-full.js"), join(resourcesDir, "preload-full.js"));
		copyFileSync(
			join(dist, "preload-sandboxed.js"),
			join(resourcesDir, "preload-sandboxed.js"),
		);
		syncMainviewAssets(logPrefix, templateRoot, viewsDir, app.bundlesMainview);
		writeBundleMetadata(resourcesDir, app);

		const executable = join(macosDir, executableBase);
		return {
			executable,
			nimEntry: join(templateRoot, app.nimEntry),
		};
	}

	const exeDir = join(bundleRoot, "bin");
	const resourcesDir = join(bundleRoot, "Resources");
	const viewsDir = join(resourcesDir, "app", "views", "mainview");
	mkdirSync(exeDir, { recursive: true });
	mkdirSync(viewsDir, { recursive: true });

	copyRuntimeLibraries(dist, exeDir, app);
	copyFileSync(join(dist, "preload-full.js"), join(resourcesDir, "preload-full.js"));
	copyFileSync(
		join(dist, "preload-sandboxed.js"),
		join(resourcesDir, "preload-sandboxed.js"),
	);
	syncMainviewAssets(logPrefix, templateRoot, viewsDir, app.bundlesMainview);
	writeBundleMetadata(resourcesDir, app);

	const executable = join(exeDir, executableBase);
	return {
		executable,
		nimEntry: join(templateRoot, app.nimEntry),
	};
}

function compileNimMain(logPrefix, templateRoot, executable, nimEntry) {
	const nim = resolveNimBinary().binary;
	const sdkPath = resolveSdkPath();
	const compiler = nimCompilerOptions();
	run(
		logPrefix,
		"Compiling Nim main process",
		nim,
		[
			"c",
			...compiler.args,
			"--threads:on",
			"--mm:orc",
			"--verbosity:0",
			`--path:${sdkPath}`,
			`-o:${executable}`,
			nimEntry,
		],
		templateRoot,
		compiler.env,
	);
	if (process.platform !== "win32") {
		chmodSync(executable, 0o755);
	}
}

function runLocal(logPrefix, templateRoot, app, options) {
	ensureDevkit(logPrefix, options.devkitBuild, app);
	const { executable, nimEntry } = stageLocalBundle(logPrefix, templateRoot, app);
	compileNimMain(logPrefix, templateRoot, executable, nimEntry);
	if (options.buildOnly) {
		console.log(`[${logPrefix}] Built ${executable}`);
		return;
	}
	console.log(`[${logPrefix}] Launching ${executable}`);
	run(logPrefix, "Running app", executable, [], dirname(executable));
}

// Hutch compiles Nim mains only when the resolved devkit release carries the
// toolchain and SDK layout entries; older releases fail with
// `NimNotSupportedByElectrobunRelease`. Prefer the repo-local dist (which the
// local-bundle route already depends on) so `--hutch` and local runs agree.
// The override also pins the Electrobun version the project must resolve to:
// floating templates target the stable channel (2.0.4), which mismatches this
// devkit, so route hutch through the npm-default selector the shim uses.
function distShipsNimDevkit() {
	let manifest = null;
	try {
		manifest = JSON.parse(
			readFileSync(join(packageRoot, "dist", "native-devkit.json"), "utf8"),
		);
	} catch {
		return null;
	}
	const shipping = Boolean(
		manifest?.toolchains?.nim?.defaultVersion &&
			manifest?.layout?.sdks?.nim &&
			typeof manifest?.product?.version === "string",
	);
	return shipping ? manifest.product.version : null;
}

function resolveHutchForTemplates() {
	const hutch = selectHutchBinary();
	if (hutch !== "hutch" && !existsSync(hutch)) {
		throw new Error(
			`Hutch binary not found: ${hutch}. Install Hutch or set HUTCH_BINARY to its path.`,
		);
	}
	return hutch;
}

function runWithHutch(logPrefix, templateRoot, options) {
	const hutch = resolveHutchForTemplates();
	const env = { ...process.env };
	if (!env.HUTCH_ELECTROBUN_DEVKIT_ROOT) {
		const devkitVersion = distShipsNimDevkit();
		if (devkitVersion) {
			env.HUTCH_ELECTROBUN_DEVKIT_ROOT = join(packageRoot, "dist");
			if (!env.HUTCH_DEFAULT_ELECTROBUN) {
				env.HUTCH_DEFAULT_ELECTROBUN = devkitVersion;
			}
		}
	}
	run(logPrefix, "Syncing Hutch project files", hutch, ["electrobun", "sync", "--env=dev"], templateRoot, env);
	run(logPrefix, "Building with Hutch", hutch, ["electrobun", "build", "--env=dev"], templateRoot, env);
	if (options.buildOnly) {
		console.log(`[${logPrefix}] Built with Hutch (--build-only); not launching.`);
		return;
	}
	run(logPrefix, "Running with Hutch", hutch, ["electrobun", "dev", "--env=dev"], templateRoot, env);
}

async function main() {
	if (process.platform === "win32" && process.arch === "arm64") {
		console.log("Nim template dev skipped: Windows ARM64 is unsupported.");
		process.exit(0);
	}

	const { templateName, options } = parseArgs(process.argv.slice(2));
	if (options.help) {
		usage();
		return;
	}

	const templateRoot = join(repositoryRoot, "templates", templateName);
	const logPrefix = templateName;
	if (!existsSync(templateRoot)) {
		throw new Error(`Template directory not found: ${templateRoot}`);
	}

	const app = await parseTemplateMetadata(templateRoot);

	if (options.hutch) {
		runWithHutch(logPrefix, templateRoot, options);
	} else {
		runLocal(logPrefix, templateRoot, app, options);
	}
}

try {
	await main();
} catch (error) {
	console.error(error instanceof Error ? error.message : String(error));
	process.exit(1);
}
