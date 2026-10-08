import test from "node:test";
import assert from "node:assert/strict";

import { handler } from "../lambda/index.mjs";

const post = (body, extra = {}) =>
  handler({ requestContext: { http: { method: "POST", path: "/auth" } }, body, ...extra });

const parse = (response) => JSON.parse(response.body);

test("body ausente -> 400 invalid_request", async () => {
  const response = await post(undefined);
  assert.equal(response.statusCode, 400);
  assert.equal(parse(response).error, "invalid_request");
});

test("body que não é JSON -> 400, sem estourar exceção", async () => {
  const response = await post("cpf=98765432100");
  assert.equal(response.statusCode, 400);
  assert.equal(parse(response).error, "invalid_request");
});

test("JSON sem o campo cpf -> 400", async () => {
  assert.equal((await post(JSON.stringify({ documento: "98765432100" }))).statusCode, 400);
  assert.equal((await post(JSON.stringify({ cpf: 98765432100 }))).statusCode, 400, "número, não string");
});

test("cpf vazio ou só espaços -> invalid_request, não invalid_cpf", async () => {
  for (const cpf of ["", "   ", "\t\n"]) {
    const response = await post(JSON.stringify({ cpf }));
    assert.equal(response.statusCode, 400, JSON.stringify(cpf));
    assert.equal(parse(response).error, "invalid_request", JSON.stringify(cpf));
  }
});

test("CPF do seed com dígitos inválidos -> 400 invalid_cpf", async () => {
  const response = await post(JSON.stringify({ cpf: "12345678901" }));
  assert.equal(response.statusCode, 400);
  assert.equal(parse(response).error, "invalid_cpf");
});

test("aceita o body em base64, como o API Gateway pode entregar", async () => {
  const response = await post(Buffer.from(JSON.stringify({ cpf: "12345" })).toString("base64"), {
    isBase64Encoded: true,
  });
  assert.equal(parse(response).error, "invalid_cpf");
});

test("a resposta é sempre JSON com content-type", async () => {
  const response = await post(undefined);
  assert.equal(response.headers["content-type"], "application/json");
  assert.doesNotThrow(() => JSON.parse(response.body));
});

test("a rejeição por CPF inválido não vaza o documento na mensagem", async () => {
  const response = await post(JSON.stringify({ cpf: "12345678901" }));
  assert.ok(!response.body.includes("12345678901"));
});
