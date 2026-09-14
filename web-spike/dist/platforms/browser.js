// @ts-check
import { MODULE_PATH } from "../instantiate.js"


/** @type {import('./browser.d.ts').defaultBrowserSetup} */
export async function defaultBrowserSetup(options) {

    return {
        module: options.module,
    }
}
