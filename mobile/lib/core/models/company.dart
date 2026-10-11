import '../utils/json.dart';

class GeoPoint {
  const GeoPoint({required this.lat, required this.lng, this.address});
  final double lat;
  final double lng;
  final String? address;

  factory GeoPoint.fromJson(Json j) =>
      GeoPoint(lat: asDouble(j['lat']), lng: asDouble(j['lng']), address: asStringOrNull(j['address']));

  Json toJson() => {'lat': lat, 'lng': lng, if (address != null && address!.isNotEmpty) 'address': address};
}

class Plan {
  const Plan({
    required this.code,
    required this.name,
    required this.priceMonthlyPaise,
    required this.priceYearlyPaise,
    required this.currency,
    required this.staffLimit,
    required this.extraStaffPricePaise,
    required this.trialDays,
    required this.features,
  });

  final String code;
  final String name;
  final int priceMonthlyPaise;
  final int priceYearlyPaise;
  final String currency;
  final int staffLimit;
  final int extraStaffPricePaise;
  final int trialDays;
  final List<String> features;

  bool has(String feature) => features.contains(feature);

  factory Plan.fromJson(Json j) => Plan(
    code: asString(j['code']),
    name: asString(j['name']),
    priceMonthlyPaise: asInt(j['priceMonthlyPaise']),
    priceYearlyPaise: asInt(j['priceYearlyPaise']),
    currency: asString(j['currency'], 'INR'),
    staffLimit: asInt(j['staffLimit']),
    extraStaffPricePaise: asInt(j['extraStaffPricePaise']),
    trialDays: asInt(j['trialDays']),
    features: asStringList(j['features']),
  );
}

class Subscription {
  const Subscription({required this.status, this.planCode, this.currentPeriodEnd});
  final String status;
  final String? planCode;
  final DateTime? currentPeriodEnd;

  factory Subscription.fromJson(Json j) => Subscription(
    status: asString(j['status'], 'free'),
    planCode: asStringOrNull(j['planCode']),
    currentPeriodEnd: asDateTimeOrNull(j['currentPeriodEnd']),
  );
}

/// Free trial of a business: a countdown while it runs, then "trial ended" for 30 days.
class Trial {
  const Trial({required this.planCode, required this.planName, required this.endsAt, this.paidFeatures = const []});
  final String planCode;
  final String planName;
  final DateTime endsAt;

  /// Paid features that stop when the trial ends (keys like `payroll`).
  final List<String> paidFeatures;

  bool activeAt(DateTime now) => endsAt.isAfter(now);
  bool get active => activeAt(DateTime.now());

  /// Whole days left, counting today's part as one; 0 once ended. Counted on the phone so it stays right.
  int daysLeftAt(DateTime now) {
    final ms = endsAt.difference(now).inMilliseconds;
    return ms <= 0 ? 0 : (ms / Duration.millisecondsPerDay).ceil();
  }

  int get daysLeft => daysLeftAt(DateTime.now());

  factory Trial.fromJson(Json j) => Trial(
    planCode: asString(j['planCode']),
    planName: asString(j['planName']),
    endsAt: asDateTimeOrNull(j['endsAt']) ?? DateTime.now(),
    paidFeatures: (j['paidFeatures'] is List ? j['paidFeatures'] as List : const []).map((e) => '$e').toList(),
  );
}

class CompanySettings {
  const CompanySettings({
    this.graceMinutes = 15,
    this.halfDayHours = 4,
    this.monthDivisor = 'days_in_month',
    this.missingCheckoutPolicy = 'half_day',
    this.weekOffsPaid = true,
    this.holidaysPaid = true,
    this.sickLeavePaid = true,
    this.outsideGeofencePolicy = 'block',
    this.phoneLockPolicy = 'recommended',
    this.faceMatchPolicy = 'off',
    this.language = 'en',
    this.digestTime = '09:30',
    this.roundToRupee = true,
    this.selfieRequired = true,
    this.maxDeviceTimeDriftMin = 10,
    this.selfieRetentionDays = 90,
    this.whatsappAlerts = false,
    this.exStaffPayslips = true,
  });

  final int graceMinutes;
  final num halfDayHours;
  final String monthDivisor;
  final String missingCheckoutPolicy;
  final bool weekOffsPaid;
  final bool holidaysPaid;
  final bool sickLeavePaid;
  final String outsideGeofencePolicy;

  /// off | recommended | required — ask the phone's own screen lock at check-in.
  final String phoneLockPolicy;

  /// off | review — compare check-in selfies with approved face photos.
  final String faceMatchPolicy;
  final String language;
  final String digestTime;
  final bool roundToRupee;
  final bool selfieRequired;
  final int maxDeviceTimeDriftMin;
  final int selfieRetentionDays;
  final bool whatsappAlerts;

  /// Ex-staff can see their own payslips for 12 months.
  final bool exStaffPayslips;

