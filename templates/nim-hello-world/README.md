# Nim hello world

Minimal Electrobun app with a Nim main process. See the
[hello world guide](https://electrobun.dev/electrobun/guides/hello-world-nim/).

With Hutch directly (after `hutch electrobun sync` in this directory; requires
Hutch ≥ 0.28.2 and a devkit release that ships the Nim toolchain and SDK
entries):

```bash
hutch run dev
```

Or from the `package/` folder in the Electrobun repository, the repo-script
dev bundle remains the interim path for older Hutch releases and devkits:

```bash
hutch run:nim-hello-world
```
