import { compress } from "../src"
await Bun.write(
    "test/output.luau",
    await compress(await Bun.file("test/input.luau").text())
)
