import assert from "node:assert/strict";
import test from "node:test";
import { templateNimEntrypoint } from "./template-config.mjs";

test("Nim entrypoints are relative to the project, including the default", () => {
	assert.equal(templateNimEntrypoint({}), "src/nim/main.nim");
	assert.equal(templateNimEntrypoint({ build: { nim: { entrypoint: "src/nim/custom.nim" } } }), "src/nim/custom.nim");
	assert.equal(templateNimEntrypoint({ build: { nim: { entrypoint: "native/main.nim" } } }), "native/main.nim");
});
