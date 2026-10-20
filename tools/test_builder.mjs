// Runs the builder page's core (the part between its "==== core" and
// "==== page" markers) on files, as the page would, and writes the ROM.
// usage: node tools/test_builder.mjs PAGE.html OUT.rom FILE...
import { readFileSync, writeFileSync } from "node:fs";
const [page, out, ...inputs] = process.argv.slice(2);
const html = readFileSync(page, "utf8");
const core = html.slice(html.indexOf("// ==== core"), html.indexOf("// ==== page"));
const { findSource, applyBps, patchBytes } = new Function(core + "; return {findSource, applyBps, patchBytes};")();
const files = inputs.map(name => ({ name, bytes: new Uint8Array(readFileSync(name)) }));
const { source, missing, archive } = await findSource(files);
if (!source) { console.log(`no source (missing ${missing.join(", ")}; archive ${archive})`); process.exit(2); }
const { rom, meta } = applyBps(patchBytes(), source);
writeFileSync(out, rom);
console.log(`${meta}: ${rom.length} bytes`);
