import type { ElectrobunConfig } from "electrobun";

export default {
	app: {
		name: "nim-hello",
		identifier: "nimhello.example.dev",
		version: "0.0.1",
	},
	build: {
		mainProcess: "nim",
		nim: {
			entrypoint: "src/nim/main.nim",
		},
		copy: {
			"src/mainview/index.html": "views/mainview/index.html",
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
