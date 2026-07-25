// Postgres adapter — one place to swap in your existing client/ORM.
//
// Default implementation uses `pg` with DATABASE_URL (works with Neon,
// Supabase, Vercel Postgres, RDS…). If sticks-golf already has a Prisma or
// Drizzle client, replace `query` with a call into it and keep the same
// signature — everything else in backend/push only imports `query`.

import pg from "pg";

let pool = null;

function getPool() {
  if (!pool) {
    pool = new pg.Pool({
      connectionString: process.env.DATABASE_URL,
      max: 3, // serverless-friendly
    });
  }
  return pool;
}

/**
 * Runs a parameterized SQL query.
 * @param {string} text  SQL with $1, $2… placeholders
 * @param {unknown[]} [params]
 * @returns {Promise<{ rows: any[], rowCount: number }>}
 */
export async function query(text, params = []) {
  const result = await getPool().query(text, params);
  return { rows: result.rows, rowCount: result.rowCount ?? 0 };
}
