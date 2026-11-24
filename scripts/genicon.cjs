// Genera webapp/CinghyIcon.js dai livelli marroni e scuri di un SVG a colori del cinghiale.
// Uso: npm run icon   (oppure: node scripts/genicon.cjs <svg> <output.js>)
const fs = require("fs");
const [srcFile, outFile] = process.argv.slice(2);
const src = fs.readFileSync(srcFile, "utf8");
const all = [...src.matchAll(/<path[^>]*d="([^"]*)"[^>]*fill="([^"]*)"/g)].map(m => m[1]);
const LAYERS = [0, 1, 2, 4, 7, 11, 12]; // livelli marroni e scuri: testa piena, occhiali e muso in negativo
const TOLERANCE = 1.2; // unità del viewBox (372 = 16-32 px): sotto il mezzo pixel anche a 256 px
function rdp(pts) {
  // Ramer-Douglas-Peucker: toglie i punti che deviano meno di TOLERANCE dalla linea
  if (pts.length < 3) return pts;
  const [a, b] = [pts[0], pts[pts.length - 1]];
  const len = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
  let iMax = 0, dMax = 0;
  for (let i = 1; i < pts.length - 1; i++) {
    const dist = Math.abs((b[0] - a[0]) * (a[1] - pts[i][1]) - (a[0] - pts[i][0]) * (b[1] - a[1])) / len;
    if (dist > dMax) { dMax = dist; iMax = i; }
  }
  return dMax <= TOLERANCE ? [a, b] : rdp(pts.slice(0, iMax + 1)).slice(0, -1).concat(rdp(pts.slice(iMax)));
}
function simplify(d) {
  // coordinate intere, senza punti ripetuti
  return d.split(/(?=[MZ])/).map(seg => {
    if (seg[0] === "Z") return "Z";
    const pts = seg.slice(1).split("L").map(p => p.trim().split(/[ ,]+/).map(n => +n));
    const r = rdp(pts).map(p => p.map(Math.round));
    const out = r.filter((p, i) => i === 0 || p[0] !== r[i - 1][0] || p[1] !== r[i - 1][1]);
    return out.length > 2 ? "M" + out.map(p => p.join(" ")).join("L") : "";
  }).join("").replace(/Z+/g, "Z").replace(/^Z|(?<=Z)Z/g, "");
}
const paths = LAYERS.map(i => simplify(all[i]));
const js = `sap.ui.define(["@ui5/webcomponents-base/dist/asset-registries/Icons"], function (Icons) {
  "use strict";

  // Generato da scripts/genicon.cjs (npm run icon): non modificare a mano.
  // Il registro delle icone dei Web Components è condiviso: la shell bar lo vede.
  const NAME = "regesta/cinghy";
  Icons.registerIcon("cinghy", {
    collection: "regesta",
    packageName: "regesta.cinghy",
    viewBox: "70 20 372 372",
    pathData: ${JSON.stringify(paths)}
  });

  return NAME;
});
`;
fs.writeFileSync(outFile, js);
console.log("byte pathData:", paths.join("").length);
