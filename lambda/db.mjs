import pg from "pg";

// O RDS exige TLS (rds.force_ssl = 1); rejectUnauthorized: false equivale ao sslmode=require da app.
function sslOption(mode) {
  return mode === "disable" ? false : { rejectUnauthorized: false };
}

let pool;

export function getPool({ host, port, database, user, password, ssl }) {
  pool ??= new pg.Pool({
    host,
    port,
    database,
    user,
    password,
    ssl: sslOption(ssl),
    max: 1,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 30000,
  });
  return pool;
}

export async function findCustomerByDocument(client, document) {
  const { rows } = await client.query(
    "SELECT id, name FROM customers WHERE document = $1 LIMIT 1",
    [document]
  );
  return rows[0] ?? null;
}
