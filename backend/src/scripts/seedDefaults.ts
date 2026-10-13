import { Plan, Config } from '../models/index.js';
import { ADDED_FEATURES, DEFAULT_PLANS, DEFAULT_CONFIG } from '../modules/config/defaults.js';

/** Insert default plans/config if missing. Never overwrites values edited in the DB. */
export async function seedDefaults() {
  for (const p of DEFAULT_PLANS) await Plan.updateOne({ code: p.code }, { $setOnInsert: { ...p, country: 'IN', currency: 'INR', active: true } }, { upsert: true });
  for (const [key, value] of Object.entries(DEFAULT_CONFIG)) await Config.updateOne({ key, companyId: null }, { $setOnInsert: { key, companyId: null, value } }, { upsert: true });
  // New features reach plans already saved in the DB, once.
  const done = ((await Config.findOne({ key: 'features.added', companyId: null }).lean())?.value as string[] | undefined) ?? [];
  const todo = Object.keys(ADDED_FEATURES).filter((f) => !done.includes(f));
  for (const f of todo) await Plan.updateMany({ code: { $in: ADDED_FEATURES[f] } }, { $addToSet: { features: f } });
  if (todo.length) await Config.updateOne({ key: 'features.added', companyId: null }, { $set: { value: [...done, ...todo] } }, { upsert: true });
}
