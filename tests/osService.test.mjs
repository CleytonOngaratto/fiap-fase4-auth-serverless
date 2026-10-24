import test from "node:test";
import assert from "node:assert/strict";

import { findCustomerByDocument, OsServiceUnavailable } from "../lambda/osService.mjs";

const BASE = "http://alb.internal/carworkshop/v1/internal/customers";

const call = (document = "52998224725") =>
  findCustomerByDocument({ baseUrl: BASE, document, serviceToken: "token", timeoutMs: 100 });

const stubFetch = (implementation) => {
  const original = globalThis.fetch;
  globalThis.fetch = implementation;
  return () => {
    globalThis.fetch = original;
  };
};

test("cliente encontrado -> devolve o corpo do OS Service", async () => {
  const restore = stubFetch(async () => new Response(JSON.stringify({ id: 1, name: "John Silva" }), {
    status: 200,
    headers: { "content-type": "application/json" },
  }));
  try {
    assert.deepEqual(await call(), { id: 1, name: "John Silva" });
  } finally {
    restore();
  }
});

test("manda a credencial de serviço no header e o cpf no caminho", async () => {
  let seen;
  const restore = stubFetch(async (url, init) => {
    seen = { url, init };
    return new Response(JSON.stringify({ id: 1, name: "John Silva" }), { status: 200 });
  });
  try {
    await call("52998224725");
    assert.equal(seen.url, `${BASE}/52998224725`);
    assert.equal(seen.init.headers["X-Service-Token"], "token");
    assert.equal(seen.init.method, "GET");
  } finally {
    restore();
  }
});

test("404 do OS Service -> null, que o handler traduz em customer_not_found", async () => {
  const restore = stubFetch(async () => new Response("", { status: 404 }));
  try {
    assert.equal(await call(), null);
  } finally {
    restore();
  }
});

test("401 significa credencial de serviço errada, não cliente ausente", async () => {
  const restore = stubFetch(async () => new Response("", { status: 401 }));
  try {
    await assert.rejects(call(), OsServiceUnavailable);
  } finally {
    restore();
  }
});

test("5xx do OS Service -> indisponível", async () => {
  const restore = stubFetch(async () => new Response("", { status: 500 }));
  try {
    await assert.rejects(call(), OsServiceUnavailable);
  } finally {
    restore();
  }
});

test("rede fora do ar -> indisponível, com a causa na mensagem", async () => {
  const restore = stubFetch(async () => {
    throw new Error("connect ECONNREFUSED");
  });
  try {
    await assert.rejects(call(), (error) => {
      assert.ok(error instanceof OsServiceUnavailable);
      assert.match(error.message, /ECONNREFUSED/);
      return true;
    });
  } finally {
    restore();
  }
});

test("o cpf vai codificado no caminho", async () => {
  let seen;
  const restore = stubFetch(async (url) => {
    seen = url;
    return new Response("", { status: 404 });
  });
  try {
    await call("../internal");
    assert.ok(!seen.includes("../"), seen);
  } finally {
    restore();
  }
});
