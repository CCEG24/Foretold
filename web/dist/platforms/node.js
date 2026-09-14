// @ts-check
import { fileURLToPath } from "node:url";
import { Worker, parentPort } from "node:worker_threads";
import { MODULE_PATH } from "../instantiate.js"


/** @type {import('./node.d.ts').defaultNodeSetup} */
export async function defaultNodeSetup(options = {}) {
    const path = await import("node:path");
    const { fileURLToPath } = await import("node:url");
    const { readFile } = await import("node:fs/promises")

    const args = options.args ?? process.argv.slice(2)
    const rootFs = new Map();
    const wasi = new WASI(/* args */[MODULE_PATH, ...args], /* env */[], /* fd */[
        new OpenFile(new File([])), // stdin
        ConsoleStdout.lineBuffered((stdout) => {
            console.log(stdout);
        }),
        ConsoleStdout.lineBuffered((stderr) => {
            console.error(stderr);
        }),
        new PreopenDirectory("/", rootFs),
    ], { debug: false })
    const pkgDir = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
    const module = await WebAssembly.compile(new Uint8Array(await readFile(path.join(pkgDir, MODULE_PATH))))

    return {
        module,
    }
}
