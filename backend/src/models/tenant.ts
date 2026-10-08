import { Schema } from 'mongoose';

const GUARDED_OPS = [
  'find',
  'findOne',
  'countDocuments',
  'updateOne',
  'updateMany',
  'deleteOne',
  'deleteMany',
  'findOneAndUpdate',
  'findOneAndDelete',
  'replaceOne',
] as const;

/**
 * Tenant isolation guard: every query on a tenant collection must filter by
 * companyId unless explicitly opted out with `.setOptions({ skipTenant: true })`
 * (only used by system jobs that iterate across companies).
 */
export const tenantFields = {
  companyId: { type: Schema.Types.ObjectId, ref: 'Company', required: true, index: true },
  deletedAt: { type: Date, default: null },
} as const;

export function tenantPlugin(schema: Schema): void {
  for (const op of GUARDED_OPS) {
    schema.pre(op, function (this: any) {
      if (this.getOptions?.().skipTenant) return;
      const filter = this.getFilter?.() ?? {};
      // populate() fetches `{ _id: { $in: [...] } }` using ids read from already tenant-scoped documents.
      const keys = Object.keys(filter);
      if (op === 'find' && keys.length === 1 && keys[0] === '_id' && filter._id && typeof filter._id === 'object' && '$in' in filter._id) return;
      if (filter.companyId === undefined || filter.companyId === null) {
        throw new Error(`Tenant guard: ${op} on ${this.model?.modelName} without companyId`);
      }
    });
  }
}
