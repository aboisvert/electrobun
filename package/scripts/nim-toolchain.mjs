// Shared Nim toolchain resolution for plain-Node dev-facing scripts.
//
// package/build.ts vendors the pinned Nim release into package/vendors/nim
// (version pinned in ../src/shared/nim-version.ts, trusted by
// src/shared/vendored-toolchain-host.ts via the same first-line regex) and
// Electrobun must not use an arbitrary system Nim. These dev scripts used to
// fall back silently to whatever `nim` was on PATH; resolveNimBinary() now
// prefers the vendored binary and, when it is missing, only accepts a system
// `nim` that reports the exact pinned version:
//   - matching system nim: used, with a one-line warning on stderr;
//   - missing or version-mismatched system nim: throws and points at the
//     package build, which vendors the pinned toolchain.

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { NIM_VERSION } from "../src/shared/nim-version.ts";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// Keep in sync with verifyNimToolchain in ../src/shared/vendored-toolchain-host.ts.
const NIM_VERSION_REGEX = /^Nim Compiler Version (\d+\.\d+\.\d+)/;

export function vendoredNimBinary() {
	return join(
		packageRoot,
		"vendors",
		"nim",
		"bin",
		process.platform === "win32" ? "nim.exe" : "nim",
	);
}

const INSTRUCTIONS = `Run the package build to vendor the pinned Nim ${NIM_VERSION} toolchain: cd package && hutch build.ts (or: bun build.ts).`;

export function resolveNimBinary() {
	const vendored = vendoredNimBinary();
	if (existsSync(vendored)) {
		return { binary: vendored, kind: "vendored", version: NIM_VERSION };
	}

	const systemBinary = process.platform === "win32" ? "nim.exe" : "nim";
	const probe = spawnSync(systemBinary, ["--version"], {
		encoding: "utf8",
		windowsHide: true,
	});
	const firstLine =
		probe && !probe.error && probe.status === 0
			? ((probe.stdout ?? "").split(/\r?\n/, 1)[0]?.trim() ?? "")
			: "";
	const version = NIM_VERSION_REGEX.exec(firstLine)?.[1];
	if (!version) {
		throw new Error(
			`Vendored Nim toolchain is missing and no usable system '${systemBinary}' was found (expected Nim ${NIM_VERSION}). ${INSTRUCTIONS}`,
		);
	}
	if (version !== NIM_VERSION) {
		throw new Error(
			`Vendored Nim toolchain is missing and the system nim reports ${version} but Electrobun pins ${NIM_VERSION}. ${INSTRUCTIONS}`,
		);
	}
	process.stderr.write(
		`[nim] WARNING: using system nim ${version} (vendored toolchain missing; run the package build to vendor it)\n`,
	);
	return { binary: systemBinary, kind: "system", version };
}
