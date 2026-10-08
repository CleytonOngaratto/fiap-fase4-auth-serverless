const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
  args.set(process.argv[i].replace(/^--/, ""), process.argv[i + 1]);
}

const cpf = args.get("cpf");
if (!cpf) {
  console.error("uso: node scripts/invoke-local.mjs --cpf <cpf> [--raw <body cru>]");
  process.exit(2);
}

const defaults = {
  DB_HOST: "localhost",
  DB_PORT: "5433",
  DB_NAME: "oficina_db",
  DB_USER: "postgres",
  DB_PASSWORD: "postgres",
  DB_SSL: "disable",
  JWT_ISSUER: "https://oficina-api.com",
  JWT_TTL_SECONDS: "3600",
  JWT_PRIVATE_KEY_PARAM: "/fase4/jwt/private-key",
  DB_PASSWORD_PARAM: "/fase4/rds/password",
  AWS_REGION: "us-east-1",
};
for (const [key, value] of Object.entries(defaults)) {
  process.env[key] ??= value;
}

// Import dinâmico DEPOIS do ambiente: config.mjs lê process.env no carregamento do módulo.
const { handler } = await import("../lambda/index.mjs");

const response = await handler({
  version: "2.0",
  rawPath: "/auth",
  requestContext: { http: { method: "POST", path: "/auth" } },
  headers: { "content-type": "application/json" },
  body: args.get("raw") ?? JSON.stringify({ cpf }),
  isBase64Encoded: false,
});

console.log(JSON.stringify({ statusCode: response.statusCode, body: JSON.parse(response.body) }));

process.exit(response.statusCode === 200 ? 0 : 1);