  factory CompanySettings.fromJson(Json j) => CompanySettings(
    graceMinutes: asInt(j['graceMinutes'], 15),
    halfDayHours: asNum(j['halfDayHours'], 4),
    monthDivisor: asString(j['monthDivisor'], 'days_in_month'),
    missingCheckoutPolicy: asString(j['missingCheckoutPolicy'], 'half_day'),
    weekOffsPaid: asBool(j['weekOffsPaid'], true),
    holidaysPaid: asBool(j['holidaysPaid'], true),
    sickLeavePaid: asBool(j['sickLeavePaid'], true),
    outsideGeofencePolicy: asString(j['outsideGeofencePolicy'], 'block'),
    phoneLockPolicy: asString(j['phoneLockPolicy'], 'recommended'),
    faceMatchPolicy: asString(j['faceMatchPolicy'], 'off'),
    language: asString(j['language'], 'en'),
    digestTime: asString(j['digestTime'], '09:30'),
    roundToRupee: asBool(j['roundToRupee'], true),
    selfieRequired: asBool(j['selfieRequired'], true),
    maxDeviceTimeDriftMin: asInt(j['maxDeviceTimeDriftMin'], 10),
    selfieRetentionDays: asInt(j['selfieRetentionDays'], 90),
    whatsappAlerts: asBool(j['whatsappAlerts']),
    exStaffPayslips: j['exStaffPayslips'] == null ? true : asBool(j['exStaffPayslips']),
  );

  Json toJson() => {
    'graceMinutes': graceMinutes,
    'halfDayHours': halfDayHours,
    'monthDivisor': monthDivisor,
    'missingCheckoutPolicy': missingCheckoutPolicy,
    'weekOffsPaid': weekOffsPaid,
    'holidaysPaid': holidaysPaid,
    'sickLeavePaid': sickLeavePaid,
    'outsideGeofencePolicy': outsideGeofencePolicy,
    'phoneLockPolicy': phoneLockPolicy,
    'faceMatchPolicy': faceMatchPolicy,
    'language': language,
    'digestTime': digestTime,
    'roundToRupee': roundToRupee,
    'selfieRequired': selfieRequired,
    'maxDeviceTimeDriftMin': maxDeviceTimeDriftMin,
    'selfieRetentionDays': selfieRetentionDays,
    'whatsappAlerts': whatsappAlerts,
    'exStaffPayslips': exStaffPayslips,
  };
}

class Company {
  const Company({
    required this.id,
    required this.name,
    required this.businessType,
    this.country = 'IN',
    this.currency = 'INR',
    this.timezone = 'Asia/Kolkata',
    this.location,
    this.settings = const CompanySettings(),
    this.plan,
    this.subscription,
    this.trial,
  });

  final String id;
  final String name;
  final String businessType;
  final String country;
  final String currency;
  final String timezone;
  final GeoPoint? location;
  final CompanySettings settings;
  final Plan? plan;
  final Subscription? subscription;
  final Trial? trial;

  bool hasFeature(String f) => plan?.has(f) ?? true;

  factory Company.fromJson(Json j) => Company(
    id: asString(j['id']),
    name: asString(j['name']),
    businessType: asString(j['businessType'], 'other'),
    country: asString(j['country'], 'IN'),
    currency: asString(j['currency'], 'INR'),
    timezone: asString(j['timezone'], 'Asia/Kolkata'),
    location: j['location'] is Map ? GeoPoint.fromJson(asMap(j['location'])) : null,
    settings: CompanySettings.fromJson(asMap(j['settings'])),
    plan: j['plan'] is Map ? Plan.fromJson(asMap(j['plan'])) : null,
    subscription: j['subscription'] is Map ? Subscription.fromJson(asMap(j['subscription'])) : null,
    trial: j['trial'] is Map ? Trial.fromJson(asMap(j['trial'])) : null,
  );
}

class Branch {
  const Branch({required this.id, required this.name, this.location, this.radiusM = 100, this.shiftId});
  final String id;
  final String name;
  final GeoPoint? location;
  final int radiusM;
  final String? shiftId;

  factory Branch.fromJson(Json j) => Branch(
    id: asString(j['id']),
    name: asString(j['name']),
    location: j['location'] is Map ? GeoPoint.fromJson(asMap(j['location'])) : null,
    radiusM: asInt(j['radiusM'], 100),
    shiftId: asStringOrNull(j['shiftId']),
  );
}

class Shift {
  const Shift({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    this.graceMinutes,
    this.weeklyOff = const [0],
  });
  final String id;
  final String name;
  final String start;
  final String end;
  final int? graceMinutes;
  final List<int> weeklyOff;

  factory Shift.fromJson(Json j) => Shift(
    id: asString(j['id']),
    name: asString(j['name']),
    start: asString(j['start'], '09:00'),
    end: asString(j['end'], '19:00'),
    graceMinutes: asIntOrNull(j['graceMinutes']),
    weeklyOff: asIntList(j['weeklyOff']),
  );
}

class Holiday {
  const Holiday({required this.id, required this.date, required this.name});
  final String id;
  final String date;
  final String name;

  factory Holiday.fromJson(Json j) =>
      Holiday(id: asString(j['id']), date: asString(j['date']), name: asString(j['name']));
}

class RuleText {
  const RuleText({required this.key, required this.text});
  final String key;
  final String text;
  factory RuleText.fromJson(Json j) => RuleText(key: asString(j['key']), text: asString(j['text']));
}
