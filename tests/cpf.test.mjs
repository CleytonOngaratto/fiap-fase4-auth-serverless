import test from "node:test";
import assert from "node:assert/strict";

import { isValidCpf, maskCpf } from "../lambda/cpf.mjs";

test("CPFs do seed: só o da Maria Santos tem dígitos válidos", () => {
  assert.equal(isValidCpf("98765432100"), true, "Maria Santos — caminho feliz");
  assert.equal(isValidCpf("12345678901"), false, "John Silva — semeado inválido");
  assert.equal(isValidCpf("11122233344"), false, "Carlos Oliveira — semeado inválido");
});

test("CPF válido que não existe no banco serve ao caso 404", () => {
  assert.equal(isValidCpf("11144477735"), true);
});

test("rejeita formato antes dos dígitos, como o validador da app", () => {
  assert.equal(isValidCpf("529.982.247-25"), false, "pontuação não é normalizada");
  assert.equal(isValidCpf("9876543210"), false, "10 dígitos");
  assert.equal(isValidCpf("987654321000"), false, "12 dígitos");
  assert.equal(isValidCpf(""), false);
  assert.equal(isValidCpf(null), false);
  assert.equal(isValidCpf(98765432100), false, "número não é string");
});

test("rejeita dígitos repetidos, que passam na aritmética mas não são CPF", () => {
  for (const digit of "0123456789") {
    assert.equal(isValidCpf(digit.repeat(11)), false, `${digit.repeat(11)}`);
  }
});

test("cobre o ramo `check >= 10 -> 0`, que o caminho feliz por acaso exercita", () => {
  assert.equal(isValidCpf("98765432100"), true);
  assert.equal(isValidCpf("11144477735"), true);
});

test("maskCpf nunca devolve o documento cheio", () => {
  assert.equal(maskCpf("98765432100"), "*********00");
  assert.equal(maskCpf("123"), "***");
  assert.equal(maskCpf(null), "***");
});
