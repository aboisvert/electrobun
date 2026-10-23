import type { ElectrobunConfig } from "electrobun";

export default {
	app: {
		name: "nim-notes",
		identifier: "nimnotes.electrobun.dev",
		version: "0.0.1",
	},
	build: {
		mainProcess: "nim",
		nim: {
			entrypoint: "src/nim/main.nim",
		},
		views: {
			mainview: {
				entrypoint: "src/mainview/index.ts",
			},
		},
		copy: {
			"src/mainview/index.html": "views/mainview/index.html",
			"src/mainview/index.css": "views/mainview/index.css",
		},
		mac: {
			bundleCEF: false,
		},
		linux: {
			bundleCEF: false,
		},
		win: {
			bundleCEF: false,
		},
	},
} satisfies ElectrobunConfig;
