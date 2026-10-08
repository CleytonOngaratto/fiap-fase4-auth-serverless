import { readFileSync } from "node:fs";
import { createHash, createPublicKey, createPrivateKey } from "node:crypto";

const path = process.argv[2];
if (!path) {
  console.error("uso: node scripts/key-fingerprint.mjs <arquivo.pem>");
  process.exit(2);
}

const pem = readFileSync(path, "utf8").replace(/\r/g, "");

let publicKey;
try {
  publicKey = pem.includes("PRIVATE KEY")
    ? createPublicKey(createPrivateKey(pem))
    : createPublicKey(pem);
} catch (error) {
  console.error(`PEM invalido em ${path}: ${error.message}`);
  process.exit(1);
}

const der = publicKey.export({ type: "spki", format: "der" });
console.log(createHash("sha256").update(der).digest("hex"));
