export class OsServiceUnavailable extends Error {}

// Nenhum acesso ao banco do OS: o cliente é confirmado pelo endpoint interno dele, que fica fora da
// allowlist do API Gateway e exige a credencial de serviço.
export async function findCustomerByDocument({ baseUrl, document, serviceToken, timeoutMs }) {
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
    throw new OsServiceUnavailable(`OS Service unreachable: ${error.message}`);
  } finally {
    clearTimeout(timer);
  }

  if (response.status === 404) return null;
  if (!response.ok) {
    throw new OsServiceUnavailable(`OS Service answered ${response.status}`);
  }
  return response.json();
}
