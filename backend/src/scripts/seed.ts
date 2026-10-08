/**
 * Seed default plans/config. With --demo, also create a demo company:
 *   owner +919999900001 (OTP 123456 with OTP_PROVIDER=mock), 6 staff, 2 weeks of attendance.
 */
import { DateTime } from 'luxon';
import { connectDb, disconnectDb } from '../db.js';
import { seedDefaults } from './seedDefaults.js';
import { User, Company, Attendance, Employee } from '../models/index.js';
import { setupCompany } from '../modules/company/service.js';
import { createEmployee } from '../modules/employees/service.js';
import { createAdvance } from '../modules/advances/service.js';
import type { Ctx } from '../lib/context.js';
import { logger } from '../lib/logger.js';

async function demo() {
  const phone = '+919999900001';
  let owner = await User.findOne({ phone });
  if (owner?.companyId) {
    logger.info('Demo company already exists');
    return;
  }
  owner ??= await User.create({ phone, role: 'owner', name: 'Demo Owner', language: 'hi' });
  const { company } = await setupCompany(owner._id, {
    name: 'Sharma Medical Store',
    businessType: 'pharmacy',
    location: { lat: 28.6139, lng: 77.209, address: 'Connaught Place, New Delhi' },
    openingTime: '09:00',
    closingTime: '21:00',
    weeklyOff: [0],
    ownerName: 'Rakesh Sharma',
  });
  const c = await Company.findById(company.id);
  const ctx: Ctx = { userId: owner._id, companyId: c!._id, role: 'owner', employeeId: null, branchIds: [], actorName: 'Rakesh Sharma', channel: 'app', language: 'hi' };
  const staff = [
    ['Ramesh Kumar', '9876500001', 1500000, 'Pharmacist'],
    ['Suresh Yadav', '9876500002', 1200000, 'Helper'],
    ['Pooja Singh', '9876500003', 1400000, 'Cashier'],
    ['Amit Verma', '9876500004', 1100000, 'Delivery'],
    ['Raju', '9876500005', 60000, 'Cleaner'],
    ['Ramesh Gupta', '9876500006', 1300000, 'Pharmacist'],
  ] as const;
  const start = DateTime.now().setZone(c!.timezone).minus({ days: 14 });
  const emps = [];
  for (const [name, ph, rate, desig] of staff) {
    emps.push(await createEmployee(ctx, { name, phone: ph, ratePaise: rate, wageType: rate < 100000 ? 'daily' : 'monthly', designation: desig, joiningDate: start.minus({ months: 6 }).toISODate()! }));
  }
  await createAdvance(ctx, { employeeId: String(emps[3]._id), amountPaise: 500000, date: start.toISODate()!, mode: 'installments', installments: 2 });
  const statuses = ['present', 'present', 'present', 'present', 'half_day', 'present', 'absent'];
  for (let i = 0; i < 14; i++) {
    const d = start.plus({ days: i });
    if (d.weekday === 7) continue;
    for (const [j, e] of emps.entries()) {
      const status = statuses[(i + j) % statuses.length];
      await Attendance.updateOne(
        { companyId: c!._id, employeeId: e._id, date: d.toISODate()! },
        { $setOnInsert: { companyId: c!._id, employeeId: e._id, date: d.toISODate()!, status, lateMinutes: (i + j) % 5 === 0 ? 22 : 0, punches: [] } },
        { upsert: true },
      );
    }
  }
  await Employee.updateMany({ companyId: c!._id }, { 'consent.location': true, 'consent.at': new Date() });
  logger.info(`Demo company created. Owner login: ${phone} / OTP 123456 (mock). Staff e.g. 9876500001.`);
}

async function main() {
  await connectDb();
  await seedDefaults();
  if (process.argv.includes('--demo')) await demo();
  await disconnectDb();
}

main().catch(async (err) => {
  logger.error({ err }, 'seed failed');
  await disconnectDb();
  process.exit(1);
});
