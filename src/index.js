import vm from "./vm"
import { parse as parseSettings } from "./settings"
import { ZstdInit, ZstdStream } from "@oneidentity/zstd-js"

console.log("Initializing...")
await ZstdInit()
console.log("Initialized")

export const minify = async (source, settings) => {
    settings = parseSettings(settings)

    const compileResponse = await fetch(
        "https://luau-compile.shuttleapp.rs/compile",
        {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                source,
                options: {
                    optimization_level: 1,
                    debug_level: 1,
                    type_info_level: 0,
                    coverage_level: 0,
                    vector_lib: "Vector3",
                    vector_ctor: "new",
                    vector_type: "Vector3",
                },
            }),
        }
    )

    if (!compileResponse.ok) {
        throw Error(`Error while compiling: ${await compileResponse.text()}`)
    }

    const zbase64 = Buffer.from(
        ZstdStream.compress(await compileResponse.bytes(), settings.zstdLevel),
        "utf8"
    ).toString("base64")

    return vm.replace("__bytecode_zbase64__", zbase64)
}
