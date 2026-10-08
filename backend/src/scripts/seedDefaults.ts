import { Plan, Config } from '../models/index.js';
import { DEFAULT_PLANS, DEFAULT_CONFIG } from '../modules/config/defaults.js';

/** Insert default plans/config if missing. Never overwrites values edited in the DB. */
export async function seedDefaults() {
  for (const p of DEFAULT_PLANS) await Plan.updateOne({ code: p.code }, { $setOnInsert: { ...p, country: 'IN', currency: 'INR', active: true } }, { upsert: true });
  for (const [key, value] of Object.entries(DEFAULT_CONFIG)) await Config.updateOne({ key, companyId: null }, { $setOnInsert: { key, companyId: null, value } }, { upsert: true });
}
