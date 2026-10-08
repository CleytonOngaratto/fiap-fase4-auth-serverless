import jwt from "jsonwebtoken";

const CUSTOMER_GROUPS = ["CUSTOMER"];

const normalizePem = (pem) => pem.replace(/\r/g, "");

export function signCustomerToken({ cpf, privateKey, issuer, ttlSeconds, issuedAt }) {
  const iat = issuedAt ?? Math.floor(Date.now() / 1000);

  return jwt.sign(
    {
      sub: cpf,
      iss: issuer,
      groups: CUSTOMER_GROUPS,
      cpf,
      iat,
      exp: iat + ttlSeconds,
    },
    normalizePem(privateKey),
    { algorithm: "RS256" }
  );
}
