/**
 * Create (or reset the password of) an admin for the admin app.
 *   npm run admin:create -- --email you@example.com --name "Your Name" --password 'long-pass-123'
 *   (production image) node dist/scripts/createAdmin.js --email ... --password ...
 * Add --role viewer for read-only support staff (default: admin).
 */
import { parseArgs } from 'node:util';
import { connectDb, disconnectDb } from '../db.js';
import { AdminUser } from '../models/index.js';
import { assertStrongPassword, hashPassword } from '../modules/admin/auth.js';

async function main() {
  const { values } = parseArgs({ options: { email: { type: 'string' }, name: { type: 'string' }, password: { type: 'string' }, role: { type: 'string', default: 'admin' } } });
  if (!values.email || !values.password) throw new Error('Usage: --email you@example.com --password <at least 10 chars> [--name "Name"] [--role admin|viewer]');
  if (values.role !== 'admin' && values.role !== 'viewer') throw new Error('--role must be admin or viewer');
  assertStrongPassword(values.password);
  await connectDb();
  const email = values.email.trim().toLowerCase();
  const passwordHash = await hashPassword(values.password);
  const existing = await AdminUser.findOne({ email });
  if (existing) {
    existing.passwordHash = passwordHash;
    existing.role = values.role;
    existing.active = true;
    existing.tokenVersion += 1;
    if (values.name) existing.name = values.name;
    await existing.save();
    console.log(`Updated admin ${email} (${values.role}); old sessions signed out.`);
  } else {
    await AdminUser.create({ email, name: values.name ?? '', role: values.role, passwordHash });
    console.log(`Created admin ${email} (${values.role}).`);
  }
  await disconnectDb();
}

main().catch(async (err) => {
  console.error(err.message ?? err);
  await disconnectDb().catch(() => undefined);
  process.exit(1);
});
