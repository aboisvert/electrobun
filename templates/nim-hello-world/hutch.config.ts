export default {
	scripts: {
		dev: ["hutch", "electrobun", "dev", "--watch"],
		build: ["hutch", "electrobun", "build", "--env=stable"],
		run: ["hutch", "electrobun", "run"],
	},
};
