#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
	copyFileSync,
	existsSync,
	mkdtempSync,
	mkdirSync,
	readdirSync,
	rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
	readElectrobunConfig,
	templateNimEntrypoint,
} from "./template-config.mjs";
import { resolveNimBinary } from "./nim-toolchain.mjs";

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const repositoryRoot = resolve(packageRoot, "..");
const templatesRoot = join(repositoryRoot, "templates");

if (process.platform === "win32" && process.arch === "arm64") {
	console.log("Nim template tests skipped: Windows ARM64 is unsupported.");
	process.exit(0);
}

const nimBinary = resolveNimBinary().binary;

function templateNimPackages() {
	return readdirSync(templatesRoot, { withFileTypes: true })
		.filter((entry) => entry.isDirectory() && entry.name.startsWith("nim-"))
		.map((entry) => ({
			name: entry.name,
			nimDir: join(templatesRoot, entry.name, "src", "nim"),
		}))
		.filter((template) => existsSync(template.nimDir))
		.sort((left, right) => left.name.localeCompare(right.name));
}

async function readMainEntrypoint(templateName) {
	const config = await readElectrobunConfig(join(templatesRoot, templateName));
	return templateNimEntrypoint(config);
}

function resolveSdkCollection() {
	const builtCollection = join(packageRoot, "dist", "nim-sdk");
	if (existsSync(join(builtCollection, "electrobun.nim"))) {
		return { path: builtCollection, cleanup: null };
	}

	const sourceSdk = join(packageRoot, "src", "sdks", "nim", "electrobun.nim");
	if (!existsSync(sourceSdk)) {
		throw new Error(`Electrobun Nim SDK source not found at ${sourceSdk}`);
	}

	const stagingRoot = mkdtempSync(join(tmpdir(), "electrobun-nim-tests-"));
	copyFileSync(sourceSdk, join(stagingRoot, "electrobun.nim"));
	return { path: stagingRoot, cleanup: stagingRoot };
}

function removeTemporaryDirectory(path) {
	try {
		rmSync(path, {
			recursive: true,
			force: true,
			maxRetries: 40,
			retryDelay: 250,
		});
	} catch (error) {
		if (process.platform === "win32" && error?.code === "EPERM") return;
		throw error;
	}
}

function nimCommonArgs(sdkPath) {
	return [
		"--threads:on",
		"--mm:orc",
		"--verbosity:0",
		"--hint:Processing:on",
		`--path:${sdkPath}`,
	];
}

function runNim(cwd, args) {
	const result = spawnSync(nimBinary, args, { cwd, stdio: "inherit" });
	if (result.error) throw result.error;
	if (result.status !== 0) {
		throw new Error(
			`Nim command failed in ${cwd} with exit code ${result.status ?? "unknown"}`,
		);
	}
}

const templates = templateNimPackages();
if (templates.length === 0) {
	throw new Error("No Nim template packages were found");
}

const sdkCollection = resolveSdkCollection();
const executionRoot = mkdtempSync(join(tmpdir(), "electrobun-nim-run-"));
try {
	for (const template of templates) {
		console.log(`Testing ${template.name}...`);
		const scratchDir = join(executionRoot, template.name);
		mkdirSync(scratchDir, { recursive: true });
		const testFiles = readdirSync(template.nimDir)
			.filter((file) => file.endsWith("_test.nim"))
			.sort();
		for (const testFile of testFiles) {
			runNim(template.nimDir, [
				...nimCommonArgs(sdkCollection.path),
				"c",
				"-r",
				`-o:${join(scratchDir, testFile.slice(0, -".nim".length))}`,
				testFile,
			]);
		}

		const mainEntry = await readMainEntrypoint(template.name);
		const mainPath = join(template.nimDir, mainEntry);
		if (!existsSync(mainPath)) {
			throw new Error(`${template.name} missing main entrypoint at ${mainPath}`);
		}
		runNim(template.nimDir, [
			...nimCommonArgs(sdkCollection.path),
			"check",
			mainEntry,
		]);
	}
} finally {
	if (sdkCollection.cleanup) {
		removeTemporaryDirectory(sdkCollection.cleanup);
	}
	removeTemporaryDirectory(executionRoot);
}

console.log(`Nim template tests passed (${templates.length} packages).`);
