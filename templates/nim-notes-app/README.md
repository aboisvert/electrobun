# Nim notes app

Same notes UI as the Bun [`notes-app`](../notes-app/) template, with a Nim main process.

With Hutch directly (after `hutch electrobun sync`; requires Hutch ≥ 0.28.2
and a devkit release that ships the Nim toolchain and SDK entries):

```bash
hutch electrobun build --env=dev
hutch electrobun dev --env=dev
```

Or from the `package/` folder in the Electrobun repository, the repo-script
dev bundle remains the interim path for older Hutch releases and devkits:

```bash
hutch dev:template nim-notes-app
hutch run:nim-notes-app
```
