// Espelho de CustomerDomainValidator.isValidCpf, inclusive sem normalizar pontuação: divergir quebra o login.

const ELEVEN_DIGITS = /^\d{11}$/;
const ALL_SAME_DIGIT = /^(\d)\1{10}$/;

function checkDigit(digits, length) {
  let sum = 0;
  for (let i = 0; i < length; i++) {
    sum += digits[i] * (length + 1 - i);
  }
  const check = 11 - (sum % 11);
  return check >= 10 ? 0 : check;
}

export function isValidCpf(cpf) {
  if (typeof cpf !== "string" || !ELEVEN_DIGITS.test(cpf)) return false;
  if (ALL_SAME_DIGIT.test(cpf)) return false;

  const digits = Array.from(cpf, Number);
  return digits[9] === checkDigit(digits, 9) && digits[10] === checkDigit(digits, 10);
}

export function maskCpf(cpf) {
  return typeof cpf === "string" && cpf.length === 11 ? `*********${cpf.slice(-2)}` : "***";
}
