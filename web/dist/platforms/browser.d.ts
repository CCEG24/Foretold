import type { InstantiateOptions, ModuleSource } from "../instantiate.js"

export function defaultBrowserSetup(options: {
    module: ModuleSource,
}): Promise<InstantiateOptions>

export function createDefaultWorkerFactory(preludeScript?: string): (module: WebAssembly.Module, memory: WebAssembly.Memory, startArg: any) => Worker
