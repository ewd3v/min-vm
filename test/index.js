import { minify } from "../src"
await Bun.write(
    "test/output.luau",
    await minify(await Bun.file("test/input.luau").text())
)
