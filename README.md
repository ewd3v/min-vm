# zluau-vm

A Luau code compression utility<br>(Luau bytecode + zstd compression + minified [Fiu vm](https://github.com/rce-incorporated/Fiu) fork = compression)

Not an obfuscator, but I suppose it works as one.<br>(Notice: extracting bytecode from the output is easy, but the full source code will be hidden).

## Getting Started

(Requires [Bun](https://bun.sh), might work with npm / node, but I haven't tested.)

To install dependencies:

```bash
bun install
```

## Testing

Check the `/test` directory and add a `input.luau` file, then run:

```bash
bun run test
```

You should now see a `output.luau` containing your processed code.

## VM

If you want to make modifications to the vm, then first get the proper tooling with [Rokit](https://github.com/rojo-rbx/rokit):

```bash
rokit install
```

(You can also just manually install [darklua](https://github.com/seaofvoices/darklua).)

<br>

After making changes to `vm/vm.luau` run:

```bash
bun run gen
```

This should generate a `vm_output.luau` file, copy it's contents and paste it into the default export of `src/vm.js`

### Notes

This project was created using `bun init` in bun v1.1.42. [Bun](https://bun.sh) is a fast all-in-one JavaScript runtime.

Uses [http requests to compile](https://github.com/Open-SB/luau-compile) Luau (check [src/index.js](https://github.com/ewd3v/zluau-vm/blob/main/src/index.js)).

The vm being used for compressed files is a fork of [Fiu](https://github.com/rce-incorporated/Fiu)
