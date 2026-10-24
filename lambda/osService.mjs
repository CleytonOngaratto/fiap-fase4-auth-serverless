export class OsServiceUnavailable extends Error {
  constructor(message, { retryable = false } = {}) {
    super(message);
    this.retryable = retryable;
  }
}

const ATTEMPTS = 2;

// Nenhum acesso ao banco do OS: o cliente é confirmado pelo endpoint interno dele, que fica fora da
// allowlist do API Gateway e exige a credencial de serviço.
export async function findCustomerByDocument({ baseUrl, document, serviceToken, timeoutMs }) {
  let lastError;

  // Medido: a primeira conexão ao ALB depois de os pods do OS serem reagendados estourou o orcamento de
  // 3 s, e a chamada seguinte levou 17 ms. O GET e idempotente, entao uma segunda tentativa troca um 503
  // visivel no login por mais 3 s no pior caso. Credencial errada nao e retentada.
  for (let attempt = 1; attempt <= ATTEMPTS; attempt += 1) {
    try {
      return await requestCustomer({ baseUrl, document, serviceToken, timeoutMs });
    } catch (error) {
      if (!(error instanceof OsServiceUnavailable) || !error.retryable) {
        throw error;
      }
      lastError = error;
    }
  }

  throw lastError;
}

async function requestCustomer({ baseUrl, document, serviceToken, timeoutMs }) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let response;
  try {
    response = await fetch(`${baseUrl}/${encodeURIComponent(document)}`, {
      method: "GET",
      headers: { "X-Service-Token": serviceToken, accept: "application/json" },
      signal: controller.signal,
    });
  } catch (error) {
    throw new OsServiceUnavailable(`OS Service unreachable: ${error.message}`, { retryable: true });
  } finally {
    clearTimeout(timer);
  }

  if (response.status === 404) return null;
  if (!response.ok) {
    throw new OsServiceUnavailable(`OS Service answered ${response.status}`, {
      retryable: response.status >= 500,
    });
  }
  return response.json();
}
