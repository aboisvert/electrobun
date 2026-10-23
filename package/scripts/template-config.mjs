// Shared reader for template `electrobun.config.ts` files.
//
// Template configs use type-only imports (`import type ... from "electrobun"`)
// and `satisfies`, so their exported object can be evaluated with a dynamic
// `import()` on Node >= 23.6 (type stripping is on by default) as well as under
// the hutch/bun runner. Importing is preferred over text scraping; when a
// config cannot be imported (for example it uses extensionless relative
// specifiers that plain Node cannot resolve), the comment-stripped,
// brace-matched text fallback below keeps the tooling working.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const NIM_ENTRYPOINT_DEFAULT = "src/nim/main.nim";

function stripComments(source) {
	let result = "";
	let index = 0;
	while (index < source.length) {
		const char = source[index];
		const next = source[index + 1];
		if (char === '"' || char === "'" || char === "`") {
			result += char;
			index += 1;
			while (index < source.length) {
				if (source[index] === "\\") {
					result += source.slice(index, index + 2);
					index += 2;
					continue;
				}
				result += source[index];
				const closingQuote = source[index] === char;
				index += 1;
				if (closingQuote) break;
			}
			continue;
		}
		if (char === "/" && next === "/") {
			while (index < source.length && source[index] !== "\n") index += 1;
			continue;
		}
		if (char === "/" && next === "*") {
			const end = source.indexOf("*/", index + 2);
			index = end === -1 ? source.length : end + 2;
			continue;
		}
		result += char;
		index += 1;
	}
	return result;
}

function objectBlock(source, key) {
	const match = new RegExp(`(?:^|[\\r\\n])[\\t ]*${key}[\\t ]*:`).exec(source);
	if (!match) return undefined;
	let index = match.index + match[0].length;
	while (index < source.length && /[\s]/.test(source[index])) index += 1;
	if (source[index] !== "{") return undefined;
	const start = index;
	let depth = 0;
	while (index < source.length) {
		const char = source[index];
		if (char === '"' || char === "'" || char === "`") {
			index += 1;
			while (index < source.length) {
				if (source[index] === "\\") {
					index += 2;
					continue;
				}
				const closing = source[index] === char;
				index += 1;
				if (closing) break;
			}
			continue;
		}
		if (char === "{") depth += 1;
		else if (char === "}") {
			depth -= 1;
			if (depth === 0) return source.slice(start, index + 1);
		}
		index += 1;
	}
	return undefined;
}

function stringField(source, key) {
	const pattern = new RegExp(
		`(?:^|[\\r\\n{,\\t ])${key}[\\t ]*:[\\t ]*(?:"([^"\\r\\n]*)"|'([^'\\r\\n]*)')`,
	);
	const match = pattern.exec(source);
	return match?.[1] ?? match?.[2];
}

// Parses comment-stripped config source into the same shape callers read from
// the imported config object. Unresolvable fields stay undefined.
function parseConfigSource(source) {
	const code = stripComments(source);
	const app = objectBlock(code, "app");
	const build = objectBlock(code, "build");
	const nim = build === undefined ? undefined : objectBlock(build, "nim");
	const views = build === undefined ? undefined : objectBlock(build, "views");
	const entrypoint = nim === undefined ? undefined : stringField(nim, "entrypoint");
	const mainview =
		views !== undefined && /^[\t ]*mainview[\t ]*:/m.test(views);
	return {
		app: {
			name: app === undefined ? undefined : stringField(app, "name"),
			identifier:
				app === undefined ? undefined : stringField(app, "identifier"),
			version:
				app === undefined ? undefined : stringField(app, "version"),
		},
		build: {
			mainProcess:
				build === undefined ? undefined : stringField(build, "mainProcess"),
			nim: entrypoint === undefined ? undefined : { entrypoint },
			views: mainview ? { mainview: {} } : undefined,
		},
	};
}

// Returns the exported config object for a template directory, or undefined
// when the directory has no `electrobun.config.ts` or it cannot be resolved.
export async function readElectrobunConfig(templateDir) {
	const configPath = join(templateDir, "electrobun.config.ts");
	if (!existsSync(configPath)) {
		return undefined;
	}
	try {
		const module = await import(pathToFileURL(configPath).href);
		const config = module?.default;
		if (config !== null && typeof config === "object") {
			return config;
		}
	} catch {
		// Fall through to the text fallback below.
	}
	return parseConfigSource(readFileSync(configPath, "utf8"));
}

export function templateNimEntrypoint(config) {
	const entrypoint = config?.build?.nim?.entrypoint;
	if (
		typeof entrypoint === "string" &&
		entrypoint.length > 0
	) {
		return entrypoint;
	}
	return NIM_ENTRYPOINT_DEFAULT;
}

export { NIM_ENTRYPOINT_DEFAULT };
