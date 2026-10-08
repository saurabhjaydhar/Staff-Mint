import { Types } from 'mongoose';
import { Config, FeatureFlag } from '../../models/index.js';
import { DEFAULT_CONFIG } from './defaults.js';

/** Company override → global DB value → code default. */
export async function getConfig<T = unknown>(key: string, companyId?: Types.ObjectId | string | null): Promise<T> {
  if (companyId) {
    const c = await Config.findOne({ key, companyId }).lean();
    if (c) return c.value as T;
  }
  const g = await Config.findOne({ key, companyId: null }).lean();
  if (g) return g.value as T;
  return DEFAULT_CONFIG[key] as T;
}

export async function setConfig(key: string, value: unknown, companyId: Types.ObjectId | string | null = null) {
  return Config.findOneAndUpdate({ key, companyId }, { value }, { upsert: true, new: true }).lean();
}

export async function isFlagEnabled(key: string, companyId?: string | Types.ObjectId, planCode?: string): Promise<boolean> {
  const f = await FeatureFlag.findOne({ key }).lean();
  if (!f) return false;
  if (companyId && f.companyIds.some((id) => String(id) === String(companyId))) return true;
  if (planCode && f.plans.includes(planCode)) return true;
  return f.enabled;
}

export async function enabledFlags(companyId?: string | Types.ObjectId, planCode?: string): Promise<string[]> {
  const flags = await FeatureFlag.find().lean();
  return flags
    .filter((f) => f.enabled || (planCode && f.plans.includes(planCode)) || (companyId && f.companyIds.some((id) => String(id) === String(companyId))))
    .map((f) => f.key);
}
