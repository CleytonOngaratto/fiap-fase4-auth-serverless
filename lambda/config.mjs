import { SSMClient, GetParametersCommand } from "@aws-sdk/client-ssm";

const num = (value, fallback) => (value ? Number(value) : fallback);

export const config = {
  os: {
    internalUrl: process.env.OS_INTERNAL_URL,
    timeoutMs: num(process.env.OS_TIMEOUT_MS, 3000),
  },
  jwt: {
    issuer: process.env.JWT_ISSUER,
    ttlSeconds: num(process.env.JWT_TTL_SECONDS, 3600),
  },
  params: {
    privateKey: process.env.JWT_PRIVATE_KEY_PARAM,
    serviceToken: process.env.OS_SERVICE_TOKEN_PARAM,
  },
  // Só o harness local preenche: o Terraform nunca define o valor, apenas o nome do parâmetro.
  overrides: {
    privateKey: process.env.JWT_PRIVATE_KEY,
    serviceToken: process.env.OS_SERVICE_TOKEN,
  },
};

let cached;

async function fetchSecrets() {
  const wanted = [
    { key: "privateKey", name: config.params.privateKey },
    { key: "serviceToken", name: config.params.serviceToken },
  ].filter((entry) => !config.overrides[entry.key]);

  const resolved = { ...config.overrides };
  if (wanted.length === 0) return resolved;

  const client = new SSMClient({});
  const response = await client.send(
    new GetParametersCommand({ Names: wanted.map((e) => e.name), WithDecryption: true })
  );

  // Parâmetro ausente volta em InvalidParameters com HTTP 200, não como erro.
  if (response.InvalidParameters?.length) {
    throw new Error(`Parametros ausentes no SSM: ${response.InvalidParameters.join(", ")}`);
  }

  for (const entry of wanted) {
    resolved[entry.key] = response.Parameters.find((p) => p.Name === entry.name)?.Value;
  }
  return resolved;
}

export function loadSecrets() {
  cached ??= fetchSecrets().catch((error) => {
    cached = undefined;
    throw error;
  });
  return cached;
}
