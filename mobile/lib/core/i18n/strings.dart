import 'package:flutter/widgets.dart';

import '../utils/money.dart';

/// A label with an optional small English hint: Hindi-first screens show
/// "हाज़िर" with "Present" underneath; English screens show just "Present".
class Bi {
  const Bi(this.text, [this.hint]);
  final String text;
  final String? hint;

  /// One-line form: `हाज़िर · Present` (or just `Present`).
  String get joined => hint == null ? text : '$text · $hint';
}

/// Every user-visible string in the app, in English and Hindi.
///
/// A typed class (instead of ARB + codegen) keeps both languages side by side
/// so a missing translation is obvious in review. Use `context.s.xyz`.
class S {
  const S(this.languageCode);

  final String languageCode;

  static const supportedLanguages = ['en', 'hi'];
  static const en = S('en');
  static const hi = S('hi');

  bool get isHindi => languageCode == 'hi';

  static S of(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    return code == 'hi' ? hi : en;
  }

  static S forCode(String code) => code == 'hi' ? hi : en;

  String _t(String en, String hi) => isHindi ? hi : en;

  /// Hindi with an English hint when the app is in Hindi, plain English otherwise.
  /// Hindi mode shows Hindi only (no English hint under it).
  Bi _b(String en, String hi) => isHindi ? Bi(hi) : Bi(en);

  /// 2 → "2", 1.5 → "1.5".
  String _num(num n) => n == n.roundToDouble() ? '${n.round()}' : '$n';

  // ---------------------------------------------------------------- General
  String get appName => 'StaffMint';
  String get tagline => _t('Staff & salary, sorted from your phone.', 'स्टाफ़ और सैलरी, सब आपके फ़ोन से।');
  String get taglineHinglish =>
      _t('Speak or tap — attendance and salary done.', 'बोलो या टैप करो — हाज़िरी और सैलरी हो जाएगी।');
  String get ok => _t('OK', 'ठीक है');
  String get cancel => _t('Cancel', 'रद्द करें');
  String get save => _t('Save', 'सेव करें');
  String get next => _t('Next', 'आगे');
  String get back => _t('Back', 'पीछे');
  String get skip => _t('Skip', 'छोड़ें');
  String get done => _t('Done', 'हो गया');
  String get retry => _t('Try again', 'फिर से कोशिश करें');
  String get confirm => _t('Confirm', 'पक्का करें');
  String get close => _t('Close', 'बंद करें');
  String get delete => _t('Delete', 'हटाएँ');
  String get edit => _t('Edit', 'बदलें');
  String get add => _t('Add', 'जोड़ें');
  String get search => _t('Search', 'खोजें');
  String get loading => _t('Loading…', 'लोड हो रहा है…');
  String get yes => _t('Yes', 'हाँ');
  String get no => _t('No', 'नहीं');
  String get optional => _t('optional', 'ज़रूरी नहीं');
  String get required => _t('Required', 'ज़रूरी है');
  String get saved => _t('Saved', 'सेव हो गया');
  String get nothingHere => _t('Nothing here yet', 'अभी यहाँ कुछ नहीं है');
  String get today => _t('Today', 'आज');
  String get yesterday => _t('Yesterday', 'कल');
  String get date => _t('Date', 'तारीख़');
  String get month => _t('Month', 'महीना');
  String get from => _t('From', 'से');
  String get to => _t('To', 'तक');
  String get note => _t('Note', 'नोट');
  String get reason => _t('Reason', 'कारण');
  String get amount => _t('Amount (₹)', 'रकम (₹)');
  String get name => _t('Name', 'नाम');
  String get phone => _t('Phone number', 'फ़ोन नंबर');
  String get status => _t('Status', 'स्थिति');
  String get open => _t('Open', 'खोलें');
  String get share => _t('Share', 'शेयर करें');
  String get selectEmployee => _t('Select staff member', 'स्टाफ़ चुनें');
  String get invalidAmount => _t('Enter a valid amount', 'सही रकम डालें');
  String get invalidPhone => _t('Enter a valid 10-digit mobile number', 'सही 10 अंकों का मोबाइल नंबर डालें');
  String get couldNotOpen => _t('Could not open the link', 'लिंक नहीं खुल सका');
  String get areYouSure => _t('Are you sure?', 'क्या आप पक्का हैं?');

  // ----------------------------------------------------------------- Errors
  String get networkError => _t('No internet. Please check your connection.', 'इंटरनेट नहीं है। कृपया कनेक्शन जाँचें।');
  String get genericError => _t('Something went wrong. Please try again.', 'कुछ गड़बड़ हो गई। फिर से कोशिश करें।');
  String get sessionExpired =>
      _t('Your session has ended. Please log in again.', 'आपका सेशन ख़त्म हो गया। फिर से लॉगिन करें।');
  String get planLimitError => _t(
    'Your plan limit is reached. Upgrade in More › Billing.',
    'आपके प्लान की सीमा पूरी हो गई। और › प्लान और पेमेंट में अपग्रेड करें।',
  );
  String get deviceNotBound => _t(
    'This phone is not registered for your account. Ask your owner to reset your device.',
    'यह फ़ोन आपके खाते से जुड़ा नहीं है। मालिक से डिवाइस रीसेट करवाएँ।',
  );
  String get forbiddenError => _t('You do not have permission for this.', 'आपको इसकी अनुमति नहीं है।');

  // ------------------------------------------------------------------ Auth
  String get loginTitle => _t('Welcome to StaffMint', 'StaffMint में आपका स्वागत है');
  String get loginSubtitle => _t('Enter your mobile number to continue', 'आगे बढ़ने के लिए अपना मोबाइल नंबर डालें');
  String get mobileNumber => _t('Mobile number', 'मोबाइल नंबर');
  String get getOtp => _t('Get OTP', 'OTP पाएँ');
  String get sendViaWhatsApp => _t('Send OTP on WhatsApp', 'OTP WhatsApp पर भेजें');
  String get otpTitle => _t('Enter OTP', 'OTP डालें');
  String otpSentTo(String phone) => _t('We sent a 6-digit code to $phone', 'हमने $phone पर 6 अंकों का कोड भेजा है');
  String devCodeHint(String code) => _t('Test mode — your code is $code', 'टेस्ट मोड — आपका कोड $code है');
  String get verify => _t('Verify & continue', 'जाँचें और आगे बढ़ें');
  String get resendOtp => _t('Resend OTP', 'OTP फिर से भेजें');
  String resendIn(int s) => _t('Resend in ${s}s', '$s सेकंड में फिर भेजें');
  String get changeNumber => _t('Change number', 'नंबर बदलें');
  String get otpInvalid => _t('Wrong OTP. Please try again.', 'गलत OTP। फिर से कोशिश करें।');
  String get termsNote => _t(
    'By continuing you agree to our Terms & Privacy Policy.',
    'आगे बढ़कर आप हमारी शर्तों और प्राइवेसी पॉलिसी से सहमत हैं।',
  );
  String get logout => _t('Log out', 'लॉग आउट');
  String get logoutConfirm => _t('Do you want to log out?', 'क्या आप लॉग आउट करना चाहते हैं?');

  // ----------------------------------------------------------------- Setup
  String setupStep(int i, int n) => _t('Step $i of $n', 'चरण $i / $n');
  String get setupBusinessTitle => _t('About your business', 'आपके बिज़नेस के बारे में');
  String get businessName => _t('Business name', 'बिज़नेस का नाम');
  String get businessNameHint => _t('e.g. Sharma Medical Store', 'जैसे शर्मा मेडिकल स्टोर');
  String get businessType => _t('Business type', 'बिज़नेस का प्रकार');
  String businessTypeLabel(String t) {
    switch (t) {
      case 'pharmacy':
        return _t('Pharmacy', 'मेडिकल / फ़ार्मेसी');
      case 'clinic':
        return _t('Clinic', 'क्लिनिक');
      case 'salon':
        return _t('Salon', 'सैलून');
      case 'restaurant':
        return _t('Restaurant', 'रेस्टोरेंट');
      case 'shop':
        return _t('Shop', 'दुकान');
      case 'office':
        return _t('Office', 'ऑफ़िस');
      default:
        return _t('Other', 'अन्य');
    }
  }

  String get setupLocationTitle => _t('Where is your shop?', 'आपकी दुकान कहाँ है?');
  String get setupLocationHint => _t(
    'Tap the map to place the pin. Staff can check in only near this point.',
    'नक्शे पर टैप करके पिन लगाएँ। स्टाफ़ इसी जगह के पास हाज़िरी लगा पाएगा।',
  );
  String get useMyLocation => _t('Use my current location', 'मेरी मौजूदा लोकेशन लें');
  String get addressOptional => _t('Address (optional)', 'पता (ज़रूरी नहीं)');
  String get locationPermissionDenied => _t(
    'Location permission is needed. Please allow it in Settings.',
    'लोकेशन की अनुमति चाहिए। कृपया सेटिंग्स में अनुमति दें।',
  );
  String get locationServiceOff => _t('Please turn on GPS / Location.', 'कृपया GPS / लोकेशन चालू करें।');
  String get pinRequired => _t('Please place the pin on your shop', 'कृपया अपनी दुकान पर पिन लगाएँ');
  String get setupTimingTitle => _t('Shop timings', 'दुकान का समय');
  String get openingTime => _t('Opening time', 'खुलने का समय');
  String get closingTime => _t('Closing time', 'बंद होने का समय');
  String get setupTimingHint => _t(
    'Staff arriving more than 15 minutes after opening are marked late. You can change this later.',
    'खुलने के 15 मिनट बाद आने वाला स्टाफ़ लेट माना जाएगा। इसे बाद में बदल सकते हैं।',
  );
  String get setupWeeklyOffTitle => _t('Weekly off', 'साप्ताहिक छुट्टी');
  String get setupWeeklyOffHint => _t('Which day is your shop closed?', 'आपकी दुकान किस दिन बंद रहती है?');
  String get noWeeklyOff => _t('No weekly off', 'कोई साप्ताहिक छुट्टी नहीं');
  String get createBusiness => _t('Create my business', 'मेरा बिज़नेस बनाएँ');
  String get setupStaffTitle => _t('Add your staff', 'अपना स्टाफ़ जोड़ें');
  String get setupStaffHint => _t(
    'Add staff now or later. They log in with their own phone number.',
    'स्टाफ़ अभी या बाद में जोड़ें। वे अपने फ़ोन नंबर से लॉगिन करेंगे।',
  );
  String get addManually => _t('Add manually', 'ख़ुद से जोड़ें');
  String get pickFromContacts => _t('Pick from contacts', 'कॉन्टैक्ट्स से चुनें');
  String get skipForNow => _t('Skip for now', 'अभी छोड़ें');
  String get finishSetup => _t('Finish setup', 'सेटअप पूरा करें');
  String staffAdded(int n) => _t('$n staff added', '$n स्टाफ़ जोड़े गए');
  String staffSkipped(int n) => _t('$n skipped (duplicate or invalid)', '$n छोड़े गए (दोहराए या ग़लत)');
  String get contactsPermissionDenied =>
      _t('Contacts permission is needed to pick staff.', 'स्टाफ़ चुनने के लिए कॉन्टैक्ट्स की अनुमति चाहिए।');
  String get noContactsWithPhone =>
      _t('No contacts with mobile numbers found', 'मोबाइल नंबर वाले कोई कॉन्टैक्ट नहीं मिले');
  String selectedCount(int n) => _t('$n selected', '$n चुने गए');
  String get monthlySalary => _t('Monthly salary (₹)', 'मासिक सैलरी (₹)');
  String get dailyWage => _t('Daily wage (₹)', 'रोज़ की मज़दूरी (₹)');

  // ------------------------------------------------------------- Weekdays
  String weekday(int d) {
    const en = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const hi = ['रविवार', 'सोमवार', 'मंगलवार', 'बुधवार', 'गुरुवार', 'शुक्रवार', 'शनिवार'];
    return isHindi ? hi[d % 7] : en[d % 7];
  }

  /// "1st & 3rd" / "पहला और तीसरा": weeks of the month.
  String weeksOfMonth(List<int> weeks) {
    const en = ['', '1st', '2nd', '3rd', '4th', '5th'];
    const hi = ['', 'पहला', 'दूसरा', 'तीसरा', 'चौथा', 'पाँचवाँ'];
    final names = [for (final w in weeks) (isHindi ? hi : en)[w.clamp(1, 5)]];
    final last = names.removeLast();
    return names.isEmpty ? last : '${names.join(', ')} ${_t('&', 'और')} $last';
  }

  /// "Sunday, 1st & 3rd Saturday": a shift's days off, alternating weeks included.
  String offDaysText(List<int> days, Map<int, List<int>> weeks) => days
      .map((d) => weeks[d]?.isNotEmpty == true ? '${weeksOfMonth(weeks[d]!)} ${weekday(d)}' : weekday(d))
      .join(', ');
  String get everyWeek => _t('Every week', 'हर हफ़्ते');
  String whichWeekdayOff(String day) => _t('Which ${day}s off?', 'कौन से $day छुट्टी?');

  String weekdayShort(int d) {
    const en = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const hi = ['रवि', 'सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि'];
    return isHindi ? hi[d % 7] : en[d % 7];
  }

  // --------------------------------------------------------- Navigation
  String get navStaff => _t('Staff', 'स्टाफ़');
  String get mint => 'Mint';
  Bi get navTodayBi => _b('Today', 'आज');
  Bi get navStaffBi => _b('Staff', 'स्टाफ़');
  Bi get navSalaryBi => _b('Salary', 'सैलरी');
  Bi get navMoreBi => _b('More', 'और');
  Bi get navHomeBi => _b('Home', 'होम');
  Bi get navAttendanceBi => _b('Attendance', 'हाज़िरी');
  Bi get navLeaveBi => _b('Leave', 'छुट्टी');
  Bi get navProfileBi => _b('Profile', 'प्रोफ़ाइल');
  String get switchLanguage => _t('Switch to Hindi', 'English में बदलें');

  // ------------------------------------------------------------ Statuses
  String statusLabel(String? s) {
    switch (s) {
      case 'present':
        return _t('Present', 'हाज़िर');
      case 'late':
        return _t('Late', 'लेट');
      case 'checked_in':
        return _t('Checked in', 'चेक-इन');
      case 'absent':
        return _t('Absent', 'ग़ैरहाज़िर');
      case 'half_day':
        return _t('Half day', 'आधा दिन');
      case 'leave':
        return _t('On leave', 'छुट्टी पर');
      case 'holiday':
        return _t('Holiday', 'छुट्टी (त्योहार)');
      case 'week_off':
        return _t('Week off', 'साप्ताहिक छुट्टी');
      case 'needs_check':
        return _t('Needs check', 'जाँच ज़रूरी');
      case 'not_marked':
      case null:
        return _t('Not marked', 'दर्ज नहीं');
      default:
        return s;
    }
  }

  /// Short word for status pills (always shown next to an icon).
  String statusShort(String? s) {
    switch (s) {
      case 'present':
        return _t('Present', 'हाज़िर');
      case 'late':
        return _t('Late', 'लेट');
      case 'checked_in':
        return _t('In', 'अंदर');
      case 'absent':
        return _t('Absent', 'ग़ैरहाज़िर');
      case 'half_day':
        return _t('Half day', 'आधा दिन');
      case 'leave':
        return _t('Leave', 'छुट्टी');
      case 'holiday':
        return _t('Holiday', 'त्योहार');
      case 'week_off':
        return _t('Week off', 'साप्ताहिक');
      case 'needs_check':
        return _t('Check', 'जाँचें');
      default:
        return _t('Not in yet', 'अभी नहीं आए');
    }
  }

  /// One/two-letter code for month grids.
  String statusCode(String? s) {
    switch (s) {
      case 'present':
        return _t('P', 'हा');
      case 'late':
        return _t('L', 'ले');
      case 'checked_in':
        return _t('In', 'इन');
      case 'absent':
        return _t('A', 'ग़');
      case 'half_day':
        return _t('HD', 'आ');
      case 'leave':
        return _t('LV', 'छु');
      case 'holiday':
        return _t('H', 'त्यो');
      case 'week_off':
        return _t('WO', 'सा');
      default:
        return '–';
    }
  }

  /// "paid" / "sick" — the word that goes before "leaves" in a sentence.
  String leaveKind(String? t) => t == 'sick' ? _t('sick', 'बीमारी की') : _t('paid', 'पेड');

  String leaveTypeLabel(String? t) {
    switch (t) {
      case 'paid':
        return _t('Paid leave', 'पेड छुट्टी');
      case 'sick':
        return _t('Sick leave', 'बीमारी की छुट्टी');
      case 'unpaid':
        return _t('Unpaid leave', 'बिना पैसे की छुट्टी');
      default:
        return t ?? '';
    }
  }

  String leaveStatusLabel(String s) {
    switch (s) {
      case 'pending':
        return _t('Pending', 'बाक़ी');
      case 'approved':
        return _t('Approved', 'मंज़ूर');
      case 'rejected':
        return _t('Rejected', 'नामंज़ूर');
      case 'cancelled':
        return _t('Cancelled', 'रद्द');
      default:
        return s;
    }
  }

  String flagLabel(String f) {
    switch (f) {
      case 'late_sync':
        return _t('Synced late (offline)', 'देर से सिंक (ऑफ़लाइन)');
      case 'device_time_drift':
        return _t('Phone time was wrong', 'फ़ोन का समय ग़लत था');
      case 'mock_location':
        return _t('Fake GPS suspected', 'नकली GPS का शक');
      case 'low_accuracy':
        return _t('Weak GPS signal', 'कमज़ोर GPS सिग्नल');
      case 'outside_geofence':
        return _t('Outside shop area', 'दुकान के दायरे से बाहर');
      case 'missing_checkout':
        return _t('No check-out', 'चेक-आउट नहीं किया');
      case 'phone_lock_failed':
        return _t('Phone lock didn\'t open', 'फ़ोन लॉक नहीं खुला');
      case 'no_phone_lock':
        return _t('No phone lock', 'फ़ोन पर लॉक नहीं');
      case 'face_mismatch':
        return _t('Face does not match', 'चेहरा मेल नहीं खाता');
      case 'face_unsure':
        return _t('Face not clear', 'चेहरा साफ़ नहीं');
      case 'face_no_face':
        return _t('No face in selfie', 'सेल्फ़ी में चेहरा नहीं');
      case 'face_many_faces':
        return _t('More than one face', 'एक से ज़्यादा चेहरे');
      case 'face_check_failed':
        return _t('Face check failed', 'चेहरा जाँच नहीं हो पाई');
      default:
        return f.replaceAll('_', ' ');
    }
  }

  String approvalLabel(String a) {
    switch (a) {
      case 'pending':
        return _t('Waiting for approval', 'मंज़ूरी बाक़ी');
      case 'approved':
        return _t('Approved', 'मंज़ूर');
      case 'rejected':
        return _t('Rejected', 'नामंज़ूर');
      default:
        return '';
    }
  }

  // ----------------------------------------------------------- Owner home
  String hello(String name) => name.isEmpty ? _t('Hello!', 'नमस्ते!') : _t('Hello, $name', 'नमस्ते, $name');
  String get needsAction => _t('Needs action', 'आपका ध्यान चाहिए');
  String get addAdvance => _t('Add advance', 'एडवांस जोड़ें');
  String get addStaff => _t('Add staff', 'स्टाफ़ जोड़ें');
  String get approve => _t('Approve', 'मंज़ूर करें');
  String get reject => _t('Reject', 'नामंज़ूर करें');
  String get approved => _t('Approved', 'मंज़ूर किया');
  String get rejected => _t('Rejected', 'नामंज़ूर किया');
  String leaveRequestLine(String type, String from, String to, num days) =>
      _t('$type · $from – $to ($days days)', '$type · $from – $to ($days दिन)');
  String get outsidePunchApproval => _t('Punch outside shop area', 'दुकान के दायरे से बाहर चेक-इन');
  String get lockPunchApproval => _t('Punch without phone lock', 'फ़ोन लॉक खोले बिना चेक-इन');
  String lockTagShort(String issue) => issue == 'failed' ? _t('Lock ✗', 'लॉक ✗') : _t('No lock', 'बिना लॉक');
  String distanceAway(num m) => _t('${m.round()} m away', '${m.round()} मीटर दूर');
  String staffUsage(int count, int limit) =>
      _t('$count of $limit staff on your plan', 'आपके प्लान में $limit में से $count स्टाफ़');

  // ---------------------------------------------------------------- Staff
  String get staffTitle => _t('Staff', 'स्टाफ़');
  String get searchStaff => _t('Search by name or phone', 'नाम या फ़ोन से खोजें');
  String get noStaffYet => _t('No staff yet. Add your first staff member.', 'अभी कोई स्टाफ़ नहीं। पहला स्टाफ़ जोड़ें।');
  String get showInactive => _t('Show inactive', 'काम छोड़ चुके भी दिखाएँ');
  String get inactive => _t('Inactive', 'काम छोड़ दिया');
  String get designation => _t('Designation', 'पद');
  String get designationHint => _t('e.g. Helper, Pharmacist', 'जैसे हेल्पर, फ़ार्मासिस्ट');
  String get wageType => _t('Salary type', 'सैलरी का प्रकार');
  String get wageMonthly => _t('Monthly', 'मासिक');
  String get wageDaily => _t('Daily', 'रोज़ाना');
  String get shift => _t('Shift', 'शिफ़्ट');
  String get branch => _t('Branch', 'ब्रांच');
  String get joiningDate => _t('Joining date', 'जॉइनिंग की तारीख़');
  String get salary => _t('Salary', 'सैलरी');
  String perMonth(String amount) => _t('$amount / month', '$amount / महीना');
  String perDay(String amount) => _t('$amount / day', '$amount / दिन');
  String get advanceBalance => _t('Advance balance', 'बाक़ी एडवांस');
  String get leaveBalance => _t('Leave balance', 'छुट्टी बैलेंस');
  String leaveLeft(num paid, num sick) =>
      _t('Paid: $paid left · Sick: $sick left', 'पेड: $paid बाक़ी · बीमारी: $sick बाक़ी');
  String get editLeaveBalance => _t('Set leave balance', 'छुट्टी बैलेंस सेट करें');
  String get paidLeaves => _t('Paid leaves (per year)', 'पेड छुट्टियाँ (साल में)');
  String get sickLeaves => _t('Sick leaves (per year)', 'बीमारी की छुट्टियाँ (साल में)');
  String get device => _t('Phone', 'फ़ोन');
  String get deviceBound => _t('Linked to a phone', 'एक फ़ोन से जुड़ा है');
  String get deviceNotLinked => _t('Not logged in yet', 'अभी लॉगिन नहीं किया');
  String get resetDevice => _t('Reset phone', 'फ़ोन रीसेट करें');
  String get resetDeviceConfirm =>
      _t('Staff can then log in from a new phone. Continue?', 'इसके बाद स्टाफ़ नए फ़ोन से लॉगिन कर सकेगा। आगे बढ़ें?');
  String get deviceReset => _t('Phone reset done', 'फ़ोन रीसेट हो गया');
  String get deactivate => _t('Deactivate staff', 'स्टाफ़ ने काम छोड़ दिया');
  String get deactivateConfirm => _t(
    'They will not be able to check in and will not appear in salary.',
    'वे हाज़िरी नहीं लगा पाएँगे और सैलरी में नहीं दिखेंगे।',
  );
  String get deactivated => _t('Staff deactivated', 'स्टाफ़ को हटा दिया गया');
  String get editStaff => _t('Edit staff', 'स्टाफ़ बदलें');
  String get effectiveFrom => _t('Salary change effective from', 'सैलरी बदलाव कब से लागू');
  String get staffSaved => _t('Staff saved', 'स्टाफ़ सेव हो गया');
  String get callStaff => _t('Call', 'कॉल करें');
  String get consentGiven => _t('Location consent given', 'लोकेशन की सहमति दी');
  String get consentPending => _t('Location consent pending', 'लोकेशन की सहमति बाक़ी');
  String get none => _t('None', 'कोई नहीं');
  String get defaultShift => _t('Default shift', 'मुख्य शिफ़्ट');

  // ----------------------------------------------------------- Attendance
  String get noAttendanceRows => _t('No staff to show for this day', 'इस दिन के लिए कोई स्टाफ़ नहीं');
  String get changeStatus => _t('Change status', 'स्थिति बदलें');
  String get overrideReasonHint => _t('Why are you changing it?', 'आप इसे क्यों बदल रहे हैं?');
  String get reasonRequired => _t('Please write a reason', 'कृपया कारण लिखें');
  String get attendanceUpdated => _t('Attendance updated', 'हाज़िरी अपडेट हो गई');
  String get punches => _t('Punches', 'चेक-इन');
  String get noPunches => _t('No punches', 'कोई चेक-इन नहीं');
  String get checkInLabel => _t('Check-in', 'चेक-इन');
  String get checkOutLabel => _t('Check-out', 'चेक-आउट');
  String lateBy(int m) => _t('Late by $m min', '$m मिनट लेट');
  String earlyOutBy(int m) => _t('Left $m min early', '$m मिनट जल्दी गए');
  String worked(String d) => _t('Worked $d', '$d काम किया');
  String get overriddenTag => _t('Changed by owner', 'मालिक ने बदला');
  String accuracy(num m) => _t('±${m.round()} m', '±${m.round()} मीटर');
  String get insideArea => _t('Inside shop area', 'दुकान के दायरे में');
  String get outsideArea => _t('Outside shop area', 'दुकान के दायरे से बाहर');
  String get openMap => _t('Open in map', 'नक्शे में खोलें');
  String get legend => _t('Legend', 'संकेत');
  String get leaveTypeTitle => _t('Leave type', 'छुट्टी का प्रकार');
  String get totals => _t('Totals', 'कुल');

  // --------------------------------------------------------------- Salary
  String get prepareSalary => _t('Calculate salary', 'सैलरी निकालें');
  String get recalculate => _t('Recalculate', 'फिर से निकालें');
  String get noRunYet => _t('Salary for this month is not calculated yet.', 'इस महीने की सैलरी अभी नहीं निकाली गई है।');

  String revisionLabel(int r) =>
      _t('Changed after approval · old slip kept', 'मंज़ूरी के बाद बदला · पुरानी स्लिप रखी है');
  String get totalNet => _t('Total to pay', 'कुल देना है');
  String get deductions => _t('Deductions', 'कटौती');
  String employeesCount(int n) => _t('$n staff', '$n स्टाफ़');
  String get anomalies => _t('Please check', 'कृपया जाँचें');
  String get sendPayslips => _t('Send salary slips', 'सैलरी स्लिप भेजें');
  String payslipsQueued(int n) => _t('$n salary slips are being sent', '$n सैलरी स्लिप भेजी जा रही हैं');
  String get markPaid => _t('Mark as paid', 'पैसे दे दिए — मार्क करें');
  String get revise => _t('Change salary', 'सैलरी बदलें');
  String get reviseConfirm => _t(
    'A new draft (revision) will be created from current attendance.',
    'मौजूदा हाज़िरी से नया ड्राफ़्ट (संशोधन) बनेगा।',
  );
  String payableDays(num d, num div) => _t('Payable days: $d / $div', 'पैसे वाले दिन: $d / $div');
  String get payslips => _t('Salary slips', 'सैलरी स्लिप');
  String get advances => _t('Advances (udhaar)', 'एडवांस (उधार)');
  String get bonusDeduction => _t('Bonus / cut', 'बोनस / कटौती');
  String get noAdvances => _t('No advances', 'कोई एडवांस नहीं');
  String get noAdjustments => _t('No bonus or deduction this month', 'इस महीने कोई बोनस या कटौती नहीं');
  String get bonus => _t('Bonus', 'बोनस');
  String get deduction => _t('Deduction', 'कटौती');
  String get addAdjustment => _t('Add bonus / deduction', 'बोनस / कटौती जोड़ें');
  String get advanceMode => _t('How to recover', 'कैसे वापस लें');
  String get modeInstallments => _t('In installments', 'किस्तों में');
  String get modeFullNext => _t('Full from next salary', 'अगली सैलरी से पूरा');
  String get installments => _t('Number of installments', 'किस्तों की संख्या');
  String installmentInfo(String amt, int n) => _t('$amt × $n installments', '$amt × $n किस्तें');
  String repaidOf(String repaid, String total) => _t('Repaid $repaid of $total', '$total में से $repaid वापस');
  String get balance => _t('Balance', 'बाक़ी');
  String get advanceAdded => _t('Advance recorded', 'एडवांस दर्ज हो गया');
  String get skipNextMonth => _t('Skip this month’s cut', 'इस महीने कटौती न करें');
  String get skipped => _t('Skipped', 'छोड़ दिया');
  String get activeLabel => _t('Active', 'चालू');
  String get closedLabel => _t('Closed', 'बंद');

  // ----------------------------------------------------------------- More
  String get moreTitle => _t('More', 'और');
  String get leaveRequests => _t('Leave requests', 'छुट्टी की अर्ज़ियाँ');
  String get reports => _t('Reports', 'रिपोर्ट');
  String get settings => _t('Settings', 'सेटिंग्स');
  String get billing => _t('Plan & payment', 'प्लान और पेमेंट');
  String get auditLog => _t('Audit log', 'बदलावों का रिकॉर्ड');
  String get exportData => _t('Export all data', 'सारा डेटा डाउनलोड करें');
  String get exportHint => _t('Excel + salary slip PDFs. Always free.', 'Excel + सैलरी स्लिप PDF। हमेशा मुफ़्त।');
  String exportSaved(String path) => _t('Saved to $path', '$path में सेव हुआ');
  String get language => _t('Language', 'भाषा');
  String get help => _t('Help', 'मदद');
  String get pending => _t('Pending', 'बाक़ी');
  String get all => _t('All', 'सभी');
  String get noLeaveRequests => _t('No leave requests', 'कोई छुट्टी की अर्ज़ी नहीं');

  String get reportAttendance => _t('Attendance sheet', 'हाज़िरी शीट');
  String get reportSalary => _t('Salary register', 'सैलरी रजिस्टर');
  String get reportAdvances => _t('Advances', 'एडवांस');
  String get reportLate => _t('Late list', 'लेट आने वालों की सूची');
  String get downloadPdf => _t('PDF', 'PDF');
  String get downloadExcel => _t('Excel', 'Excel');

  String get companySettings => _t('Business & rules', 'बिज़नेस और नियम');
  String get rulesInPlainWords => _t('Your rules in simple words', 'आपके नियम आसान शब्दों में');
  String get graceMinutes => _t('Late after (grace minutes)', 'कितने मिनट बाद लेट (छूट)');
  String get halfDayHours => _t('Half day if worked less than (hours)', 'इतने घंटे से कम काम पर आधा दिन');
  String get monthDivisor => _t('Salary per day = monthly salary ÷', 'रोज़ की सैलरी = मासिक सैलरी ÷');
  String get divisorDaysInMonth => _t('Days in month', 'महीने के दिन');
  String get divisor30 => _t('30 days', '30 दिन');
  String get divisor26 => _t('26 days', '26 दिन');
  String get missingCheckoutPolicy => _t('If staff forget to check out', 'अगर स्टाफ़ चेक-आउट भूल जाए');
  String get policyHalfDay => _t('Mark half day', 'आधा दिन लगाएँ');
  String get policyPresent => _t('Mark present', 'हाज़िर लगाएँ');
  String get policyFlag => _t('Flag for me to decide', 'मुझे बताएँ, मैं तय करूँगा');
  String get outsideGeofencePolicy => _t('If staff are outside the shop area', 'अगर स्टाफ़ दुकान के दायरे से बाहर हो');
  String get policyBlock => _t('Block check-in', 'चेक-इन रोकें');
  String get policyRequestApproval => _t('Allow, but ask me to approve', 'होने दें, पर मुझसे मंज़ूरी लें');
  String get phoneLockPolicy => _t('Phone lock at check-in', 'चेक-इन पर फ़ोन लॉक');
  String get phoneLockPolicyHelp => _t(
    'Staff unlock their own phone (fingerprint, face, PIN or pattern). StaffMint only learns whether it opened — never the fingerprint or face.',
    'स्टाफ़ अपना फ़ोन लॉक खोलेगा (फ़िंगरप्रिंट, चेहरा, PIN या पैटर्न)। StaffMint को सिर्फ़ इतना पता चलता है कि लॉक खुला या नहीं — फ़िंगरप्रिंट या चेहरा कभी नहीं।',
  );
  String get lockPolicyOff => _t('Don\'t ask', 'न पूछें');
  String get lockPolicyRecommended => _t('Ask, tag me if it fails', 'पूछें, न खुले तो मुझे टैग दिखाएँ');
  String get lockPolicyRequired => _t('Ask, I approve if it fails', 'पूछें, न खुले तो मेरी मंज़ूरी');
  String get digestTime => _t('Daily summary time', 'रोज़ की रिपोर्ट का समय');
  String get weekOffsPaid => _t('Weekly offs are paid', 'साप्ताहिक छुट्टी के पैसे मिलेंगे');
  String get holidaysPaid => _t('Holidays are paid', 'त्योहार की छुट्टी के पैसे मिलेंगे');
  String get sickLeavePaid => _t('Sick leave is paid', 'बीमारी की छुट्टी के पैसे मिलेंगे');
  String get selfieRequired => _t('Selfie required at check-in', 'चेक-इन पर सेल्फ़ी ज़रूरी');
  String get roundToRupee => _t('Round salary to nearest rupee', 'सैलरी पूरे रुपये में करें');
  String get whatsappAlerts => _t('WhatsApp alerts', 'WhatsApp अलर्ट');
  String get shifts => _t('Shifts', 'शिफ़्ट');
  String get addShift => _t('Add shift', 'शिफ़्ट जोड़ें');
  String get shiftName => _t('Shift name', 'शिफ़्ट का नाम');
  String get startTime => _t('Start', 'शुरू');
  String get endTime => _t('End', 'ख़त्म');
  String get weeklyOff => _t('Weekly off', 'साप्ताहिक छुट्टी');
  String get useCompanyGrace => _t('Grace minutes (blank = business default)', 'छूट के मिनट (ख़ाली = बिज़नेस का नियम)');
  String get geofence => _t('Shop location & area', 'दुकान की लोकेशन और दायरा');
  String get geofenceHint =>
      _t('Staff can check in only inside this circle.', 'स्टाफ़ सिर्फ़ इस घेरे के अंदर चेक-इन कर सकता है।');
  String radiusLabel(int m) => _t('Radius: $m m', 'दायरा: $m मीटर');
  String get branches => _t('Branches', 'ब्रांच');
  String get addBranch => _t('Add branch', 'ब्रांच जोड़ें');
  String get branchName => _t('Branch name', 'ब्रांच का नाम');
  String get holidays => _t('Holidays', 'छुट्टियाँ (त्योहार)');
  String get addHoliday => _t('Add holiday', 'छुट्टी जोड़ें');
  String get holidayName => _t('Holiday name', 'छुट्टी का नाम');
  String get noHolidays => _t('No holidays added for this year', 'इस साल कोई छुट्टी नहीं जोड़ी गई');
  String get settingsSaved => _t('Settings saved', 'सेटिंग्स सेव हो गईं');

  String get currentPlan => _t('Current plan', 'मौजूदा प्लान');
  String subscriptionStatus(String s) {
    switch (s) {
      case 'trialing':
        return _t('Free trial', 'फ़्री ट्रायल');
      case 'active':
        return _t('Active', 'चालू');
      case 'past_due':
        return _t('Payment due', 'पेमेंट बाक़ी');
      case 'cancelled':
        return _t('Cancelled', 'रद्द');
      case 'free':
        return _t('Free', 'मुफ़्त');
      default:
        return s;
    }
  }

  String renewsOn(String d) => _t('Renews / ends on $d', '$d को रिन्यू / ख़त्म');
  String staffLimit(int n) => _t('Up to $n staff', '$n स्टाफ़ तक');
  String priceMonthly(String p) => _t('$p / month', '$p / महीना');
  String priceYearly(String p) => _t('$p / year', '$p / साल');
  String get monthly => _t('Monthly', 'मासिक');
  String get yearly => _t('Yearly', 'सालाना');
  String get choosePlan => _t('Choose plan', 'प्लान चुनें');
  String get yourPlan => _t('Your plan', 'आपका प्लान');
  String trialDays(int n) => _t('$n-day free trial', '$n दिन का फ़्री ट्रायल');

  // Free trial banner (every new owner tries all features).
  String trialLeft(String plan, int days) => days <= 1
      ? _t('$plan free trial: last day', '$plan फ़्री ट्रायल: आख़िरी दिन')
      : _t('$plan free trial: $days days left', '$plan फ़्री ट्रायल: $days दिन बाक़ी');
  String trialAllOn(String date) => _t(
    'All features are on until $date. Pick a plan any time to keep them.',
    '$date तक सारे फ़ीचर चालू हैं। इन्हें चालू रखने के लिए कभी भी प्लान चुनें।',
  );
  String trialEndsSoon(String date) => _t(
    'Ends on $date. After that you move to Free: your data stays, paid features pause.',
    '$date को ख़त्म होगा। फिर आप फ़्री प्लान पर आ जाएँगे: डेटा रहेगा, पेड फ़ीचर रुक जाएँगे।',
  );
  String get trialEndedTitle => _t('Your free trial has ended', 'आपका फ़्री ट्रायल ख़त्म हो गया');
  String trialEndedBody(String paused) => _t(
    'You are on Free now. Attendance, leave and the daily summary keep working, and all your data is safe.${paused.isEmpty ? '' : ' Paused until you pick a plan: $paused.'}',
    'अब आप Free पर हैं। हाज़िरी, छुट्टी और रोज़ की रिपोर्ट चलती रहेगी, आपका सारा डेटा सुरक्षित है।${paused.isEmpty ? '' : ' प्लान लेने तक रुका है: $paused।'}',
  );
  String get seePlans => _t('See plans', 'प्लान देखें');
  String get upgrade => _t('Upgrade', 'अपग्रेड करें');
  String trialEndsOn(String date) => _t('Free trial until $date', '$date तक फ़्री ट्रायल');
  String trialEndedOn(String date) => _t('Free trial ended on $date', 'फ़्री ट्रायल $date को ख़त्म हुआ');
  String featureLabel(String f) {
    switch (f) {
      case 'attendance':
        return _t('Attendance', 'हाज़िरी');
      case 'leave':
        return _t('Leave', 'छुट्टी');
      case 'digest':
        return _t('Daily summary', 'रोज़ की रिपोर्ट');
      case 'payroll':
        return _t('Salary', 'सैलरी');
      case 'advances':
        return _t('Advances', 'एडवांस');
      case 'payslips':
        return _t('Salary slips', 'सैलरी स्लिप');
      case 'assistant':
        return _t('Ask Mint', 'Mint से पूछें');
      case 'branches':
        return _t('More branches', 'कई ब्रांच');
      case 'reports':
        return _t('Reports', 'रिपोर्ट');
      case 'roster':
        return _t('Roster', 'रोस्टर');
      case 'roster_repeat':
        return _t('Repeat roster every week', 'रोस्टर हर हफ़्ते दोहराना');
      case 'roster_swaps':
        return _t('Shift swaps', 'शिफ़्ट अदला-बदली');
      case 'verification':
        return _t('Documents check', 'दस्तावेज़ जाँच');
      case 'documents':
        return _t('Staff documents', 'स्टाफ़ के दस्तावेज़');
      case 'tracking':
        return _t('Field staff location', 'फ़ील्ड स्टाफ़ की लोकेशन');
      case 'whatsapp_payslips':
        return _t('Salary slips on WhatsApp', 'WhatsApp पर सैलरी स्लिप');
      case 'whatsapp_assistant':
        return _t('WhatsApp assistant', 'WhatsApp सहायक');
      case 'face_match':
        return _t('Face check', 'चेहरा मिलान');
      case 'ca_access':
        return _t('CA access', 'CA एक्सेस');
      case 'priority_support':
        return _t('Priority support', 'प्राथमिक सहायता');
      default:
        return f;
    }
  }

  String get noAuditLogs => _t('No changes recorded yet', 'अभी कोई बदलाव दर्ज नहीं');
  String get loadMore => _t('Load more', 'और दिखाएँ');
  String byActor(String n, String ch) => _t('by $n via $ch', '$n द्वारा ($ch)');
  String get before => _t('Before', 'पहले');
  String get after => _t('After', 'बाद में');

  String get helpTitle => _t('Help & support', 'मदद और सहायता');
  String get chatOnWhatsApp => _t('Chat with us on WhatsApp', 'WhatsApp पर हमसे बात करें');
  String get faq1q => _t('How do staff check in?', 'स्टाफ़ हाज़िरी कैसे लगाएगा?');
  String get faq1a => _t(
    'Add their phone number in Staff. They install StaffMint, log in with OTP and tap Check in near the shop.',
    'स्टाफ़ में उनका फ़ोन नंबर जोड़ें। वे StaffMint इंस्टॉल करके OTP से लॉगिन करें और दुकान के पास चेक-इन दबाएँ।',
  );
  String get faq2q => _t('Staff changed phone?', 'स्टाफ़ ने फ़ोन बदल लिया?');
  String get faq2a => _t(
    'Open their profile in Staff and tap “Reset phone”.',
    'स्टाफ़ में उनकी प्रोफ़ाइल खोलें और “फ़ोन रीसेट करें” दबाएँ।',
  );
  String get faq3q => _t('How is salary calculated?', 'सैलरी कैसे निकलती है?');
  String get faq3a => _t(
    'Monthly salary ÷ days (your setting) × payable days, plus bonus, minus advances and deductions. Every salary slip line explains itself.',
    'मासिक सैलरी ÷ दिन (आपकी सेटिंग) × पैसे वाले दिन, फिर बोनस जुड़ता है और एडवांस व कटौती घटती है। सैलरी स्लिप की हर लाइन का कारण लिखा होता है।',
  );
  String get faq4q => _t('What if there is no internet?', 'अगर इंटरनेट न हो तो?');
  String get faq4a => _t(
    'Check-in is saved on the phone and sent automatically when internet returns, with the original time.',
    'चेक-इन फ़ोन में सेव हो जाता है और इंटरनेट आने पर असली समय के साथ अपने आप भेज दिया जाता है।',
  );
  String get appVersion => _t('App version', 'ऐप वर्ज़न');

  // ------------------------------------------------------------- Employee
  String get consentTitle => _t('Your privacy', 'आपकी प्राइवेसी');
  String consentBody(String company) => _t(
    '$company uses StaffMint to record attendance.\n\n'
        '• When you tap Check in or Check out, we record your location (GPS), a selfie and the time — only at that moment. We never track you in the background.\n'
        '• This data is used only for attendance and salary at $company.\n'
        '• You may be asked to unlock your phone (fingerprint, face, PIN or pattern). Your fingerprint and face never leave your phone — StaffMint only learns whether it unlocked.\n'
        '• Selfies are deleted automatically after 90 days.\n'
        '• You can ask your employer to see or correct your data at any time.\n\n'
        'This notice follows India’s Digital Personal Data Protection (DPDP) Act, 2023.',
    '$company हाज़िरी दर्ज करने के लिए StaffMint का उपयोग करता है।\n\n'
        '• जब आप चेक-इन या चेक-आउट दबाते हैं, तभी आपकी लोकेशन (GPS), सेल्फ़ी और समय दर्ज होता है। हम आपको बैकग्राउंड में कभी ट्रैक नहीं करते।\n'
        '• यह डेटा सिर्फ़ $company में हाज़िरी और सैलरी के लिए इस्तेमाल होता है।\n'
        '• आपसे फ़ोन लॉक (फ़िंगरप्रिंट, चेहरा, PIN या पैटर्न) खोलने को कहा जा सकता है। आपका फ़िंगरप्रिंट और चेहरा आपके फ़ोन से बाहर नहीं जाता — StaffMint को सिर्फ़ पता चलता है कि लॉक खुला या नहीं।\n'
        '• सेल्फ़ी 90 दिन बाद अपने आप मिटा दी जाती हैं।\n'
        '• आप कभी भी अपने मालिक से अपना डेटा देखने या सुधारने को कह सकते हैं।\n\n'
        'यह सूचना भारत के डिजिटल व्यक्तिगत डेटा संरक्षण (DPDP) अधिनियम, 2023 के अनुसार है।',
  );
  String get consentAgree => _t('I agree — allow location at check-in', 'मैं सहमत हूँ — चेक-इन पर लोकेशन की अनुमति');
  String get yourEmployer => _t('Your employer', 'आपके मालिक');

  String get checkIn => _t('Check in', 'हाज़िरी लगाएँ');
  String get checkOut => _t('Check out', 'चेक-आउट करें');
  String get checkOutHint => _t('Going home?', 'घर जा रहे हैं?');
  String get checkInAgain => _t('Check in again', 'फिर से चेक-इन करें');
  String get workingNow => _t('You are checked in', 'आप चेक-इन हैं');
  String get notCheckedIn => _t('You have not checked in yet', 'आपने अभी चेक-इन नहीं किया');
  String get dayComplete => _t('Day complete. Thank you!', 'आज का काम पूरा। धन्यवाद!');
  String checkedInAt(String t) => _t('Checked in at $t', '$t पर चेक-इन');
  String checkedOutAt(String t) => _t('Checked out at $t', '$t पर चेक-आउट');
  String get gettingLocation => _t('Getting your location…', 'आपकी लोकेशन ली जा रही है…');
  String get takingSelfie => _t('Take a selfie', 'सेल्फ़ी लें');
  String get unlockingPhone => _t('Unlock your phone…', 'अपना फ़ोन लॉक खोलें…');
  String get unlockReason => _t('Unlock to check in', 'हाज़िरी के लिए फ़ोन लॉक खोलें');
  String get unlockFailedTitle => _t('Phone lock did not open', 'फ़ोन लॉक नहीं खुला');
  String unlockFailedBody(bool required) => required
      ? _t(
          'Try again, or check in without it — your owner will need to approve this check-in.',
          'फिर कोशिश करें, या बिना लॉक के हाज़िरी लगाएँ — यह हाज़िरी मालिक की मंज़ूरी के बाद लगेगी।',
        )
      : _t(
          'Try again, or check in without it — your owner will see a tag on this check-in.',
          'फिर कोशिश करें, या बिना लॉक के हाज़िरी लगाएँ — मालिक को इस हाज़िरी पर टैग दिखेगा।',
        );
  String get continueWithoutLock => _t('Check in without it', 'बिना लॉक के लगाएँ');
  String get phoneLockLabel => _t('Phone lock', 'फ़ोन लॉक');

  // ---- Face check (live selfie, enrolment, owner review) ----
  Bi livenessHint(String hint) => switch (hint) {
    'noFace' => _b('Face the camera', 'कैमरे की ओर देखें'),
    'manyFaces' => _b('Only you in the photo', 'फ़ोटो में सिर्फ़ आप'),
    'moveCloser' => _b('Come a little closer', 'थोड़ा पास आएँ'),
    'centerFace' => _b('Keep your face in the circle', 'चेहरा गोले के अंदर रखें'),
    'blink' => _b('Now blink once', 'अब एक बार पलक झपकाएँ'),
    'holdStill' => _b('Hold still…', 'स्थिर रहें…'),
    _ => _b('Done!', 'हो गया!'),
  };
  String get takePhotoNow => _t('Take photo now', 'अभी फ़ोटो लें');
  String get cameraUnavailable => _t('Camera not available', 'कैमरा उपलब्ध नहीं');
  Bi get faceCheckBi => _b('Face check', 'चेहरा पहचान');
  String get faceSetupTitle => _t('Set up face check', 'चेहरा पहचान सेट करें');
  String get faceSetupIntro => _t(
    'Your owner uses face check so nobody else can mark attendance for you. Take one clear photo of your face now.',
    'आपके मालिक चेहरा पहचान इस्तेमाल करते हैं ताकि आपकी जगह कोई और हाज़िरी न लगा सके। अभी अपने चेहरे की एक साफ़ फ़ोटो लें।',
  );
  String get faceConsentText => _t(
    'I agree that StaffMint keeps one photo of my face and compares it with my check-in selfies, only to confirm my attendance. '
        'The comparison runs on a secure cloud service in India. My photo is deleted when I leave this job or when I remove it here. '
        'If I say no, I can still check in with a selfie and GPS.',
    'मैं सहमत हूँ कि StaffMint मेरे चेहरे की एक फ़ोटो रखे और उसे मेरी हाज़िरी की सेल्फ़ी से मिलाए — सिर्फ़ मेरी हाज़िरी पक्की करने के लिए। '
        'यह मिलान भारत में एक सुरक्षित क्लाउड सेवा पर होता है। नौकरी छोड़ने पर या यहाँ से हटाने पर मेरी फ़ोटो मिटा दी जाएगी। '
        'मना करने पर भी मैं सेल्फ़ी और GPS से हाज़िरी लगा सकता/सकती हूँ।',
  );
  String get faceAgreeAndTake => _t('Agree & take photo', 'सहमत हूँ, फ़ोटो लें');
  String get faceNotNow => _t('Not now', 'अभी नहीं');
  Bi get facePendingBi => _b('Waiting for owner approval', 'मालिक की मंज़ूरी बाक़ी');
  Bi get faceApprovedBi => _b('Face check is on', 'चेहरा पहचान चालू है');
  String get faceRetake => _t('Take a new photo', 'नई फ़ोटो लें');
  String get faceRemove => _t('Remove my face photo', 'मेरी चेहरे की फ़ोटो हटाएँ');
  String get faceRemoveConfirm => _t(
    'Your photo will be deleted and face check will stop for you. You can set it up again any time.',
    'आपकी फ़ोटो मिटा दी जाएगी और आपके लिए चेहरा पहचान बंद हो जाएगी। आप कभी भी फिर से सेट कर सकते हैं।',
  );
  String get faceRemoved => _t('Face photo removed', 'चेहरे की फ़ोटो हटा दी गई');
  String get faceSent => _t('Photo sent to your owner for approval', 'फ़ोटो मंज़ूरी के लिए मालिक को भेजी गई');
  String get faceSetupBanner => _t('Set up face check — takes 10 seconds', 'चेहरा पहचान सेट करें — 10 सेकंड लगेंगे');
  String faceStatusLabel(String status) => switch (status) {
    'pending' => _t('Waiting for approval', 'मंज़ूरी बाक़ी'),
    'approved' => _t('On', 'चालू'),
    _ => _t('Not set up', 'सेट नहीं'),
  };
  String faceResultLabel(String? r) => switch (r) {
    'match' => _t('Face matches', 'चेहरा मेल खाता है'),
    'unsure' => _t('Face not clear', 'चेहरा साफ़ नहीं'),
    'mismatch' => _t('Face does not match', 'चेहरा मेल नहीं खाता'),
    'no_face' => _t('No face in selfie', 'सेल्फ़ी में चेहरा नहीं'),
    'many_faces' => _t('More than one face', 'एक से ज़्यादा चेहरे'),
    'error' => _t('Face check failed', 'चेहरा जाँच नहीं हो पाई'),
    _ => _t('Not checked', 'जाँच नहीं हुई'),
  };
  String get facePunchApproval => _t('Check the face', 'चेहरा जाँचें');
  String get approvedPhoto => _t('Approved photo', 'मंज़ूर फ़ोटो');
  String get todaysSelfie => _t('Today\'s selfie', 'आज की सेल्फ़ी');
  String get facePhotoToApprove => _t('Face photo to approve', 'चेहरे की फ़ोटो मंज़ूर करें');
  String get faceAskRetake => _t('Ask for a new photo', 'नई फ़ोटो माँगें');
  String get faceMatchPolicy => _t('Face check at check-in', 'चेक-इन पर चेहरा पहचान');
  String get faceMatchPolicyHelp => _t(
    'Each check-in selfie is compared with the staff member\'s approved photo. If it doesn\'t clearly match, the check-in waits for you. Staff must agree before their photo is used. Growth plan and above.',
    'हर चेक-इन की सेल्फ़ी स्टाफ़ की मंज़ूर फ़ोटो से मिलाई जाती है। साफ़ मेल न खाए तो हाज़िरी आपकी मंज़ूरी के बाद लगेगी। स्टाफ़ की सहमति के बिना फ़ोटो इस्तेमाल नहीं होती। Growth प्लान और ऊपर।',
  );
  String get faceMatchOff => _t('Off', 'बंद');
  String get faceMatchReview => _t('On — I approve unclear matches', 'चालू — साफ़ मेल न हो तो मेरी मंज़ूरी');
  String lockCheckLabel(String? v) => switch (v) {
    'passed' => _t('Unlocked', 'खुला'),
    'failed' => _t('Did not open', 'नहीं खुला'),
    'unavailable' => _t('No lock on phone', 'फ़ोन पर लॉक नहीं'),
    _ => _t('Not asked', 'नहीं पूछा'),
  };
  String get facePendingNote => _t(
    'Face not clearly matched — sent to owner for approval',
    'चेहरा साफ़ मेल नहीं खाया — मंज़ूरी के लिए मालिक को भेजा गया',
  );
  String get lockPendingNote =>
      _t('Phone lock not opened — sent to owner for approval', 'फ़ोन लॉक नहीं खुला — मंज़ूरी के लिए मालिक को भेजा गया');
  String get submitting => _t('Saving…', 'सेव हो रहा है…');
  String pendingSync(int n) => _t('$n punch(es) waiting to sync', '$n चेक-इन सिंक होने बाक़ी');
  String get syncNow => _t('Sync now', 'अभी सिंक करें');
  String syncedCount(int n) => _t('$n offline punch(es) synced', '$n ऑफ़लाइन चेक-इन सिंक हुए');
  String syncRejected(String msg) => _t('A saved punch was rejected: $msg', 'एक सेव चेक-इन नहीं माना गया: $msg');
  String get outsideGeofence => _t('You are outside the shop area', 'आप दुकान के दायरे से बाहर हैं');
  String get outsideGeofenceHelp => _t(
    'Move closer to your workplace and try again. If you are at work, ask your owner to check the shop pin.',
    'अपने काम की जगह के पास जाकर फिर कोशिश करें। अगर आप काम पर ही हैं, तो मालिक से दुकान का पिन जाँचने को कहें।',
  );
  String get pendingApprovalNote =>
      _t('Outside shop area — sent to owner for approval', 'दुकान के दायरे से बाहर — मंज़ूरी के लिए मालिक को भेजा गया');
  String get mockLocationWarning =>
      _t('Fake GPS detected. Your owner will be informed.', 'नकली GPS पकड़ा गया। मालिक को सूचना दी जाएगी।');
  String get selfieNeeded => _t('A selfie is needed to check in', 'चेक-इन के लिए सेल्फ़ी ज़रूरी है');
  String get myAttendance => _t('My attendance', 'मेरी हाज़िरी');
  String get applyLeave => _t('Apply for leave', 'छुट्टी के लिए अर्ज़ी');
  String get myLeaves => _t('My leaves', 'मेरी छुट्टियाँ');
  String get halfDayLeave => _t('Half day', 'आधा दिन');
  String get leaveApplied => _t('Leave request sent to owner', 'छुट्टी की अर्ज़ी मालिक को भेज दी गई');
  String get cancelLeave => _t('Cancel request', 'अर्ज़ी रद्द करें');
  String get balances => _t('Balances', 'बैलेंस');
  String paidLeft(num n) => _t('Paid: $n left', 'पेड: $n बाक़ी');
  String sickLeft(num n) => _t('Sick: $n left', 'बीमारी: $n बाक़ी');
  String get mySalary => _t('My salary', 'मेरी सैलरी');
  String get runningEstimate => _t('This month so far (estimate)', 'इस महीने अब तक (अनुमान)');
  String get estimateNote =>
      _t('Final salary may change after owner approval.', 'मालिक की मंज़ूरी के बाद आख़िरी सैलरी बदल सकती है।');
  String get noPayslips => _t('No salary slips yet', 'अभी कोई सैलरी स्लिप नहीं');
  String get myProfile => _t('My profile', 'मेरी प्रोफ़ाइल');

  // ---- Profile ----
  String roleLabel(String role) => switch (role) {
    'owner' => _t('Owner', 'मालिक'),
    'manager' => _t('Manager', 'मैनेजर'),
    'ca' => _t('Accountant', 'अकाउंटेंट'),
    _ => _t('Staff', 'स्टाफ़'),
  };
  String profileComplete(int p) => _t('Profile $p% complete', 'प्रोफ़ाइल $p% पूरी');
  String get profileCompleteHint =>
      _t('Finish these so salary and alerts reach you', 'ये भर दें ताकि सैलरी और सूचनाएँ सही पहुँचें');
  String missingLabel(String k) => switch (k) {
    'photo' => _t('Add photo', 'फ़ोटो लगाएँ'),
    'name' => _t('Add name', 'नाम लिखें'),
    'email' => _t('Add email', 'ईमेल जोड़ें'),
    'bank' => _t('Salary account', 'सैलरी खाता'),
    _ => _t('Emergency contact', 'आपात संपर्क'),
  };
  Bi get personalBi => _b('Personal details', 'निजी जानकारी');
  Bi get workBi => _b('Work', 'काम');
  Bi get salaryAccountBi => _b('Salary account', 'सैलरी खाता');
  Bi get emergencyBi => _b('Emergency contact', 'आपात संपर्क');
  Bi get businessBi => _b('Business', 'बिज़नेस');
  Bi get accountBi => _b('Account & security', 'खाता और सुरक्षा');
  String get fullName => _t('Name', 'नाम');
  String get mobileLabel => _t('Mobile', 'मोबाइल');
  String get emailLabel => _t('Email', 'ईमेल');
  String get emailHint => _t('For reports and receipts (optional)', 'रिपोर्ट और रसीद के लिए (ज़रूरी नहीं)');
  String get notAdded => _t('Not added', 'नहीं जोड़ा');
  String get removeLabel => _t('Remove', 'हटाएँ');
  String get designationLabel => _t('Role', 'पद');
  String get joinedOn => _t('Joined', 'जॉइन किया');
  String get branchLabel => _t('Branch', 'ब्रांच');
  String get salaryLabel => _t('Salary', 'सैलरी');
  String get setByOwner =>
      _t('Set by your owner. Ask them to change it.', 'मालिक तय करते हैं। बदलवाने के लिए उनसे कहें।');
  String get addSalaryAccount => _t('Add salary account', 'सैलरी खाता जोड़ें');
  String get salaryAccountHint =>
      _t('Bank account or UPI where your salary is paid', 'बैंक खाता या UPI जहाँ सैलरी आती है');
  String get accountHolder => _t('Account holder name', 'खाताधारक का नाम');
  String get accountNumber => _t('Account number', 'खाता नंबर');
  String get confirmAccountNumber => _t('Re-enter account number', 'खाता नंबर दोबारा लिखें');
  String get accountsDontMatch => _t('Account numbers don\'t match', 'खाता नंबर मेल नहीं खाते');
  String get ifscLabel => _t('IFSC code', 'IFSC कोड');
  String get upiLabel => _t('UPI ID', 'UPI ID');
  String get bankOrUpi => _t('Add a bank account or a UPI ID', 'बैंक खाता या UPI ID में से एक भरें');
  String get invalidAccount => _t('9–18 digits', '9–18 अंक');
  String get retypeAccount => _t('Type the full number again to keep it', 'रखने के लिए पूरा नंबर दोबारा लिखें');
  String get invalidIfsc => _t('Like SBIN0001234', 'जैसे SBIN0001234');
  String get invalidUpi => _t('Like name@okaxis', 'जैसे name@okaxis');
  String get ownerNotifiedBank =>
      _t('Your owner is told whenever this changes.', 'इसे बदलने पर मालिक को सूचना जाती है।');
  String get salaryAccountSaved => _t('Salary account saved', 'सैलरी खाता सेव हुआ');
  String get removeSalaryAccount => _t('Remove salary account?', 'सैलरी खाता हटाएँ?');
  String get contactName => _t('Contact name', 'नाम');
  String get contactPhone => _t('Phone', 'फ़ोन');
  String get relationLabel => _t('Relation', 'रिश्ता');
  List<String> get relations => isHindi
      ? const ['पिता', 'माता', 'पति/पत्नी', 'भाई', 'बहन', 'दोस्त']
      : const ['Father', 'Mother', 'Spouse', 'Brother', 'Sister', 'Friend'];
  String get emergencyHint =>
      _t('Who should we call if something happens at work?', 'काम पर कुछ हो तो किसे फ़ोन करें?');
  String get planLabel => _t('Plan', 'प्लान');
  String get manageBusiness => _t('Business settings', 'बिज़नेस सेटिंग्स');
  String get logoutAll => _t('Log out of all devices', 'सभी फ़ोन से लॉग आउट');
  String get logoutAllConfirm => _t(
    'You will be logged out on every phone and computer, including this one.',
    'आप हर फ़ोन और कंप्यूटर से लॉग आउट हो जाएँगे, इस फ़ोन से भी।',
  );
  String memberSince(String d) => _t('Member since $d', '$d से सदस्य');
  String get changePhoto => _t('Profile photo', 'प्रोफ़ाइल फ़ोटो');
  String get takePhoto => _t('Take photo', 'फ़ोटो खींचें');
  String get chooseFromGallery => _t('Choose from gallery', 'गैलरी से चुनें');
  String get removePhoto => _t('Remove photo', 'फ़ोटो हटाएँ');
  String get changeMobile => _t('Change mobile number', 'मोबाइल नंबर बदलें');
  String get newMobile => _t('New mobile number', 'नया मोबाइल नंबर');
  String get changeMobileHint => _t(
    'We will send a code to the new number. You will log in with it from now on.',
    'नए नंबर पर कोड भेजेंगे। अब से उसी नंबर से लॉगिन होगा।',
  );
  String codeSentTo(String phone) => _t('Code sent to $phone', '$phone पर कोड भेजा');
  String get sendCode => _t('Send code', 'कोड भेजें');
  String get verifyAndChange => _t('Verify & change', 'जाँचें और बदलें');
  String get mobileChanged => _t('Mobile number changed', 'मोबाइल नंबर बदल गया');
  String get requiredField => _t('Required', 'ज़रूरी है');
  String get invalidEmail => _t('Email looks wrong', 'ईमेल सही नहीं लगता');
  String get viewProfile => _t('View profile', 'प्रोफ़ाइल देखें');
  String get or => _t('or', 'या');

  // ---- Owner or staff? ----
  String get whoAreYou => _t('How will you use StaffMint?', 'आप StaffMint कैसे इस्तेमाल करेंगे?');
  String get whoAreYouHint => _t('This number is new to StaffMint.', 'यह नंबर StaffMint पर नया है।');
  String get iOwnBusiness => _t('I own a business', 'मेरा बिज़नेस है');
  String get iOwnBusinessHint => _t('Set up my shop and add my staff', 'दुकान सेट करें और स्टाफ़ जोड़ें');
  String get iWorkAtShop => _t('I work at a shop', 'मैं किसी दुकान पर काम करता/करती हूँ');
  String get iWorkAtShopHint => _t('Mark my attendance and see my salary', 'हाज़िरी लगाएँ और सैलरी देखें');
  String get askEmployerTitle => _t('Ask your employer to add you', 'मालिक से आपको जोड़ने को कहें');
  String get askEmployerBody => _t(
    'Your employer adds you in StaffMint with this mobile number. Then tap "Check again" — no need to log in again.',
    'मालिक इसी मोबाइल नंबर से आपको StaffMint में जोड़ेंगे। फिर "फिर से जाँचें" दबाएँ — दोबारा लॉगिन की ज़रूरत नहीं।',
  );
  String get yourNumber => _t('Your number', 'आपका नंबर');
  String get checkAgain => _t('Check again', 'फिर से जाँचें');
  String get notAddedYet => _t(
    'Not added yet. Ask your employer to add this number.',
    'अभी तक नहीं जोड़ा गया। मालिक से यह नंबर जोड़ने को कहें।',
  );
  String get useAnotherNumber => _t('Use another number', 'दूसरा नंबर इस्तेमाल करें');
  String get hindi => 'हिन्दी';
  String get english => 'English';

  // ------------------------------------------------------------ Assistant
  String get mintWelcome => _t(
    'Namaste! I am Mint. Type or hold the mic and speak — in Hindi, English or Hinglish.',
    'नमस्ते! मैं Mint हूँ। टाइप करें या माइक दबाकर बोलें — हिन्दी, English या Hinglish में।',
  );
  String get typeMessage => _t('Type a message…', 'मैसेज लिखें…');
  String get holdToTalk => _t('Hold the mic to talk', 'बोलने के लिए माइक दबाए रखें');
  String get listening => _t('Listening… release to send', 'सुन रहा हूँ… भेजने के लिए छोड़ें');
  String get micPermissionDenied =>
      _t('Microphone permission is needed for voice.', 'आवाज़ के लिए माइक की अनुमति चाहिए।');
  String get mintThinking => _t('Mint is thinking…', 'Mint सोच रहा है…');
  String get openAttachment => _t('Open file', 'फ़ाइल खोलें');
  String get actionCancelled => _t('Cancelled', 'रद्द किया गया');
  String get newChat => _t('New chat', 'नई बातचीत');

  // ---------------------------------------------------------------- Today
  String get todayTitle => _t('Today’s attendance', 'आज की हाज़िरी');
  String get dayTitle => _t('Attendance', 'हाज़िरी');
  Bi get presentBi => _b('Present', 'हाज़िर');
  String chipLate(int n) => _t('Late $n', 'लेट $n');
  String chipLeave(int n) => _t('Leave $n', 'छुट्टी $n');
  String chipAbsent(int n) => _t('Absent $n', 'ग़ैरहाज़िर $n');
  String chipRemaining(int n) => _t('Not yet $n', 'बाकी $n');
  String minutesShort(int m) => _t('$m min', '$m मिनट');
  String metersShort(num m) => _t('${m.round()} m', '${m.round()} मी');
  Bi needsYouTitle(int n) => _b(n == 1 ? '1 thing needs you' : '$n things need you', '$n काम आपके लिए');
  String needsYouLeave(String name) => _t('$name’s leave', '$name की छुट्टी');
  String needsYouPunch(String name) => _t('$name’s check-in needs a look', '$name का चेक-इन देख लें');
  String needsYouFlag(String name) => _t('$name: check', '$name: जाँचें');
  String needsYouFace(String name) => _t('$name’s face photo', '$name की फ़ोटो');
  String get view => _t('View', 'देखें');
  String get hide => _t('Hide', 'छुपाएँ');
  String get swipeHint => _t('Swipe right to approve, left to reject', 'दाएँ खिसकाएँ = मंज़ूर, बाएँ = नामंज़ूर');
  String get tapStatusHint => _t('Tap a status to save it', 'स्थिति दबाते ही सेव हो जाएगी');
  String get details => _t('Details', 'पूरी जानकारी');
  Bi get reasonOwnerConfirmed => _b('Owner confirmed', 'मालिक ने बताया');
  Bi get reasonDoctor => _b('Doctor', 'डॉक्टर');
  Bi get reasonLateBus => _b('Late bus', 'देर से बस');
  Bi get reasonPhoneIssue => _b('Phone issue', 'फ़ोन ख़राब');
  String statusSaved(String name, String status) => _t('$name: $status · saved', '$name: $status · सेव हुआ');
  String get undo => _t('Undo', 'वापस लें');
  String get undone => _t('Change undone', 'बदलाव वापस लिया');
  String get dayMonthToggle => _t('Day / month view', 'दिन / महीना');

  // ------------------------------------------------- Home (redesign, Oct 2026)
  String get switchBusiness => _t('Switch', 'बदलें');
  String todayOn(String day) => _t('Today, $day', 'आज, $day');
  String get dayTab => _t('Day', 'दिन');
  String get monthTab => _t('Month', 'महीना');
  String atWorkSummary(int n, int total) => _t('$n of $total at work', '$total में से $n काम पर');
  String chipPresentN(int n) => _t('$n present', '$n हाज़िर');
  String chipLateN(int n) => _t('$n late', '$n लेट');
  String chipLeaveN(int n) => _t('$n on leave', '$n छुट्टी पर');
  String chipAbsentN(int n) => _t('$n absent', '$n ग़ैरहाज़िर');
  String chipHalfDayN(int n) => _t('$n half day', '$n आधा दिन');
  String chipNotInN(int n) => _t('$n not in yet', '$n अभी नहीं आए');
  String get colInAt => _t('In at', 'आए');
  String get colName => _t('Name', 'नाम');
  String get colStatus => _t('Status', 'स्थिति');
  String get rowNotInstalled => _t('Hasn’t installed the app', 'ऐप इंस्टॉल नहीं किया');
  String get rowInvited => _t('Invited', 'बुलाया');
  String get rowNotCheckedIn => _t('Not checked in yet', 'अभी चेक-इन नहीं किया');
  String get rowLeaveApproved => _t('Leave approved', 'छुट्टी मंज़ूर');
  String rowLateBy(int m) => _t('$m min late', '$m मिनट लेट');
  String get rowChangedByYou => _t('Changed by you', 'आपने बदला');
  String get rowChangedByOther => _t('Changed by owner', 'मालिक ने बदला');
  String rowAway(num m) => _t('${m.round()} m from shop', 'दुकान से ${m.round()} मी दूर');
  String get weeklyOffTitle => _t('Weekly off today', 'आज साप्ताहिक छुट्टी');
  String get weeklyOffBody =>
      _t('Shop is closed today. Nobody needs to check in.', 'आज दुकान बंद है। किसी को चेक-इन नहीं करना है।');
  String holidayTitle(String name) => _t('Holiday: $name', 'छुट्टी: $name');
  String get holidayBody => _t('Nobody needs to check in today.', 'आज किसी को चेक-इन नहीं करना है।');
  String get dayOffPastTitle => _t('Shop was closed this day', 'इस दिन दुकान बंद थी');
  String get showStaffList => _t('Show staff list', 'स्टाफ़ की सूची देखें');
  String get changeDate => _t('change', 'बदलें');
  String needYourOk(int n) =>
      _t(n == 1 ? '1 thing needs your OK' : '$n things need your OK', '$n काम आपकी मंज़ूरी के लिए');
  String get review => _t('Review', 'देखें');
  String okAskedLeave(String name) => _t('$name asked for leave', '$name ने छुट्टी माँगी');
  String okFarPunch(String name) => _t('$name checked in away from shop', '$name ने दुकान से दूर चेक-इन किया');
  String okCheck(String name) => _t('$name: please check', '$name: जाँच लें');
  String wantsLeave(String name) => _t('$name wants leave', '$name छुट्टी चाहते हैं');
  String leaveBalanceEffect(String type, num left, num after) => _t(
    'Has ${_num(left)} $type leaves left. After this: ${_num(after)}.',
    '${_num(left)} $type छुट्टियाँ बाकी हैं। इसके बाद: ${_num(after)}।',
  );
  String get sayNo => _t('Say no', 'मना करें');
  String checkedInAway(String name, String away) => _t('$name checked in $away', '$name ने चेक-इन किया · $away');
  String get countIt => _t('Count it', 'मान लें');
  String get dontCount => _t('Don’t count', 'न मानें');
  String statusMeaning(String status) => switch (status) {
    'present' => _t('full day', 'पूरा दिन'),
    'half_day' => _t('half pay', 'आधा पैसा'),
    'absent' => _t('no pay', 'पैसा नहीं'),
    'leave' => _t('uses leave', 'छुट्टी कटेगी'),
    'holiday' => _t('paid', 'पैसा मिलेगा'),
    'week_off' => _t('shop closed', 'दुकान बंद'),
    _ => '',
  };
  String get whatHappened => _t('What happened this day?', 'इस दिन क्या हुआ?');
  String get reasonOptional => _t('Reason (optional)', 'कारण (ज़रूरी नहीं)');
  String get writeReason => _t('Write', 'लिखें');
  String get seePhotoMap => _t('See check-in photo & map', 'चेक-इन फ़ोटो और नक्शा देखें');
  String cameInAt(String t) => _t('came in $t', '$t पर आए');
  String get pickStatusFirst => _t('Pick what happened', 'पहले चुनें क्या हुआ');
  String markedAs(String name, String status) => _t('$name marked $status', '$name: $status');
  String get monthPersonHeader => _t('Person · tap for their calendar', 'व्यक्ति · कैलेंडर के लिए दबाएँ');
  String get daysPresentHeader => _t('Days present', 'हाज़िर दिन');
  String get seeEveryoneGrid => _t('See everyone day by day', 'सबको दिन-ब-दिन देखें');
  String get gridHint => _t(
    'Full grid for the month, good for checking before salary.',
    'पूरे महीने की तालिका — सैलरी से पहले जाँचने के लिए।',
  );
  String get gridLabel => _t('Grid', 'तालिका');
  String get personMonthHint =>
      _t('Tap any day to see times or change it.', 'समय देखने या बदलने के लिए कोई भी दिन दबाएँ।');
  String daysPresentOf(num n, num of) =>
      _t('${_num(n)} of ${_num(of)} days present', '${_num(of)} में से ${_num(n)} दिन हाज़िर');
  String get allGood => _t('All good', 'सब ठीक');
  String get offShort => _t('Off', 'बंद');
  String get setupTitle => _t('Let’s get your shop running', 'चलिए दुकान शुरू करते हैं');
  String setupCount(int d, int t) => _t('$d of $t', '$t में से $d');
  String get setupBusiness => _t('Create your business', 'बिज़नेस बनाएँ');
  String get setupStaff => _t('Add your staff', 'स्टाफ़ जोड़ें');
  String get setupJoin => _t('Staff install the app & check in', 'स्टाफ़ ऐप इंस्टॉल करके चेक-इन करें');
  String get setupSalary => _t('Set each person’s salary', 'हर व्यक्ति की सैलरी डालें');
  String get setupTeam => _t('Add your CA or partner (optional)', 'CA या पार्टनर जोड़ें (ज़रूरी नहीं)');
  String invitedJoined(int n, int j) => _t('$n staff invited · $j have joined', '$n स्टाफ़ को बुलाया · $j जुड़े');
  String get remind => _t('Remind', 'याद दिलाएँ');
  String remindSent(int n) => _t(
    n == 0 ? 'Invites were sent a few minutes ago' : 'Invite sent again to $n',
    n == 0 ? 'कुछ मिनट पहले भेजा जा चुका है' : '$n को फिर से भेजा',
  );
  String get emptyStaffHome =>
      _t('Your staff will appear here once you add them.', 'स्टाफ़ जोड़ने के बाद वे यहाँ दिखेंगे।');
  String get askMint => _t('Ask Mint', 'Mint से पूछें');
  String get tipMonth =>
      _t('Month: see the whole month and each person’s totals.', 'महीना: पूरा महीना और हर व्यक्ति का हिसाब देखें।');
  String get tipStatus => _t(
    'Tap a status to change it. Nothing changes until you press Save.',
    'बदलने के लिए स्थिति दबाएँ। सेव दबाने तक कुछ नहीं बदलेगा।',
  );
  String get tipMint => _t(
    'Ask Mint: hold to speak or tap to type, in Hindi or English.',
    'Mint से पूछें: बोलने के लिए दबाकर रखें या लिखें — हिंदी या अंग्रेज़ी में।',
  );
  String tipCount(int i, int n) => _t('$i of $n', '$n में से $i');
  String get gotIt => _t('Got it', 'समझ गया');

  // ------------------------------------------- Team, More, rules, salary steps
  String get teamAccess => _t('Team & access', 'टीम और अनुमति');
  String get teamAccessHint => _t('Partners, managers and your CA', 'पार्टनर, मैनेजर और आपके CA');
  String get teamWho => _t('Who can open your business', 'आपका बिज़नेस कौन खोल सकता है');
  String get partnersTitle => _t('Partners (co-owners)', 'पार्टनर (सह-मालिक)');
  String get partnersCan =>
      _t('Run the business with you. See everything.', 'आपके साथ बिज़नेस चलाते हैं। सब देख सकते हैं।');
  String get youLabel => _t('You', 'आप');
  String get mainOwnerLabel => _t('main owner', 'मुख्य मालिक');
  String get partnerLabel => _t('partner', 'पार्टनर');
  String get addPartner => _t('Add partner', 'पार्टनर जोड़ें');
  String get managersTitle => _t('Managers', 'मैनेजर');
  String get managersCan => _t(
    'Mark attendance and approve leave. Can’t see salary or billing.',
    'हाज़िरी लगाते हैं और छुट्टी मंज़ूर करते हैं। सैलरी या बिलिंग नहीं देख सकते।',
  );
  String get makeManagerAction => _t('Make a staff member manager', 'किसी स्टाफ़ को मैनेजर बनाएँ');
  String get noManagers => _t('No managers yet', 'अभी कोई मैनेजर नहीं');
  String get caTitle => _t('Accountant (CA)', 'अकाउंटेंट (CA)');
  String get caCan => _t(
    'Sees salary and reports to file taxes. Can’t change attendance.',
    'टैक्स के लिए सैलरी और रिपोर्ट देखते हैं। हाज़िरी नहीं बदल सकते।',
  );
  String get addCa => _t('Add your CA', 'अपने CA जोड़ें');
  String get manage => _t('Manage', 'बदलें');
  String makeManagerQ(String name) => _t('Make $name a manager?', '$name को मैनेजर बनाएँ?');
  String get willBeAbleTo => _t('They will be able to', 'वे यह कर पाएँगे');
  String get canSeeFix => _t('See everyone’s attendance and fix it', 'सबकी हाज़िरी देखना और ठीक करना');
  String get canApproveLeave => _t('Approve leave and check-in requests', 'छुट्टी और चेक-इन मंज़ूर करना');
  String get canApprovePhones => _t('Approve new phones for staff', 'स्टाफ़ के नए फ़ोन मंज़ूर करना');
  String get wontSee => _t('They won’t see', 'वे यह नहीं देखेंगे');
  String get cantSalary => _t('Salary, advances or salary slips of others', 'दूसरों की सैलरी, एडवांस या सैलरी स्लिप');
  String get cantSettings => _t('Settings, plan & billing', 'सेटिंग, प्लान और बिलिंग');
  String get allBranchesLabel => _t('All branches', 'सभी ब्रांच');
  String get ownBranchLabel => _t('Only their branch', 'सिर्फ़ उनकी ब्रांच');
  String get managerMessageNote => _t(
    'They’ll get a message, and their app switches to the manager view by itself.',
    'उन्हें मैसेज जाएगा, और उनका ऐप अपने-आप मैनेजर वाला हो जाएगा।',
  );
  String get makeManager => _t('Make manager', 'मैनेजर बनाएँ');
  String madeManager(String name) => _t('$name is now a manager', '$name अब मैनेजर हैं');
  String get backToStaff => _t('Back to staff', 'वापस स्टाफ़');
  String backToStaffQ(String name) => _t('Make $name regular staff again?', '$name को फिर से स्टाफ़ बनाएँ?');
  String backToStaffDone(String name) => _t('$name is staff again', '$name फिर से स्टाफ़ हैं');
  String get pickStaff => _t('Pick a staff member', 'स्टाफ़ चुनें');
  String get managerBadge => _t('Manager', 'मैनेजर');
  String staffCountLine(int n, int m) =>
      _t('$n staff${m > 0 ? ' · $m manager${m == 1 ? '' : 's'}' : ''}', '$n स्टाफ़${m > 0 ? ' · $m मैनेजर' : ''}');
  String get invitedNotJoined => _t('Invited · hasn’t joined', 'बुलाया · अभी नहीं जुड़े');
  String get moreSearchHint => _t('Search: “holiday”, “CA”, “late”…', 'खोजें: “छुट्टी”, “CA”, “लेट”…');
  String get groupDaily => _t('Daily', 'रोज़ के काम');
  String get groupShopRules => _t('Shop rules', 'दुकान के नियम');
  String get groupBusiness => _t('Business', 'बिज़नेस');
  String get groupApp => _t('Help & app', 'मदद और ऐप');
  String leaveWaiting(int n) => _t('$n waiting', '$n बाकी');
  String get timingsTitle => _t('Timings & holidays', 'समय और छुट्टियाँ');
  String get timingsHint => _t('Shifts, weekly off, festivals', 'शिफ़्ट, साप्ताहिक छुट्टी, त्योहार');
  String get attendanceRulesTitle => _t('Attendance rules', 'हाज़िरी के नियम');
  String get attendanceRulesHint => _t('Late, half day, forgot to check out', 'लेट, आधा दिन, चेक-आउट भूलना');
  String get salaryRulesTitle => _t('Salary rules', 'सैलरी के नियम');
  String get salaryRulesHint => _t('How days are counted, paid leave', 'दिन कैसे गिने जाते हैं, पेड छुट्टी');
  String get safetyTitle => _t('Check-in safety', 'चेक-इन सुरक्षा');
  String get safetyHint => _t('Shop area, selfie, phone lock, face', 'दुकान का एरिया, सेल्फ़ी, फ़ोन लॉक, चेहरा');
  String get businessDetailsTitle => _t('Business details & branches', 'बिज़नेस की जानकारी और ब्रांच');
  String get businessDetailsHint =>
      _t('Name, branches, PF/ESI, close business', 'नाम, ब्रांच, PF/ESI, बिज़नेस बंद करें');
  String get planPayment => _t('Plan & payment', 'प्लान और पेमेंट');
  String trialDaysLeftShort(int d) => _t('trial $d days left', 'ट्रायल के $d दिन बाकी');
  String get historyOfChanges => _t('History of changes', 'बदलावों का इतिहास');
  String get helpVideos => _t('Help & videos', 'मदद और वीडियो');
  String get nothingFound =>
      _t('Nothing found. Try another word, or Ask Mint.', 'कुछ नहीं मिला। कोई और शब्द आज़माएँ, या Mint से पूछें।');
  String lateAfterLabel(int n) => _t('Late after $n min', '$n मिनट बाद लेट');
  String lateExample(String start, String late) =>
      _t('Shift starts $start → $late counts as Late.', 'शिफ़्ट $start पर शुरू → $late पर आना लेट गिना जाएगा।');
  String halfDayIfLabel(String h) => _t('Half day if they work less than $h hours', '$h घंटे से कम काम पर आधा दिन');
  String halfDayExample(String inAt, String outAt) =>
      _t('In at $inAt, out at $outAt → Half day.', '$inAt पर आए, $outAt पर गए → आधा दिन।');
  String get forgotCheckout => _t('If staff forget to check out', 'अगर स्टाफ़ चेक-आउट भूल जाए');
  String get optFullDay => _t('Full day', 'पूरा दिन');
  String get optAskMe => _t('Ask me', 'मुझसे पूछें');
  String get forgotHint => _t(
    'Most shops choose Half day, so people remember to check out.',
    'ज़्यादातर दुकानें आधा दिन चुनती हैं, ताकि लोग चेक-आउट याद रखें।',
  );
  String get morningSummary => _t('Morning summary', 'सुबह की रिपोर्ट');
  String get morningSummaryHint => _t('WhatsApp/notification with who came in', 'कौन आया — WhatsApp/नोटिफ़िकेशन पर');
  String get appliesFromToday =>
      _t('Changes apply from today. Past days stay as they are.', 'बदलाव आज से लागू होंगे। पुराने दिन वैसे ही रहेंगे।');
  String divisorExample(String perDay, String divisor) =>
      _t('Example: ₹12,000 a month ÷ $divisor = $perDay a day.', 'उदाहरण: ₹12,000 महीना ÷ $divisor = $perDay रोज़।');
  String get weekOffsPaidHint =>
      _t('Weekly offs count as paid days (most shops).', 'साप्ताहिक छुट्टी का पैसा मिलता है (ज़्यादातर दुकानें)।');
  String get holidaysPaidHint =>
      _t('Festival holidays you add are paid.', 'आपके जोड़े त्योहारों की छुट्टी का पैसा मिलता है।');
  String get sickLeavePaidHint =>
      _t('Approved sick leave is paid, like paid leave.', 'मंज़ूर बीमारी की छुट्टी का पैसा मिलता है।');
  String get roundToRupeeHint => _t('₹12,387.40 becomes ₹12,387.', '₹12,387.40 → ₹12,387।');
  String get safetyIntro => _t(
    'Stop people marking attendance for someone else. Pick how strict you want it.',
    'कोई किसी और की हाज़िरी न लगा पाए। जितनी सख़्ती चाहिए, चुनें।',
  );
  String get mustBeAtShop => _t('Must be at the shop', 'दुकान पर होना ज़रूरी');
  String mustBeAtShopHint(int m) => _t('Within $m m of the shop · change area', 'दुकान से $m मी के अंदर · एरिया बदलें');
  String get awayAskMe => _t('If away: ask me to approve', 'दूर हों तो: मुझसे मंज़ूरी लें');
  String get awayBlock => _t('If away: don’t allow', 'दूर हों तो: न होने दें');
  String get selfieTitle => _t('Selfie at check-in', 'चेक-इन पर सेल्फ़ी');
  String get selfieHint => _t('You can see the photo later', 'फ़ोटो आप बाद में देख सकते हैं');
  String get phoneLockTitle => _t('Phone lock', 'फ़ोन लॉक');
  String get phoneLockHint => _t(
    'Staff unlock their own phone (fingerprint/PIN) before checking in',
    'चेक-इन से पहले स्टाफ़ अपना फ़ोन खोलें (फ़िंगरप्रिंट/PIN)',
  );
  String get phoneLockMust => _t('Must unlock (can’t check in without it)', 'खोलना ज़रूरी (इसके बिना चेक-इन नहीं)');
  String get faceTitle => _t('Face check', 'चेहरे की जाँच');
  String get faceHint => _t(
    'We compare the selfie with their photo. Unclear ones wait for you.',
    'सेल्फ़ी को उनकी फ़ोटो से मिलाते हैं। साफ़ न हो तो आपके पास आता है।',
  );
  String get safetyRecommend => _t(
    'Recommended for most shops: first three on, face check if staff often cover for each other.',
    'ज़्यादातर दुकानों के लिए: पहले तीन चालू रखें; अगर स्टाफ़ एक-दूसरे की हाज़िरी लगाते हैं तो चेहरे की जाँच भी।',
  );
  String get whoMarksTitle => _t('Who marks attendance', 'हाज़िरी कौन लगाएगा');
  String get marksSelf => _t('Staff check in on their phone', 'स्टाफ़ अपने फ़ोन से चेक-इन करें');
  String get marksOwner => _t('I or my manager mark it', 'मैं या मेरा मैनेजर लगाएँ');
  String get whoMarksHint =>
      _t('You can change this for one person on their profile.', 'किसी एक के लिए उनकी प्रोफ़ाइल में बदल सकते हैं।');
  String get presentByDefaultTitle => _t('Present by default', 'अपने-आप हाज़िर');
  String get presentByDefaultHint => _t(
    'Staff you mark count as present at night, unless you mark them absent, half day or on leave.',
    'जिनकी हाज़िरी आप लगाते हैं, वे रात को हाज़िर गिने जाएँगे, जब तक आप ग़ैरहाज़िर, आधा दिन या छुट्टी न लगाएँ।',
  );
  String get marksSelfShort => _t('Checks in on phone', 'फ़ोन से चेक-इन');
  String get marksOwnerShort => _t('You mark it', 'आप लगाते हैं');
  String marksSameAsBusiness(String current) => _t('Same as business ($current)', 'बिज़नेस जैसा ($current)');
  String get markedByOwnerBody => _t(
    'Your attendance is marked by your owner or manager. No need to check in. You can see your attendance, leave and salary here.',
    'आपकी हाज़िरी मालिक या मैनेजर लगाते हैं। चेक-इन की ज़रूरत नहीं। हाज़िरी, छुट्टी और सैलरी यहाँ देख सकते हैं।',
  );
  String todayIs(String status) => _t('Today: $status', 'आज: $status');
  String get rowYouMark => _t('You mark · tap to mark', 'आप लगाते हैं · लगाने के लिए टैप करें');
  String rowJoinsOn(String date) =>
      _t('Joining date $date · tap if they worked', 'जॉइनिंग $date · काम किया हो तो टैप करें');
  String joiningMoves(String joining, String day) => _t(
    'Their joining date is $joining. Marking this day moves it to $day.',
    'इनकी जॉइनिंग $joining है। यह दिन लगाने पर जॉइनिंग $day हो जाएगी।',
  );
  String chipToMarkN(int n) => _t('$n to mark', '$n लगानी बाकी');
  String get rowAutoPresent => _t('Counted present automatically', 'अपने-आप हाज़िर लगी');
  String get rowPresentByDefault => _t('Present unless you change it', 'हाज़िर लगेगा, जब तक आप न बदलें');
  String get growthPlan => _t('Growth', 'Growth');
  String get rulesSaved => _t('Saved. Applies from today.', 'सेव हुआ। आज से लागू।');
  String get otherSettings => _t('Messages & former staff', 'मैसेज और पुराने स्टाफ़');
  String get step1Check => _t('Step 1 · Check attendance', 'कदम 1 · हाज़िरी जाँचें');
  String get step2Approve => _t('Step 2 · Approve & send salary slips', 'कदम 2 · मंज़ूर करें और सैलरी स्लिप भेजें');
  String get step3Pay =>
      _t('Step 3 · Pay staff, then slide “I’ve paid”', 'कदम 3 · स्टाफ़ को पैसे दें, फिर “दे दिया” स्लाइड करें');
  String get step1Done => _t('Attendance looks right', 'हाज़िरी ठीक है');
  String step1Todo(int n) => _t('$n to check below', 'नीचे $n जाँचें');
  String get step2Hint => _t(
    'Makes each person’s salary slip and sends it on WhatsApp/app.',
    'हर व्यक्ति की सैलरी स्लिप बनाकर WhatsApp/ऐप पर भेजता है।',
  );
  String get step3Hint =>
      _t('StaffMint only records it — it doesn’t send money.', 'StaffMint सिर्फ़ लिखकर रखता है — पैसे नहीं भेजता।');
  String get editSalaryHint => _t(
    'Need to change something after approving? Edit salary (we keep the old version).',
    'मंज़ूरी के बाद कुछ बदलना है? सैलरी बदलें (पुराना वर्ज़न रखा जाता है)।',
  );
  String advancePreview(String name, String month, String after, String before) => _t(
    '$name’s $month salary will be about $after instead of $before.',
    '$name की $month की सैलरी $before की जगह लगभग $after होगी।',
  );
  String advanceCutPreview(String name, String cut) =>
      _t('$cut will be cut from $name’s next salary.', '$name की अगली सैलरी से $cut कटेगा।');
  String get giveAdvance => _t('Give an advance (udhaar)', 'एडवांस (उधार) दें');
  String giveAmount(String amt) => _t('Give $amt', '$amt दें');
  String get showTipsAgain => _t('Show the screen tips again', 'स्क्रीन के सुझाव फिर दिखाएँ');
  String get tipsWillShow => _t('Tips will show on Home again', 'होम पर सुझाव फिर दिखेंगे');
  String get chatWhatsApp => _t('Chat with us on WhatsApp', 'WhatsApp पर हमसे बात करें');
  String get helpSearch => _t('What do you want to do?', 'आप क्या करना चाहते हैं?');
  String get helpGettingStarted => _t('Getting started', 'शुरुआत');
  String get helpEveryDay => _t('Every day', 'रोज़ के काम');
  String get helpSalary => _t('Salary', 'सैलरी');
  String get helpTeam => _t('Team & settings', 'टीम और सेटिंग');

  // ---------------------------------------------- Staff app (redesign)
  String namaste(String name) => _t('Namaste, $name', 'नमस्ते, $name');
  String yourShift(String a, String b) => _t('Your shift: $a – $b', 'आपकी शिफ़्ट: $a – $b');
  String shiftStartsAt(String t) => _t('Starts at $t', '$t पर शुरू होगी');
  String startedAgo(int minutes) => minutes < 60
      ? _t(minutes <= 1 ? 'Started a minute ago' : 'Started $minutes minutes ago', '$minutes मिनट पहले शुरू हुई')
      : _t(
          'Started ${minutes ~/ 60} h ${minutes % 60} min ago',
          '${minutes ~/ 60} घंटे ${minutes % 60} मिनट पहले शुरू हुई',
        );
  String inAtLate(String t, int late) => late > 0
      ? _t('In at $t · $late min late', '$t पर आए · $late मिनट लेट')
      : _t('In at $t · on time', '$t पर आए · समय पर');
  String get atShopTitle => _t('You’re at the shop', 'आप दुकान पर हैं');
  String get locationWhy =>
      _t('We check this so attendance is fair for everyone.', 'हम यह इसलिए देखते हैं ताकि सबकी हाज़िरी सही रहे।');
  String awayTitle(num m) => _t('You’re ${m.round()} m from the shop', 'आप दुकान से ${m.round()} मी दूर हैं');
  String get awayBody =>
      _t('Check in works when you’re inside the shop area.', 'दुकान के एरिया के अंदर आने पर चेक-इन होगा।');
  String get awayBodyAsk => _t(
    'You can still check in — your owner will be asked to OK it.',
    'फिर भी चेक-इन कर सकते हैं — मालिक से मंज़ूरी ली जाएगी।',
  );
  String get findingYou => _t('Finding where you are…', 'आपकी जगह देखी जा रही है…');
  String get locationOffTitle => _t('Location is off', 'लोकेशन बंद है');
  String get locationOffBody => _t('Turn on location to check in.', 'चेक-इन के लिए लोकेशन चालू करें।');
  String get tryAgain => _t('Try again', 'फिर कोशिश करें');
  String get locationProblem => _t('Location problem?', 'लोकेशन में दिक्कत?');
  String get locationProblemBody => _t(
    '1. Turn on Location in your phone settings.\n2. Step outside or near a window for a better signal.\n3. Tap Try again.\nStill not working? Tell your owner — they can mark you present.',
    '1. फ़ोन की सेटिंग में लोकेशन चालू करें।\n2. बाहर या खिड़की के पास जाएँ ताकि सिग्नल मिले।\n3. फिर कोशिश करें दबाएँ।\nफिर भी नहीं हुआ? मालिक को बताएँ — वे आपको हाज़िर लगा सकते हैं।',
  );
  String get checkInHintSelfie => _t('Takes a selfie and marks you present', 'सेल्फ़ी लेकर हाज़िरी लगती है');
  String get checkInHint => _t('Marks you present', 'हाज़िरी लगती है');
  String get workingOutside =>
      _t('Working outside today? (delivery, bank, site)', 'आज बाहर काम है? (डिलीवरी, बैंक, साइट)');
  String get askOwnerAllow => _t('Ask owner', 'मालिक से पूछें');
  String get workingOutsideBody => _t(
    'Call or message your owner. They can mark you present for today, or make the shop area bigger.',
    'मालिक को कॉल या मैसेज करें। वे आज के लिए आपकी हाज़िरी लगा सकते हैं, या दुकान का एरिया बढ़ा सकते हैं।',
  );
  String monthSoFar(String month) => _t('$month so far', '$month अब तक');
  String get seeAll => _t('See all', 'सब देखें');
  String daysPresentN(num n) => _t('${_num(n)} days present', '${_num(n)} दिन हाज़िर');
  String earnedTillToday(String amt) => _t('Earned till today: $amt', 'आज तक की कमाई: $amt');
  String dayInOut(String inAt, String? outAt) => outAt == null
      ? _t('In $inAt · Out — (still at work)', 'आए $inAt · गए — (अभी काम पर)')
      : _t('In $inAt · Out $outAt', 'आए $inAt · गए $outAt');
  String get noCheckInThatDay => _t('No check-in that day.', 'उस दिन चेक-इन नहीं हुआ।');
  String get iWasThere => _t('I was there — ask owner to fix', 'मैं काम पर था — मालिक से ठीक करवाएँ');
  String get fixNoteHint => _t('What happened? (optional)', 'क्या हुआ? (ज़रूरी नहीं)');
  String get askSent => _t('Sent to your owner', 'मालिक को भेज दिया');
  String get askAlreadySent => _t('Already sent for this day', 'इस दिन के लिए पहले ही भेजा जा चुका है');
  String get send => _t('Send', 'भेजें');
  String paidLeavesLeft(num n) => _t('You have ${_num(n)} paid leaves left', 'आपकी ${_num(n)} पेड छुट्टियाँ बाकी हैं');
  String leaveDaysCount(num n) => _t(n == 1 ? '1 day' : '${_num(n)} days', '${_num(n)} दिन');
  String leaveAfterPaid(num left) => _t(
    'After this you’ll have ${_num(left)} paid leaves left. Your salary won’t be cut.',
    'इसके बाद आपकी ${_num(left)} पेड छुट्टियाँ बचेंगी। सैलरी नहीं कटेगी।',
  );
  String leaveAfterSick(num left) => _t(
    'After this you’ll have ${_num(left)} sick leaves left. Your salary won’t be cut.',
    'इसके बाद आपकी ${_num(left)} बीमारी की छुट्टियाँ बचेंगी। सैलरी नहीं कटेगी।',
  );
  String leaveNotEnough(num have) => _t(
    'You have only ${_num(have)} left. Days beyond that may be unpaid.',
    'आपकी सिर्फ़ ${_num(have)} बाकी हैं। उससे ज़्यादा दिन बिना पैसे के हो सकते हैं।',
  );
  String get leaveUnpaidEffect =>
      _t('Unpaid leave: salary is cut for these days.', 'बिना पैसे की छुट्टी: इन दिनों की सैलरी कटेगी।');
  String get leaveWeekOffNote => _t(
    'Weekly offs and holidays inside these dates are not counted.',
    'इन तारीख़ों में आने वाली साप्ताहिक छुट्टी और त्योहार नहीं गिने जाते।',
  );
  String get sendToOwner => _t('Send to owner', 'मालिक को भेजें');
  String get earnedSoFarTitle => _t('Earned so far', 'अब तक की कमाई');
  String get paidOnSalaryDay =>
      _t('Paid on salary day, after the month ends', 'महीना ख़त्म होने के बाद सैलरी डे पर मिलेगी');
  String monthTillToday(String month) => _t('$month, till today', '$month, आज तक');

  // ------------------------------------------------ Round 2 (fixes)
  String shiftStartsAt2(String t) => _t('Shift starts at $t', 'शिफ़्ट $t पर शुरू होगी');
  String shiftStartsBody(int n) => _t(
    '$n staff · we’ll show who came in after the shift starts.',
    '$n स्टाफ़ · शिफ़्ट शुरू होने के बाद दिखेगा कौन आया।',
  );
  String rowShift(String t) => _t('Shift $t', 'शिफ़्ट $t');
  String get relToday => _t('Today', 'आज');
  String get relYesterday => _t('Yesterday', 'कल');
  String daysAgo(int n) => _t('$n days ago', '$n दिन पहले');
  String todoCount(int n) => _t('To do · $n', 'करने के काम · $n');
  String todoNeedOk(int n) => _t('$n need your OK', '$n मंज़ूरी बाकी');
  String todoNotJoined(int n) =>
      _t(n == 1 ? '1 staff hasn’t joined' : '$n staff haven’t joined', '$n स्टाफ़ नहीं जुड़े');
  String get todoAllDone => _t('Nothing waiting for you', 'आपके लिए कुछ बाकी नहीं');
  String todoInviteLine(int n) => _t(
    n == 1 ? '1 staff hasn’t installed the app' : '$n staff haven’t installed the app',
    '$n स्टाफ़ ने ऐप इंस्टॉल नहीं किया',
  );
  String get remindAll => _t('Remind all', 'सबको याद दिलाएँ');
  String get inviteSheetTitle => _t('App invites', 'ऐप का आमंत्रण');
  String get inviteEveryoneJoined => _t('Everyone has joined the app.', 'सब ऐप पर आ गए हैं।');
  String get inviteNotConnected => _t(
    'StaffMint’s WhatsApp isn’t set up for your business yet, so the invite can’t reach them. Send it from your own WhatsApp:',
    'आपके बिज़नेस के लिए StaffMint का WhatsApp अभी चालू नहीं है, इसलिए आमंत्रण उन तक नहीं पहुँचेगा। अपने WhatsApp से भेजें:',
  );
  String get inviteSomeFailed => _t(
    'Some invites couldn’t be sent. Send those from your own WhatsApp:',
    'कुछ आमंत्रण नहीं जा पाए। उन्हें अपने WhatsApp से भेजें:',
  );
  String get inviteOwnWhatsApp =>
      _t('Didn’t get it? Send it from your own WhatsApp too.', 'नहीं मिला? अपने WhatsApp से भी भेज सकते हैं।');
  String inviteStatus(String status) => switch (status) {
    'recent' => _t('Sent a few minutes ago', 'कुछ मिनट पहले भेजा'),
    'failed' => _t('Couldn’t send', 'नहीं भेज पाए'),
    _ => _t('Sent on WhatsApp', 'WhatsApp पर भेजा'),
  };
  String get whatsappShort => _t('WhatsApp', 'WhatsApp');
  String get rowNotOnApp => _t('not on the app yet', 'अभी ऐप पर नहीं');
  String get swipeTip => _t('Tip: you can also swipe a card.', 'सुझाव: कार्ड को खिसका भी सकते हैं।');
  String noLeavesLeft(String type, num days) => _t(
    'No $type leaves left. If you approve, these ${_num(days)} days are unpaid leave (salary is cut for ${_num(days)} days).',
    '$type छुट्टी बाकी नहीं है। मंज़ूर करने पर ये ${_num(days)} दिन बिना पैसे की छुट्टी होंगे (${_num(days)} दिन की सैलरी कटेगी)।',
  );
  String fewLeavesLeft(String type, num left, num days) => _t(
    'Only ${_num(left)} $type leaves left for ${_num(days)} days. If you approve as unpaid, salary is cut for ${_num(days)} days.',
    'सिर्फ़ ${_num(left)} $type छुट्टी बाकी है, माँगे ${_num(days)} दिन। बिना पैसे मंज़ूर करने पर ${_num(days)} दिन की सैलरी कटेगी।',
  );
  String leavesAfter(String type, num left, num after) => _t(
    'Has ${_num(left)} $type leaves. After this: ${_num(after)} left.',
    '${_num(left)} $type छुट्टी बाकी। इसके बाद: ${_num(after)} बचेंगी।',
  );
  String get approveAsUnpaid => _t('Approve as unpaid', 'बिना पैसे मंज़ूर करें');
  String get giveAsPaid => _t('Give as paid leave anyway', 'फिर भी पेड छुट्टी दें');
  String get seeMap => _t('see map', 'नक्शा देखें');
  String todayAt(String t) => _t('Today $t', 'आज $t');
  String selfieDifferent(String name) => _t('$name’s selfie looks different', '$name की सेल्फ़ी अलग दिख रही है');
  String noPhoneLock(String name) =>
      _t('$name checked in without unlocking the phone', '$name ने फ़ोन खोले बिना चेक-इन किया');
  String get itsThem => _t('It’s them', 'यही हैं');
  String get countAsPresent => _t('Count as present', 'हाज़िर मानें');
  String get mintIntro => _t(
    'Namaste! I can do things for you, or show you where to find them. Try:',
    'नमस्ते! मैं आपके काम कर सकता हूँ, या बता सकता हूँ कि कहाँ मिलेगा। ऐसे बोलें:',
  );

  /// (shown, sent) pairs: shown in the app's language, sent in Hinglish, which Mint understands best.
  List<(String, String)> get mintExamples => [
    (_t('Raju aaj absent hai', 'राजू आज नहीं आया'), 'Raju aaj absent hai'),
    (_t('Pooja ko ₹500 advance do', 'पूजा को ₹500 एडवांस दो'), 'Pooja ko ₹500 advance do'),
    (_t('Aaj kaun late aaya?', 'आज कौन लेट आया?'), 'Aaj kaun late aaya?'),
    (_t('Mera CA kaise add karein?', 'मेरा CA कैसे जोड़ें?'), 'Mera CA kaise add karein?'),
  ];
  String get openScreen => _t('Open', 'खोलें');
  String get helpTeamAnswer => _t(
    'Staff tab → Team & access → Add your CA. Your CA can see salary and reports, but can’t change attendance.',
    'स्टाफ़ टैब → टीम और एक्सेस → अपना CA जोड़ें। CA सैलरी और रिपोर्ट देख सकता है, पर हाज़िरी नहीं बदल सकता।',
  );
  String get helpTimings => _t(
    'More → Timings & holidays. Set shift times, weekly off and festival holidays there.',
    'और → समय और छुट्टियाँ। वहाँ शिफ़्ट का समय, साप्ताहिक छुट्टी और त्योहार की छुट्टी सेट करें।',
  );
  String get helpLateRules => _t(
    'More → Attendance rules. Set how many minutes late is OK, and when late becomes a half day.',
    'और → हाज़िरी के नियम। कितने मिनट की देरी ठीक है, और कब आधा दिन माना जाए, यहाँ सेट करें।',
  );
  String get helpStatutory => _t(
    'More → Business details → PF & ESI. Turn them on and add your numbers.',
    'और → बिज़नेस की जानकारी → PF और ESI। इन्हें चालू करें और अपने नंबर डालें।',
  );
  String get helpAdvance => _t(
    'Just tell me, like “Pooja ko ₹500 advance do”. Or open Salary and tap the staff member.',
    'बस मुझे बोलिए, जैसे “पूजा को ₹500 एडवांस दो”। या सैलरी खोलकर स्टाफ़ पर दबाएँ।',
  );
  String get helpAddStaff => _t(
    'Staff tab → Add. Type the name, phone and salary. They get a WhatsApp invite to join.',
    'स्टाफ़ टैब → जोड़ें। नाम, फ़ोन और सैलरी डालें। उन्हें जुड़ने के लिए WhatsApp पर बुलावा जाएगा।',
  );
  String get helpReports => _t(
    'More → Reports. Download attendance and salary as Excel or PDF.',
    'और → रिपोर्ट। हाज़िरी और सैलरी Excel या PDF में डाउनलोड करें।',
  );
  String get helpPlan => _t(
    'More → Plan & payment. See your plan and pay there.',
    'और → प्लान और पेमेंट। वहाँ अपना प्लान देखें और पेमेंट करें।',
  );
  String get salaryTitle => _t('Salary', 'सैलरी');
  String monthDone(String month) => _t('$month is done', '$month पूरा हुआ');
  String slipsSentLine(int n) => _t(
    '$n salary slips sent. Staff can see them in their app.',
    '$n सैलरी स्लिप भेजी गईं। स्टाफ़ अपने ऐप में देख सकते हैं।',
  );
  String get needChange => _t('Need to change something?', 'कुछ बदलना है?');
  String get needChangeBody => _t('We make a new slip and keep the old one.', 'नई स्लिप बनेगी, पुरानी रखी रहेगी।');
  String get countAsAbsent => _t('Count them as absent?', 'इन्हें ग़ैरहाज़िर मानें?');
  String get yesAbsent => _t('Yes, absent', 'हाँ, ग़ैरहाज़िर');
  String get fixDays => _t('Fix days', 'दिन ठीक करें');
  String get yesRight => _t('Yes, that’s right', 'हाँ, सही है');
  String get pay => _t('Pay', 'पैसे');
  String get work => _t('Work', 'काम');
  String get calendarLink => _t('Calendar', 'कैलेंडर');
  String get weeklyOffLabel => _t('Weekly off', 'साप्ताहिक छुट्टी');
  String get joinedLabel => _t('Joined', 'जुड़े');
  String get advanceToRecover => _t('Advance to recover', 'वापस लेना है (एडवांस)');
  String get giveAdvanceShort => _t('Give advance', 'एडवांस दें');
  String get bonusCutShort => _t('Bonus / cut', 'बोनस / कटौती');

  // ------------------------------------------------ Round 2 (simpler)
  String daysOff(String days) => _t('$days off', '$days छुट्टी');
  String workingN(int n) => _t('Working ($n)', 'काम पर ($n)');
  String leftN(int n) => _t('Left ($n)', 'छोड़ चुके ($n)');
  String get noneLeft => _t('Nobody has left.', 'किसी ने काम नहीं छोड़ा।');
  String staffN(int n) => _t(n == 1 ? '1 staff' : '$n staff', '$n स्टाफ़');
  String get nextHolidays => _t('Next holidays', 'आने वाली छुट्टियाँ');
  String get noHolidaysYet => _t('No holidays added yet.', 'अभी कोई छुट्टी नहीं जोड़ी।');
  String get savesAtOnce => _t('Saves as soon as you change it.', 'बदलते ही सेव हो जाता है।');
  String get alertsOnWhatsapp => _t('Alerts on WhatsApp too', 'अलर्ट WhatsApp पर भी');
  String get alertsOnWhatsappHint => _t(
    'Leave requests and check-ins that need you also come to your WhatsApp.',
    'छुट्टी की अर्ज़ी और जिन चेक-इन पर आपकी मंज़ूरी चाहिए, वे WhatsApp पर भी आएँगे।',
  );
  String get oldStaffSlips => _t('Old staff can see old salary slips', 'पुराने स्टाफ़ पुरानी सैलरी स्लिप देख सकें');
  String get oldStaffSlipsHint =>
      _t('For 12 months after they leave (for loans, ITR).', 'काम छोड़ने के 12 महीने तक (लोन, ITR के लिए)।');
  String get shopAreaHint => _t('Where staff must be to check in', 'चेक-इन के लिए स्टाफ़ को कहाँ होना चाहिए');
  String get howWorkedOut => _t('How it’s worked out', 'हिसाब कैसे बना');
  String wkPresent(num n) => _t(n == 1 ? '1 day present' : '${_num(n)} days present', '${_num(n)} दिन हाज़िर');
  String wkHalfDays(num n) => n == 1
      ? _t('1 half day = ½ day', '1 आधा दिन = ½ दिन')
      : _t(
          '${_num(n)} half days = ${n / 2 == 1 ? '1 day' : '${_num(n / 2)} days'}',
          '${_num(n)} आधे दिन = ${_num(n / 2)} दिन',
        );
  String wkPaidLeave(num n) => _t('${_num(n)} paid leave', '${_num(n)} पेड छुट्टी');
  String wkWeekOffs(num n) => _t('${_num(n)} weekly offs', '${_num(n)} साप्ताहिक छुट्टी');
  String wkHolidays(num n) => _t('${_num(n)} holidays', '${_num(n)} त्योहार की छुट्टी');
  String wkOffsPaid(num n) => _t('${_num(n)} offs & holidays', '${_num(n)} छुट्टी और त्योहार');
  String get paidByRule => _t('paid by shop rule', 'दुकान के नियम से पैसे');
  String wkNotPaid(num absent, num unmarked, num unpaid) => [
    if (absent > 0) _t('${_num(absent)} absent', '${_num(absent)} ग़ैरहाज़िर'),
    if (unpaid > 0) _t('${_num(unpaid)} unpaid leave', '${_num(unpaid)} बिना पैसे की छुट्टी'),
    if (unmarked > 0) _t('${_num(unmarked)} not marked', '${_num(unmarked)} दिन हाज़िरी नहीं'),
  ].join(' · ');
  String get notPaidWord => _t('not paid', 'पैसे नहीं');
  String oneDayRate(String rate, String div, String day) =>
      _t('1 day = $rate ÷ $div = $day', '1 दिन = $rate ÷ $div = $day');
  String slipPaidLine(String date, String method) => _t('Paid $date · $method', '$date को मिली · $method');
  String get nextBank => _t('Add your bank or UPI', 'अपना बैंक या UPI जोड़ें');
  String get nextBankWhy => _t('So your salary can be sent straight to you.', 'ताकि सैलरी सीधे आपको भेजी जा सके।');
  String get nextEmergency => _t('Add an emergency contact', 'आपात संपर्क जोड़ें');
  String get nextEmergencyWhy =>
      _t('So the shop can call someone if you need help.', 'ताकि ज़रूरत पड़ने पर दुकान किसी को कॉल कर सके।');
  String get nextPhoto => _t('Add your photo', 'अपनी फ़ोटो लगाएँ');
  String get nextPhotoWhy => _t('So your team can recognise you.', 'ताकि टीम आपको पहचान सके।');
  String get nextName => _t('Add your full name', 'अपना पूरा नाम लिखें');
  String get nextNameWhy => _t('It goes on salary slips.', 'यह सैलरी स्लिप पर आता है।');
  String get nextEmail => _t('Add your email', 'अपना ईमेल जोड़ें');
  String get nextEmailWhy =>
      _t('For salary slips and reports by email.', 'सैलरी स्लिप और रिपोर्ट ईमेल पर पाने के लिए।');
  String get languageNote =>
      _t('Language: use हि / En at the top of any screen.', 'भाषा: किसी भी स्क्रीन पर ऊपर हि / En दबाएँ।');
  String get chooseAWay => _t('Choose a way', 'कोई एक तरीका चुनें');
  String get wayContactsHint => _t('Fastest. Choose many at once.', 'सबसे जल्दी। एक साथ कई चुनें।');
  String get wayType => _t('Type name & phone', 'नाम और फ़ोन लिखें');
  String get wayTypeHint => _t('One person at a time.', 'एक बार में एक व्यक्ति।');
  String get wayTypeButton => _t('Type', 'लिखें');
  String get wayExcel => _t('From Excel / SalaryBox', 'Excel / SalaryBox से');
  String get wayExcelHint =>
      _t('Easier on a computer: app.staffmint.app → Import', 'कंप्यूटर पर आसान: app.staffmint.app → Import');
  String get sendLink => _t('Send link', 'लिंक भेजें');
  String get importLinkText => _t(
    'Add staff to StaffMint from Excel: open https://app.staffmint.app/import on a computer.',
    'StaffMint में Excel से स्टाफ़ जोड़ें: कंप्यूटर पर https://app.staffmint.app/import खोलें।',
  );
  String get whatHappensNext => _t('What happens next', 'आगे क्या होगा');
  String get next1 =>
      _t('Each person gets a WhatsApp invite with the app link.', 'हर व्यक्ति को WhatsApp पर ऐप का लिंक जाएगा।');
  String get next2 =>
      _t('They log in with their own number, no password.', 'वे अपने नंबर से लॉगिन करेंगे, कोई पासवर्ड नहीं।');
  String get next3 => _t('You see them on Home when they check in.', 'चेक-इन करते ही वे आपको होम पर दिखेंगे।');
  String get newStaff => _t('New staff', 'नया स्टाफ़');
  String get howSalaryPaid => _t('How is salary paid?', 'सैलरी कैसे मिलती है?');
  String get everyMonth => _t('Every month', 'हर महीने');
  String get everyDay => _t('Every day', 'हर दिन');
  String joiningLine(String date) => _t('Joining date: $date', 'जुड़ने की तारीख़: $date');
  String get changeLink => _t('change', 'बदलें');
  String get addAndInvite => _t('Add & send invite', 'जोड़ें और बुलावा भेजें');

  String contactsCount(int all, int canAdd) => all == canAdd
      ? _t('$all contacts', '$all कॉन्टैक्ट')
      : _t('$all contacts · $canAdd can be added', '$all कॉन्टैक्ट · $canAdd जोड़े जा सकते हैं');
  String get notAMobile => _t('Not a mobile number', 'मोबाइल नंबर नहीं है');
  String get cantAddContacts => _t('Can’t be added (no mobile number)', 'नहीं जोड़े जा सकते (मोबाइल नंबर नहीं)');
  String get contactsOnlySome => _t(
    'Your phone shared only some contacts with StaffMint.',
    'आपके फ़ोन ने StaffMint को सिर्फ़ कुछ कॉन्टैक्ट दिखाए हैं।',
  );
  String get allowAll => _t('Allow all', 'सभी दिखाएँ');
  String get openSettings => _t('Open settings', 'सेटिंग खोलें');

  // ------------------------------------------------------------- History
  String get historyHint =>
      _t('Every change in your business: who did it and when.', 'आपके बिज़नेस का हर बदलाव: किसने किया और कब।');
  String historyFilter(String c) => switch (c) {
    'attendance' => _t('Attendance', 'हाज़िरी'),
    'leave' => _t('Leave', 'छुट्टी'),
    'salary' => _t('Salary', 'सैलरी'),
    'staff' => _t('Staff', 'स्टाफ़'),
    'settings' => _t('Shop rules', 'दुकान के नियम'),
    'team' => _t('Team', 'टीम'),
    'billing' => _t('Plan', 'प्लान'),
    _ => _t('All', 'सब'),
  };
  String historyBy(String name) => _t('by $name', '$name ने');
  String historyVia(String channel) => switch (channel) {
    'assistant' => _t('via Mint', 'Mint से'),
    'whatsapp' => _t('via WhatsApp', 'WhatsApp से'),
    'web' => _t('on computer', 'कंप्यूटर से'),
    'import' => _t('from a file', 'फ़ाइल से'),
    'system' => _t('automatic', 'अपने आप'),
    _ => '',
  };
  String get historyAutomatic => _t('StaffMint', 'StaffMint');
  String get historyChanged => _t('A change was made', 'एक बदलाव किया गया');
  String get historyNothingHere => _t('Nothing here yet.', 'यहाँ अभी कुछ नहीं।');

  // ------------------------------------------------------------ Shop map
  String get shopLocationTitle => _t('Shop location', 'दुकान की लोकेशन');
  String get searchPlaceHint => _t('Search your shop, market or area', 'दुकान, बाज़ार या इलाक़ा खोजें');
  String get noPlacesFound =>
      _t('No places found. Try the market or area name.', 'कुछ नहीं मिला। बाज़ार या इलाक़े का नाम लिखकर देखें।');
  String get moveMapHint => _t('Move the map to put the pin on your shop', 'नक्शा खिसकाकर पिन अपनी दुकान पर रखें');
  String get findingAddress => _t('Finding address…', 'पता ढूँढ रहे हैं…');
  String get useThisLocation => _t('Use this location', 'यही लोकेशन रखें');
  String get mapView => _t('Map', 'नक्शा');
  String get satelliteView => _t('Satellite', 'सैटेलाइट');
  String youAreFromPin(int m) => _t('You are $m m from the pin', 'आप पिन से $m मीटर दूर हैं');
  String get youAreInside => _t('You are inside the circle', 'आप घेरे के अंदर हैं');
  String get mapLoadFailed => _t(
    'Map didn’t load. Check internet — you can still use your current location.',
    'नक्शा नहीं खुला। इंटरनेट देखें — अपनी अभी की लोकेशन फिर भी लगा सकते हैं।',
  );
  String get setShopLocation => _t('Set your shop location', 'दुकान की लोकेशन लगाएँ');
  String get setShopLocationHint =>
      _t('Staff can check in only near this spot.', 'स्टाफ़ सिर्फ़ इस जगह के पास ही चेक-इन कर पाएँगे।');
  String get findOnMap => _t('Find on map', 'नक्शे पर ढूँढें');
  String get changeOnMap => _t('Change on map', 'नक्शे पर बदलें');
  String get myLocation => _t('My location', 'मेरी लोकेशन');

  // ------------------------------------------------------- Employee home
  String shiftShort(String a, String b) => _t('Shift $a – $b', 'शिफ़्ट $a – $b');
  Bi get atShop => _b('At shop', 'दुकान पर');
  Bi get awayFromShop => _b('Away from shop', 'दुकान से दूर');
  Bi get locating => _b('Finding location…', 'लोकेशन ली जा रही है…');
  Bi get gpsOff => _b('GPS off · tap to retry', 'GPS बंद · फिर दबाएँ');
  Bi get gpsReady => _b('Location ready', 'लोकेशन तैयार');
  Bi get onTime => _b('On time', 'समय पर');
  Bi get runningLate => _b('Running late', 'देर हो रही है');
  Bi get lateToday => _b('Late', 'लेट');
  Bi get checkedInBi => _b('Checked in!', 'हाज़िरी लग गई!');
  Bi get checkedOutBi => _b('Checked out!', 'चेक-आउट हो गया!');
  Bi get savedOfflineBi => _b('Saved offline', 'ऑफ़लाइन सेव हुई');
  String get willSync => _t('Will sync when internet is back', 'इंटरनेट आने पर अपने आप सिंक होगी');
  String get selfieLabel => _t('Selfie', 'सेल्फ़ी');
  String get selfieSaved => _t('Saved', 'सेव हुई');
  String get notNeeded => _t('Not needed', 'ज़रूरी नहीं');
  String get locationLabel => _t('Location', 'लोकेशन');
  String get timeLabel => _t('Time', 'समय');
  Bi get doneBi => _b('Done', 'ठीक है');
  String monthDaysPresent(String month, num n) => _t('$month · $n days present', '$month · $n दिन हाज़िर');
  String earnedSoFar(String amount) => _t('$amount so far', '$amount अब तक');

  // ----------------------------------------------------------------- Mint
  String get mintSubtitle => _t('your assistant · online', 'आपका सहायक · ऑनलाइन');
  String get mintInputHint => _t('Type, or hold 🎙 to speak…', 'लिखें या 🎙 दबाकर बोलें…');
  String get confirmYes => _t('Yes, do it', 'हाँ, कर दो');
  String get confirmNo => _t('No', 'नहीं');
  String get voiceNote => _t('Voice note', 'आवाज़ संदेश');

  /// (label, query) pairs; queries stay in Hinglish, which Mint understands best.
  List<(String, String)> get mintSuggestionChips => [
    (_t('⏰ Who is late?', '⏰ कौन लेट?'), 'Aaj kaun late aaya?'),
    (_t('₹ Salary total?', '₹ सैलरी कितनी?'), 'Is month salary kitni banegi?'),
    (_t('🏖️ Leave', '🏖️ छुट्टी'), 'Chhutti lagani hai'),
    (_t('💸 Advance', '💸 एडवांस'), 'Advance dena hai'),
    (_t('❓ What can you do?', '❓ क्या कर सकते हो?'), 'Kya kya kar sakte ho?'),
  ];

  // ----------------------------------------------------------- Salary day
  Bi get salaryDayBi => _b('Pay salary', 'सैलरी दें');
  Bi get stepReview => _b('Review', 'जाँचें');
  Bi get stepSend => _b('Approve & send', 'भेजें');
  Bi get stepPaid => _b('Paid', 'दे दी');
  Bi get cashNeeded => _b('Total to pay this month', 'इस महीने कुल देना है');
  String earnedAmount(String a) => _t('$a earned', '$a कमाई');
  String advanceRecovered(String a) => _t('−$a advance', '−$a एडवांस');
  String get isThatRight => _t('Is that right?', 'क्या यह सही है?');
  String get looksRight => _t('Looks right', 'ठीक है');
  String get change => _t('Change', 'बदलें');
  Bi othersFine(int n) => _b('$n others look fine', 'बाकी $n स्टाफ़ में कोई दिक्कत नहीं');
  Bi allFine(int n) => _b('All $n staff look fine', 'सभी $n स्टाफ़ ठीक हैं');
  String get slideApproveSend => _t('Slide to approve & send salary slips', 'स्लाइड करें · मंज़ूर करें और भेजें');
  String get slideMarkPaid => _t('Slide after you’ve paid everyone', 'सबको पैसे देने के बाद स्लाइड करें');
  String get slideA11yHint => _t('Double-tap and hold to confirm', 'पक्का करने के लिए दबाए रखें');
  Bi get salaryApprovedBi => _b('Salary approved!', 'सैलरी मंज़ूर!');
  String payslipsSentTo(int n) => _t('Salary slips are going to $n staff', '$n स्टाफ़ को सैलरी स्लिप भेजी जा रही हैं');
  Bi get salaryPaidBi => _b('Marked as paid', 'सैलरी दी गई');
  String get paidBanner => _t('Salary for this month is paid', 'इस महीने की सैलरी दे दी गई');
  String get sendAgain => _t('Send salary slips again', 'सैलरी स्लिप फिर भेजें');
  String daysOf(num p, num d) => _t('$p of $d days', '$d में से $p दिन');
  String daysOnly(num p) => _t('$p days', '$p दिन');

  // -------------------------------------------------------------- Mark as paid
  String get paidQuestion => _t('Have you paid everyone?', 'क्या सबको सैलरी दे दी?');
  String get paidNoMoneyNote => _t(
    'StaffMint doesn\'t send money. This records that you paid, so salary slips show "Paid".',
    'StaffMint पैसे नहीं भेजता। यह सिर्फ़ दर्ज करता है कि आपने सैलरी दे दी, ताकि स्लिप पर "पैसे दे दिए" दिखे।',
  );
  String get howDidYouPay => _t('How did you pay?', 'कैसे दिया?');
  String get paidOnLabel => _t('Paid on', 'किस दिन दिया');
  String yesAllPaid(int n) => _t('Yes, all $n are paid', 'हाँ, सभी $n को दे दिया');
  String paymentMethodLabel(String m) {
    switch (m) {
      case 'upi':
        return 'UPI';
      case 'bank':
        return _t('Bank transfer', 'बैंक ट्रांसफ़र');
      case 'mixed':
        return _t('Mixed', 'मिला-जुला');
      default:
        return _t('Cash', 'नकद');
    }
  }

  String paidOnVia(String date, String method) => _t('Paid on $date · $method', '$date को दिया · $method');
  String get notPaidYet => _t('Not paid yet', 'अभी पैसे नहीं दिए');
  String get employerOnTop => _t('Paid by your employer on top of salary', 'सैलरी के अलावा मालिक द्वारा जमा');

  // -------------------------------------------------------------- PF / ESI / Professional Tax
  Bi get statutoryBi => _b('PF, ESI & Professional Tax', 'PF, ESI और प्रोफ़ेशनल टैक्स');
  String get statutoryHint =>
      _t('Only if your shop is registered for them', 'सिर्फ़ अगर आपकी दुकान इनमें रजिस्टर्ड है');
  String get statutoryIntro => _t(
    'Most small shops don\'t need these. PF is usually for 20+ staff, ESI for 10+ staff earning up to ₹21,000. Ask your CA if unsure. Changes apply from the next salary.',
    'ज़्यादातर छोटी दुकानों को इनकी ज़रूरत नहीं। PF आमतौर पर 20+ स्टाफ़ पर, ESI 10+ स्टाफ़ (₹21,000 तक सैलरी) पर लगता है। शक हो तो CA से पूछें। बदलाव अगली सैलरी से लागू होंगे।',
  );
  String get pfTitle => _t('Provident Fund (PF)', 'भविष्य निधि (PF)');
  String get pfExample => _t(
    '12% of Basic from staff, 12% from you. Basic is capped at ₹15,000, so at most ₹1,800 each.',
    'बेसिक का 12% स्टाफ़ से, 12% आपसे। बेसिक ₹15,000 तक गिना जाता है, यानी हर तरफ़ ज़्यादा से ज़्यादा ₹1,800।',
  );
  String get pfNumberLabel => _t('PF establishment code', 'PF कोड');
  String get basicPercentLabel => _t('Basic is what % of salary?', 'सैलरी का कितना % बेसिक है?');
  String get basicPercentHint =>
      _t('The rest shows as HRA & allowances. 50% is common.', 'बाकी HRA व भत्ते में दिखेगा। 50% आम है।');
  String get esiTitle => _t('ESI', 'ESI (स्टाफ़ का सरकारी बीमा)');
  String get esiExample => _t(
    'For staff earning up to ₹21,000: 0.75% from staff, 3.25% from you.',
    '₹21,000 तक सैलरी वाले स्टाफ़ के लिए: 0.75% स्टाफ़ से, 3.25% आपसे।',
  );
  String get esiNumberLabel => _t('ESI code', 'ESI कोड');
  String get ptTitle => _t('Professional Tax', 'प्रोफ़ेशनल टैक्स');
  String get ptExample => _t(
    'A small state tax (e.g. ₹200 a month in Maharashtra, none in Delhi).',
    'एक छोटा राज्य टैक्स (जैसे महाराष्ट्र में ₹200 महीना, दिल्ली में नहीं)।',
  );
  String get ptStateLabel => _t('State', 'राज्य');
  String get ptAmountLabel => _t('Amount per month (₹)', 'हर महीने (₹)');
  String get ptMinLabel => _t('Only if salary is at least (₹)', 'सिर्फ़ जब सैलरी कम से कम हो (₹)');

  // Staff details for slips
  Bi get slipDetailsBi => _b('Details on salary slip', 'सैलरी स्लिप पर विवरण');
  String get employeeCodeLabel => _t('Employee ID', 'स्टाफ़ ID');
  String get uanLabel => _t('PF UAN (12 digits)', 'PF UAN (12 अंक)');
  String get esicLabel => _t('ESIC number', 'ESIC नंबर');
  String get panLabel => _t('PAN', 'PAN');
  String get pfExemptLabel => _t('Not in PF', 'PF में नहीं');
  String get esiExemptLabel => _t('Not in ESI', 'ESI में नहीं');
  String get slipDetailsHint => _t(
    'Employee ID, PF UAN, ESIC, PAN. Optional — fill only what your shop uses.',
    'स्टाफ़ ID, PF UAN, ESIC, PAN. ज़रूरी नहीं — जो आपकी दुकान में चलता है वही भरें।',
  );

  // -------------------------------------------------------------- Salary slip
  Bi get payslipBi => _b('Salary slip', 'सैलरी स्लिप');
  Bi get netPayBi => _b('Net pay', 'हाथ में सैलरी');
  String get why => _t('Why?', 'क्यों?');
  String get sendOnWhatsApp => _t('Send on WhatsApp', 'WhatsApp पर भेजें');
  String get pdf => 'PDF';
  String get stampPaid => 'PAID';
  String get stampApproved => _t('APPROVED', 'मंज़ूर');
  String get pdfAfterApproval => _t('PDF is made after approval', 'PDF मंज़ूरी के बाद बनेगी');
  String waPayslipMessage(String name, String month, String net, String? url) => _t(
    'Namaste $name, your salary for $month: $net (in hand).${url == null ? '' : ' Salary slip: $url'}',
    'नमस्ते $name, $month की सैलरी: $net (हाथ में)।${url == null ? '' : ' सैलरी स्लिप: $url'}',
  );

  // ---------------------------------------------------------------- Setup
  String get findingLocation => _t('Finding your location…', 'आपकी लोकेशन ढूँढ रहे हैं…');
  String timingsPrefilled(String type) =>
      _t('Usual timings for a ${type.toLowerCase()}. Change if needed.', '$type का आम समय भरा है। ज़रूरत हो तो बदलें।');

  // ------------------------------------------------------------- Accounts
  String get chooseAccount => _t('Choose an account', 'खाता चुनें');
  String chooseAccountHint(String phone) => _t(
    '$phone is linked to more than one business. Which one do you want to open?',
    '$phone एक से ज़्यादा बिज़नेस से जुड़ा है। कौन-सा खोलना है?',
  );
  Bi get accountsBi => _b('Your accounts', 'आपके खाते');
  String get switchAccount => _t('Switch account', 'खाता बदलें');
  String get openNow => _t('Open now', 'अभी खुला है');
  String get startOwnBusiness => _t('Start my own business', 'अपना बिज़नेस शुरू करें');
  String get addAnotherBusiness => _t('Add another business', 'एक और बिज़नेस जोड़ें');
  String get ownBusinessHint => _t('Your other accounts stay as they are', 'आपके बाकी खाते जैसे हैं वैसे रहेंगे');
  String get newBusiness => _t('New business', 'नया बिज़नेस');
  String switchedTo(String name) => _t('Now in $name', 'अब $name में');
  String pendingPunchesBlock(int n) => _t(
    '$n check-in${n == 1 ? '' : 's'} not sent yet. Connect to the internet and try again, so they are saved in the right business.',
    '$n हाज़िरी अभी भेजनी बाकी है। इंटरनेट चालू करके फिर कोशिश करें, ताकि ये सही बिज़नेस में सेव हों।',
  );
  String get accountsFooter => _t(
    'One number can own a business, work at another and be an accountant for a third.',
    'एक ही नंबर से अपना बिज़नेस, किसी और दुकान पर नौकरी और अकाउंटेंट का काम — सब चल सकता है।',
  );

  // ------------------------------------------------------ Never stuck (F14)
  String accessEnded(String company) =>
      _t('Your access to $company has ended', '$company तक आपकी पहुँच ख़त्म हो गई है');
  String accessEndedOn(String company, String date) =>
      _t('Your access to $company ended on $date', '$company तक आपकी पहुँच $date को ख़त्म हुई');
  String endedReasonLabel(String? r) => switch (r) {
    'closed' => _t('The business closed its StaffMint account.', 'बिज़नेस ने अपना StaffMint खाता बंद कर दिया।'),
    'phone_changed' => _t('Your employer changed your number.', 'आपके मालिक ने आपका नंबर बदल दिया।'),
    'import_rollback' => _t('Your employer undid a staff import.', 'आपके मालिक ने स्टाफ़ इम्पोर्ट वापस लिया।'),
    _ => _t('Your employer removed you from their staff.', 'आपके मालिक ने आपको स्टाफ़ से हटा दिया।'),
  };
  String roleChangedTo(String role) => _t('Your role is now $role', 'अब आपकी भूमिका: $role');
  String get okGotIt => _t('OK, got it', 'ठीक है');
  String get leaveBusiness => _t('Leave this business', 'यह बिज़नेस छोड़ें');
  String leaveBusinessConfirm(String company) => _t('Leave $company?', '$company छोड़ें?');
  String get leaveBusinessBody => _t(
    'You will no longer see this business. The owner will be told. They can add you again later.',
    'यह बिज़नेस आपको नहीं दिखेगा। मालिक को बताया जाएगा। वे बाद में आपको फिर जोड़ सकते हैं।',
  );
  String leftBusiness(String company) => _t('You left $company', 'आपने $company छोड़ दिया');
  String get closeBusiness => _t('Close this business', 'यह बिज़नेस बंद करें');
  String get closeBusinessHint => _t(
    'Everyone loses access. You can restore it within 30 days. Export your data first if you need it.',
    'सबकी पहुँच ख़त्म हो जाएगी। 30 दिन के अंदर वापस चालू कर सकते हैं। ज़रूरत हो तो पहले डेटा एक्सपोर्ट कर लें।',
  );
  String typeNameToConfirm(String name) => _t('Type "$name" to confirm', 'पक्का करने के लिए "$name" लिखें');
  String get closeForever => _t('Close business', 'बिज़नेस बंद करें');
  String businessClosed(String name) =>
      _t('$name is closed. You can restore it for 30 days.', '$name बंद हो गया। 30 दिन तक वापस चालू कर सकते हैं।');
  String get dangerZone => _t('Careful', 'ध्यान से');
  Bi get closedBusinessesBi => _b('Closed businesses', 'बंद बिज़नेस');
  String restoreUntil(String date) => _t('Restore until $date', '$date तक वापस चालू करें');
  String get restore => _t('Restore', 'वापस चालू करें');
  String restored(String name) => _t('$name is back', '$name वापस चालू हो गया');
  String get lockedToOtherPhone => _t('Linked to another phone', 'दूसरे फ़ोन से जुड़ा है');
  String lockedTitle(String company) =>
      _t('Your staff account at $company is on another phone', '$company का आपका स्टाफ़ खाता दूसरे फ़ोन पर है');
  String get lockedBody => _t(
    'For safety, a staff account works on one phone. Ask your employer to approve this phone — they get the request on their phone.',
    'सुरक्षा के लिए स्टाफ़ खाता एक ही फ़ोन पर चलता है। मालिक से यह फ़ोन मंज़ूर करवाएँ — अनुरोध उनके फ़ोन पर पहुँच जाएगा।',
  );
  String get requestThisPhone => _t('Request this phone', 'यह फ़ोन मंज़ूर करवाएँ');
  String get requestSent =>
      _t('Request sent. We will tell you when it is approved.', 'अनुरोध भेज दिया। मंज़ूर होते ही बताएँगे।');
  String get iOwnBusinessInstead => _t('I want my own business', 'मुझे अपना बिज़नेस बनाना है');
  String get newPhoneRequest => _t('New phone', 'नया फ़ोन');
  String needsYouDevice(String name) => _t('$name’s new phone', '$name का नया फ़ोन');
  String deviceRequestBody(String? device) =>
      _t('Wants to check in from ${device ?? 'a new phone'}', '${device ?? 'नए फ़ोन'} से हाज़िरी लगाना चाहते हैं');
  Bi get accountantsBi => _b('Accountants', 'अकाउंटेंट');
  String get accountantsHint => _t(
    'Read-only access to reports, payroll and export.',
    'रिपोर्ट, सैलरी और एक्सपोर्ट देख सकते हैं, बदल नहीं सकते।',
  );
  String get addAccountant => _t('Add accountant', 'अकाउंटेंट जोड़ें');
  String get noAccountants => _t('No accountant added yet', 'अभी कोई अकाउंटेंट नहीं');
  String removeAccountantConfirm(String name) => _t('Remove $name?', '$name को हटाएँ?');
  String get remove => _t('Remove', 'हटाएँ');
  String get appNotJoined => _t('Not on the app yet', 'अभी ऐप पर नहीं');
  String invitedAgo(String when) => _t('Invite sent $when', 'आमंत्रण भेजा: $when');
  String get sendInvite => _t('Send app invite', 'ऐप का आमंत्रण भेजें');
  String get resendInvite => _t('Resend invite', 'आमंत्रण फिर भेजें');
  String get inviteSent => _t('Invite sent on WhatsApp', 'WhatsApp पर आमंत्रण भेज दिया');

  // ------------------------------------------- Shared ownership & recovery
  String isThisYou(String masked) => _t('Is this you, $masked?', 'क्या आप $masked हैं?');
  String get isThisYouBody => _t(
    'This number was not used for a long time. Mobile numbers are sometimes given to someone new.',
    'यह नंबर बहुत समय से इस्तेमाल नहीं हुआ। कभी-कभी मोबाइल नंबर किसी नए व्यक्ति को मिल जाते हैं।',
  );
  String get yesItsMe => _t('Yes, it’s me', 'हाँ, मैं ही हूँ');
  String get notMe => _t('No, not me', 'नहीं, मैं नहीं');
  Bi get ownersBi => _b('Owners', 'मालिक');
  String get ownersHint => _t('Partners can run the business with you.', 'पार्टनर आपके साथ बिज़नेस चला सकते हैं।');
  String get mainOwner => _t('Main owner', 'मुख्य मालिक');
  String get coOwner => _t('Co-owner', 'सह-मालिक');
  String get you => _t('You', 'आप');
  String get addCoOwner => _t('Add co-owner', 'सह-मालिक जोड़ें');
  String get canManageBilling => _t('Can manage billing', 'बिलिंग संभाल सकते हैं');
  String removeOwnerConfirm(String name) => _t('Remove $name as co-owner?', '$name को सह-मालिक से हटाएँ?');
  String get transferBusiness => _t('Transfer the business', 'बिज़नेस किसी और को सौंपें');
  String get transferHint => _t(
    'The new owner accepts from their phone. You can stay as co-owner or leave.',
    'नए मालिक अपने फ़ोन से स्वीकार करेंगे। आप सह-मालिक रह सकते हैं या छोड़ सकते हैं।',
  );
  String get newOwnerNumber => _t('New owner’s mobile number', 'नए मालिक का मोबाइल नंबर');
  String get stayCoOwner => _t('Keep me as co-owner', 'मुझे सह-मालिक रखें');
  String get leaveAfterTransfer => _t('Remove me after the transfer', 'सौंपने के बाद मुझे हटा दें');
  String get codeSentToYou => _t('Enter the code sent to your number', 'आपके नंबर पर भेजा गया कोड लिखें');
  String transferPending(String phone) => _t('Waiting for $phone to accept', '$phone के स्वीकार करने का इंतज़ार');
  String get cancelTransfer => _t('Cancel transfer', 'सौंपना रद्द करें');
  String get ownerLostNumber => _t('Main owner lost their number?', 'मुख्य मालिक का नंबर खो गया?');
  String get ownerLostNumberHint => _t(
    'Move main ownership to their new number. Their old number is told by SMS.',
    'मुख्य मालिकाना उनके नए नंबर पर ले जाएँ। पुराने नंबर पर SMS जाएगा।',
  );
  String get ownersNewNumber => _t('Owner’s new number', 'मालिक का नया नंबर');
  String offerTitle(String company) => _t('$company: become the owner?', '$company: मालिक बनें?');
  String offerBody(String? from) =>
      _t('${from ?? 'The owner'} is handing the business to you.', '${from ?? 'मालिक'} बिज़नेस आपको सौंप रहे हैं।');
  String get accept => _t('Accept', 'स्वीकार करें');
  String get decline => _t('Decline', 'मना करें');
  String holdTitle(String company) =>
      _t('$company: owner account is being recovered', '$company: मालिक का खाता वापस लिया जा रहा है');
  String holdBody(String date) => _t(
    'It moves to a new number on $date. Stop it if this looks wrong.',
    '$date को यह नए नंबर पर चला जाएगा। गलत लगे तो रोकें।',
  );
  String get stop => _t('Stop it', 'रोकें');
  String get stopped => _t('Stopped', 'रोक दिया');
  String get lostOldNumber => _t('Lost your old number? Recover your account', 'पुराना नंबर खो गया? खाता वापस पाएँ');
  String get recoverTitle => _t('Recover your account', 'अपना खाता वापस पाएँ');
  String get recoverByEmail => _t('With the email on your account', 'खाते के ईमेल से');
  String get recoverByEmailHint =>
      _t('We send a code to the email you added in your profile.', 'प्रोफ़ाइल में जोड़े गए ईमेल पर कोड भेजेंगे।');
  String get codeLabel => _t('Code', 'कोड');
  String get recoverNow => _t('Recover account', 'खाता वापस पाएँ');
  String get recoverBySupport => _t('No email? Ask support', 'ईमेल नहीं? सपोर्ट से मदद लें');
  String get recoverBySupportHint => _t(
    'Give any 2 of these. After support checks them, your old number, managers and accountant get 7 days to stop it.',
    'इनमें से कोई 2 दें। जाँच के बाद आपके पुराने नंबर, मैनेजर और अकाउंटेंट को 7 दिन मिलेंगे, ताकि गलत हो तो रोक सकें।',
  );
  String get oldNumber => _t('Old mobile number', 'पुराना मोबाइल नंबर');
  String get gstinOrLicence => _t('GSTIN / shop licence / Udyam number', 'GSTIN / दुकान लाइसेंस / उद्यम नंबर');
  String get paymentId => _t('A past StaffMint payment ID', 'पिछले StaffMint पेमेंट की ID');
  String get recordSelfieVideo => _t(
    'Record a 10-second selfie video saying the business name',
    '10 सेकंड का सेल्फ़ी वीडियो, बिज़नेस का नाम बोलते हुए',
  );
  String get videoRecorded => _t('Video recorded', 'वीडियो रिकॉर्ड हो गया');
  String get needTwoProofs => _t('Give at least 2 of the 3', '3 में से कम से कम 2 दें');
  String get sendRequest => _t('Send request', 'अनुरोध भेजें');
  String recoveryStatus(String status) => switch (status) {
    'hold' => _t('Approved — waiting 7 days', 'मंज़ूर — 7 दिन का इंतज़ार'),
    'completed' => _t('Done — your account is back', 'हो गया — खाता वापस मिल गया'),
    'rejected' => _t('Not approved', 'मंज़ूर नहीं'),
    'stopped' => _t('Stopped by the business', 'बिज़नेस ने रोक दिया'),
    _ => _t('Sent to support', 'सपोर्ट को भेजा गया'),
  };
  String get deleteAccount => _t('Delete my account', 'मेरा खाता हटाएँ');
  String get deleteAccountHint => _t(
    'Your login and profile are deleted. Employers keep salary records as the law requires. Owners must transfer or close their businesses first.',
    'आपका लॉगिन और प्रोफ़ाइल हट जाएगी। मालिक क़ानून के अनुसार सैलरी रिकॉर्ड रखेंगे। मालिकों को पहले बिज़नेस सौंपना या बंद करना होगा।',
  );
  String get deleteForever => _t('Delete forever', 'हमेशा के लिए हटाएँ');
  Bi get pastPayslipsBi => _b('Past salary slips', 'पुरानी सैलरी स्लिप');
  String get exStaffPayslips =>
      _t('Ex-staff can see their old salary slips (12 months)', 'पुराने स्टाफ़ अपनी सैलरी स्लिप देख सकें (12 महीने)');

  // ----------------------------------------------------- Accounts at scale
  String get searchBusinesses => _t('Search businesses', 'बिज़नेस खोजें');
  String get pin => _t('Pin to top', 'ऊपर रखें');
  String get unpin => _t('Unpin', 'ऊपर से हटाएँ');
  Bi get oneBillBi => _b('One bill for your businesses', 'आपके सभी बिज़नेस का एक बिल');
  String oneBillHint(String extra) => _t(
    'Pay for your other businesses here. Staff add up across them; each extra business is $extra/month.',
    'अपने बाकी बिज़नेस का पेमेंट यहीं करें। स्टाफ़ सबका जुड़कर गिना जाएगा; हर अतिरिक्त बिज़नेस $extra/महीना।',
  );
  String get onThisBill => _t('On this bill', 'इस बिल में');
  String get addToBill => _t('Add to this bill', 'इस बिल में जोड़ें');
  String get removeFromBill => _t('Remove from bill', 'बिल से हटाएँ');
  String billedWith(String name) =>
      _t('Paid together with $name. Change the plan there.', '$name के साथ पेमेंट होता है। प्लान वहीं बदलें।');
  String totalStaffOnBill(int n) => _t('$n staff on this bill', 'इस बिल में $n स्टाफ़');

  // ---------------------------------------------------------------- Plan & payment (pick the right plan)
  String billTrialLeft(int days) => days <= 1
      ? _t('Free trial: last day', 'फ़्री ट्रायल: आख़िरी दिन')
      : _t('Free trial: $days days left', 'फ़्री ट्रायल: $days दिन बचे');
  String billTrialEnds(String date) => _t('ends $date', '$date तक');
  String billTrialEnded(String date) => _t(
    'Free trial ended on $date. You are on Free now.',
    'फ़्री ट्रायल $date को ख़त्म हुआ। अब आप फ़्री प्लान पर हैं।',
  );
  String billRenews(String plan, String date) =>
      _t('Your plan: $plan · renews on $date', 'आपका प्लान: $plan · $date को रिन्यू');
  String billPaymentDue(String plan) => _t(
    'Payment for $plan did not go through. Pay to keep it.',
    '$plan का पेमेंट नहीं हुआ। चालू रखने के लिए पेमेंट करें।',
  );
  String billStopsOn(String plan, String date) => _t('$plan stops on $date', '$plan $date को बंद होगा');
  String get billBestTitle => _t('Best plan for your shop', 'आपकी दुकान के लिए सबसे सही प्लान');
  String get billBestBadge => _t('Best for you', 'आपके लिए सबसे सही');
  String planWho(String code, int staffLimit) => switch (code) {
    'free' => _t('Just starting out', 'अभी शुरुआत'),
    'starter' => _t('One shop, pay salary in the app', 'एक दुकान, ऐप से सैलरी'),
    'growth' => _t('Growing shop, uses WhatsApp', 'बढ़ती दुकान, WhatsApp वाले'),
    'pro' => _t('Big business, 30+ staff', 'बड़ा बिज़नेस, 30+ स्टाफ़'),
    _ => staffLimit > 0 ? this.staffLimit(staffLimit) : '',
  };
  String get aMonth => _t('a month', 'हर महीने');
  String get aYear => _t('a year', 'हर साल');
  String get monthUnit => _t('month', 'महीना');
  String get yearUnit => _t('year', 'साल');
  String aboutPerDay(String p) => _t('About $p a day', 'रोज़ लगभग $p');
  String perDayShort(String p) => _t('≈ $p a day', '≈ $p रोज़');
  String get whyThisPlan => _t('Why this plan', 'यह प्लान क्यों');
  String reasonStaff(int n, int limit) => n == 0
      ? _t('Up to $limit staff', '$limit स्टाफ़ तक')
      : _t('Your $n staff fit (up to $limit)', 'आपके $n स्टाफ़ आ जाते हैं ($limit तक)');

  /// Why a plan fits, from how much a paid feature was used ("You used Face check 85 times in your trial").
  String reasonFeature(String feature, int n, {required bool trial}) {
    final when = trial ? _t(' in your trial', ' ट्रायल में') : _t(' in the last 30 days', ' पिछले 30 दिन में');
    return switch (feature) {
      'face_match' => _t('You used Face check $n times$when', 'आपने$when चेहरा मिलान $n बार इस्तेमाल किया'),
      'whatsapp_payslips' => _t('You sent $n salary slips on WhatsApp', 'आपने WhatsApp पर $n सैलरी स्लिप भेजीं'),
      'whatsapp_assistant' => _t('You used Mint on WhatsApp $n times', 'आपने WhatsApp पर Mint $n बार इस्तेमाल किया'),
      'branches' => _t('You have $n branches', 'आपकी $n ब्रांच हैं'),
      'ca_access' => _t('Your CA logs in to this business', 'आपका CA इस बिज़नेस में लॉगिन करता है'),
      'payroll' => _t('You worked out salary $n times', 'आपने $n बार सैलरी बनाई'),
      'payslips' => _t('You made $n salary slips', 'आपने $n सैलरी स्लिप बनाईं'),
      'advances' => _t('You gave $n advances', 'आपने $n एडवांस दिए'),
      'assistant' => _t('You asked Mint $n times', 'आपने Mint से $n बार पूछा'),
      _ => _t('${featureLabel(feature)}: used $n times', '${featureLabel(feature)}: $n बार इस्तेमाल'),
    };
  }

  String keepPlanNamed(String name) => _t('Keep $name', '$name रखें');
  String choosePlanNamed(String name) => _t('Choose $name', '$name लें');
  String get thisIsYourPlan => _t('This is your plan', 'यही आपका प्लान है');
  String billFootTrial(String date) =>
      _t('₹0 today · first payment $date · stop anytime', 'आज ₹0 · पहला पेमेंट $date · कभी भी बंद करें');
  String get billFootPaid =>
      _t('UPI, card or net banking · stop anytime', 'UPI, कार्ड या नेट बैंकिंग · कभी भी बंद करें');
  String freeIsEnough({required bool trial}) => trial
      ? _t(
          'Free is enough for you. Nothing to pay: after the trial you move to Free on its own.',
          'आपके लिए फ़्री प्लान काफ़ी है। कुछ नहीं देना: ट्रायल के बाद आप अपने-आप फ़्री प्लान पर आ जाएँगे।',
        )
      : _t('Free is enough for you. Nothing to pay.', 'आपके लिए फ़्री प्लान काफ़ी है। कुछ नहीं देना।');
  String spendLess(String name) => _t('Want to spend less? $name', 'कम ख़र्च? $name');
  String priceMonthDay(String price, String day) =>
      _t('$price a month · about $day a day', '$price महीना · रोज़ लगभग $day');
  String fitsButStops(int n, String what) =>
      _t('Fits your $n staff, but $what will stop.', '$n स्टाफ़ आ जाएँगे, पर $what बंद होगा।');
  String andJoin(List<String> items) => items.length < 2
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} ${_t('and', 'और')} ${items.last}';
  String get allPlans => _t('All plans', 'सभी प्लान');
  String monthsFree(int n) => n == 1 ? _t('1 month free', '1 महीना फ़्री') : _t('$n months free', '$n महीने फ़्री');
  String yearlyPerMonthSave(String perMonth, String save) =>
      _t('$perMonth a month · you save $save', '$perMonth महीना · $save की बचत');
  String get freeForever => _t('free forever', 'हमेशा फ़्री');
  String notForYouStaff(int limit) =>
      _t('Not for you: allows only $limit staff', 'आपके लिए नहीं: सिर्फ़ $limit स्टाफ़');
  String get onTrialNow => _t('On trial now', 'अभी ट्रायल पर');
  String staffChip(int n, {bool more = false}) => _t('$n${more ? '+' : ''} staff', '$n${more ? '+' : ''} स्टाफ़');
  String get plansNested => _t(
    'Each plan has everything in the plan above it, plus more',
    'हर प्लान में ऊपर वाले प्लान का सब कुछ, और ज़्यादा',
  );
  String get comparePlans => _t('Compare plans', 'प्लान की तुलना');
  String compareRow(String key) => switch (key) {
    'staff' => _t('Staff', 'स्टाफ़'),
    'attendance' => _t('Attendance & leave', 'हाज़िरी और छुट्टी'),
    'salary' => _t('Salary & advances', 'सैलरी और एडवांस'),
    'slips' => _t('Salary slips & reports', 'सैलरी स्लिप, रिपोर्ट'),
    'roster' => _t('Weekly roster (shifts)', 'हफ़्ते का रोस्टर (शिफ़्ट)'),
    'roster_repeat' => _t('Roster repeats every week', 'रोस्टर हर हफ़्ते अपने-आप'),
    'roster_swaps' => _t('Staff swap shifts (you approve)', 'स्टाफ़ शिफ़्ट बदलें (आप मंज़ूर करें)'),
    'verification' => _t('Documents check (Aadhaar, PAN, bank)', 'दस्तावेज़ जाँच (आधार, PAN, बैंक)'),
    'mint' => _t('Ask Mint (voice)', 'Mint से पूछें (आवाज़)'),
    'branches' => _t('More branches', 'कई ब्रांच'),
    'whatsapp' => _t('Slips & helper on WhatsApp', 'WhatsApp पर स्लिप, सहायक'),
    'face' => _t('Face check at punch-in', 'हाज़िरी पर चेहरा मिलान'),
    'ca' => _t('Your CA can log in', 'आपका CA लॉगिन कर सके'),
    'support' => _t('Fast help on call', 'फ़ोन पर तुरंत मदद'),
    _ => key,
  };
  String get priceADay => _t('Price a day', 'रोज़ का ख़र्च');
  String priceLocked(int months) => months % 12 == 0
      ? (months == 12
            ? _t('Your price stays the same for 1 year.', 'आपकी क़ीमत 1 साल तक नहीं बढ़ेगी।')
            : _t(
                'Your price stays the same for ${months ~/ 12} years.',
                'आपकी क़ीमत ${months ~/ 12} साल तक नहीं बढ़ेगी।',
              ))
      : _t('Your price stays the same for $months months.', 'आपकी क़ीमत $months महीने तक नहीं बढ़ेगी।');
  String extraStaffNote(String plan, int limit, String price) => _t(
    '$plan: more than $limit staff? $price a month for each extra person.',
    '$plan: $limit से ज़्यादा स्टाफ़? हर एक्स्ट्रा व्यक्ति $price / महीना।',
  );
  String get payments => _t('Payments', 'पेमेंट');
  String get nextPayment => _t('Next payment', 'अगला पेमेंट');
  String nextPaymentTrial(String amount, String date, String plan) =>
      _t('$amount on $date, only if you choose $plan', '$date को $amount, अगर आप $plan लें');
  String nextPaymentOn(String amount, String date) => _t('$amount on $date', '$date को $amount');
  String get nothingToPay => _t('Nothing to pay on Free', 'फ़्री प्लान पर कुछ नहीं देना');
  String get receipts => _t('Receipts', 'रसीदें');
  String get receiptsEmpty =>
      _t('Your receipts show here after the first payment', 'पहले पेमेंट के बाद रसीदें यहाँ दिखेंगी');
  String receiptFor(String plan, bool yearly) =>
      yearly ? _t('$plan · 1 year', '$plan · 1 साल') : _t('$plan · 1 month', '$plan · 1 महीना');
  String get openInvoice => _t('Open invoice (with GST)', 'इनवॉइस खोलें (GST के साथ)');
  String get paymentQuestions => _t('Questions about payment?', 'पेमेंट के बारे में सवाल?');
  String get stopPlan => _t('Stop plan', 'प्लान बंद करें');
  String stopPlanTitle(String plan) => _t('Stop $plan?', '$plan बंद करें?');
  String stopPlanBody(String date) => _t(
    'Your plan stays on until $date. After that you move to Free. Your data stays safe and you can download it for 30 days.',
    '$date तक आपका प्लान चालू रहेगा। उसके बाद आप फ़्री प्लान पर आ जाएँगे। आपका डेटा सुरक्षित रहेगा, 30 दिन तक डाउनलोड कर सकते हैं।',
  );
  String get planStopped =>
      _t('Plan stopped. Nothing more will be charged.', 'प्लान बंद हो गया। अब कोई पैसा नहीं कटेगा।');
  String get dataSafeNote => _t(
    'Your data stays safe. You can download it for 30 days.',
    'आपका डेटा सुरक्षित रहेगा। 30 दिन तक डाउनलोड कर सकते हैं।',
  );
  String get paySheetSub => _t('Here is exactly what happens', 'आगे क्या होगा, साफ़-साफ़');
  String get cardShort => _t('Card', 'कार्ड');
  String get netBanking => _t('Net banking', 'नेट बैंकिंग');
  String get payTodayZero => _t('Today you pay ₹0', 'आज ₹0 देना है');
  String get paySetUp => _t('Set up UPI autopay or a card', 'UPI ऑटोपे या कार्ड जोड़ें');
  String payOnDate(String date, String amount) => _t('$date: $amount', '$date: $amount');
  String payToday(String amount) => _t('Today: $amount', 'आज: $amount');
  String get payBy => _t('Pay by UPI, card or net banking', 'UPI, कार्ड या नेट बैंकिंग से पेमेंट');
  String payThenMonthly(int day) => _t('Then on the ${_ordinal(day)} of every month', 'फिर हर महीने की $day तारीख़ को');
  String get payThenYearly => _t('Then once a year on the same date', 'फिर हर साल इसी तारीख़ को');
  String payThenEvery(String amount, bool yearly) => yearly
      ? _t('Then $amount every year', 'फिर हर साल $amount')
      : _t('Then $amount every month', 'फिर हर महीने $amount');
  String get payReceiptHere => _t('Receipt saved here', 'रसीद यहीं मिलेगी');
  String get payReceiptHereSub => _t('In Plan & payment, after each payment', 'हर पेमेंट के बाद, प्लान और पेमेंट में');
  String payExtraStaff(int n, String price) =>
      _t('Includes $n extra staff × $price', 'इसमें $n एक्स्ट्रा स्टाफ़ × $price');
  String payExtraBusinesses(int n, String price) =>
      _t('Includes $n more businesses on this bill × $price', 'इसमें इस बिल के $n और बिज़नेस × $price');
  String payLockLine(int months) => months >= 12 && months % 12 == 0
      ? _t(
          'Price fixed for ${months ~/ 12} ${months == 12 ? 'year' : 'years'} · stop anytime from this screen',
          'क़ीमत ${months ~/ 12} साल तक तय · इसी स्क्रीन से कभी भी बंद करें',
        )
      : _t('Stop anytime from this screen', 'इसी स्क्रीन से कभी भी बंद करें');
  String get payButtonZero => _t('Set up payment · ₹0 today', 'पेमेंट सेट करें · आज ₹0');
  String payButton(String amount) => _t('Pay $amount', '$amount दें');
  String switchToQ(String name) => _t('Switch to $name?', '$name पर जाएँ?');
  String switchTo(String name) => _t('Switch to $name', '$name पर जाएँ');
  String youSave(String save, String a, String b) =>
      _t('You save $save a month ($a instead of $b)', 'हर महीने $save बचेंगे ($b की जगह $a)');
  String get willStop => _t('These will stop working', 'ये काम करना बंद कर देंगे');
  String usedTimes(String label, int n) => _t('$label (used $n times)', '$label ($n बार इस्तेमाल)');
  String staffFitIn(int n, String name, int limit) =>
      _t('Your $n staff fit in $name (up to $limit)', 'आपके $n स्टाफ़ $name में आ जाएँगे ($limit तक)');
  String staffNoFit(int n, String name, int limit) => _t(
    'You have $n staff. $name allows $limit. Remove ${n - limit} first.',
    'आपके $n स्टाफ़ हैं। $name में $limit तक। पहले ${n - limit} हटाएँ।',
  );
  String freeAfterTrial(String date) => _t(
    'You don’t need to do anything. When the trial ends on $date you move to Free on its own.',
    'कुछ करने की ज़रूरत नहीं। $date को ट्रायल ख़त्म होते ही आप अपने-आप फ़्री प्लान पर आ जाएँगे।',
  );

  static String _ordinal(int n) {
    final rem100 = n % 100;
    if (rem100 >= 11 && rem100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }

  // ---------------------------------------------------------------- Roster (who works which shift)
  String get rosterTitle => _t('Roster', 'रोस्टर');
  String get rosterCardHint => _t('Plan who works which shift this week', 'इस हफ़्ते कौन किस शिफ़्ट में, तय करें');
  String thisWeekRange(String range) => _t('This week · $range', 'इस हफ़्ते · $range');
  String rosterNotSent(int n) => n == 1
      ? _t('1 change not sent to staff yet', '1 बदलाव अभी स्टाफ़ को नहीं भेजा')
      : _t('$n changes not sent to staff yet', '$n बदलाव अभी स्टाफ़ को नहीं भेजे');
  String get rosterAllSent => _t('Staff have this week', 'स्टाफ़ के पास यह हफ़्ता है');
  String get dayOff => _t('Day off', 'छुट्टी');
  String get noWork => _t('No work', 'काम नहीं');
  String get onLeaveTag => _t('On leave', 'छुट्टी पर');
  String holidayLabel(String name) => _t('Holiday · $name', 'त्योहार · $name');
  String get copyLastWeek => _t('Copy last week', 'पिछला हफ़्ता कॉपी');
  String get sendToStaff => _t('Send to staff', 'स्टाफ़ को भेजें');
  String get sameAllWeek => _t('Same shift all week', 'पूरे हफ़्ते यही शिफ़्ट');
  String get sameAllWeekHint => _t('Except their days off', 'छुट्टी वाले दिन छोड़कर');
  String get usualShiftOption => _t('Usual shift', 'रोज़ वाली शिफ़्ट');
  String usualShiftIs(String what) => _t('From their profile: $what', 'प्रोफ़ाइल से: $what');
  String get sendSheetTitle => _t('Send shifts to staff?', 'स्टाफ़ को शिफ़्ट भेजें?');
  String get sendSheetBody =>
      _t('Staff whose days changed get a message on their phone.', 'जिनके दिन बदले, उन्हें फ़ोन पर मैसेज जाएगा।');
  String thingsToFix(int n) => n == 1
      ? _t('1 thing to fix first', 'पहले 1 चीज़ ठीक करें')
      : _t('$n things to fix first', 'पहले $n चीज़ें ठीक करें');
  String problemLeave(String name, String day) => _t('$name is on leave on $day', '$name $day को छुट्टी पर है');
  String get fixMakeOff => _t('Make it Off', 'छुट्टी करें');
  String problemNoOff(String name) => _t('$name has no day off this week', '$name को इस हफ़्ते कोई छुट्टी नहीं');
  String fixGiveOff(String day) => _t('Give $day off', '$day छुट्टी दें');
  String sendToN(int n) =>
      n == 1 ? _t('Send to 1 staff', '1 स्टाफ़ को भेजें') : _t('Send to $n staff', '$n स्टाफ़ को भेजें');
  String get nothingToSend => _t('Nothing new to send', 'भेजने को कुछ नया नहीं');
  String rosterSent(int n) =>
      n == 1 ? _t('Sent to 1 staff', '1 स्टाफ़ को भेजा') : _t('Sent to $n staff', '$n स्टाफ़ को भेजा');
  String copiedLastWeek(int n) => n == 0
      ? _t('Last week had no roster changes to copy', 'पिछले हफ़्ते कॉपी करने को कोई बदलाव नहीं')
      : _t('Copied last week. Check it, then send.', 'पिछला हफ़्ता कॉपी हुआ। देखकर भेजें।');
  String get rosterAddShiftsTip => _t(
    'Tip: add shifts like Morning and Evening in Timings & holidays, then plan them here.',
    'सुझाव: समय और छुट्टियाँ में सुबह, शाम जैसी शिफ़्ट जोड़ें, फिर यहाँ तय करें।',
  );
  String get addShifts => _t('Add shifts', 'शिफ़्ट जोड़ें');
  String get rosterNeedsPlan => _t('Roster comes with Starter and up.', 'रोस्टर स्टार्टर और उससे ऊपर के प्लान में है।');
  String get viewDay => _t('Day', 'दिन');
  String get previousWeek => _t('Previous week', 'पिछला हफ़्ता');
  String get nextWeek => _t('Next week', 'अगला हफ़्ता');
  String get viewWeek => _t('Week', 'हफ़्ता');
  String get leaveShort => _t('L', 'छु');
  String get tapCellHint => _t('Tap a box to change it', 'बदलने के लिए किसी खाने पर टैप करें');
  String get repeatTitle => _t('Repeat every week', 'हर हफ़्ते दोहराएँ');
  String get repeatOffHint => _t('Plan once, next weeks fill themselves', 'एक बार तय करें, अगले हफ़्ते अपने-आप भरेंगे');
  String get repeatOnSame => _t('Repeats every week: same shifts', 'हर हफ़्ते दोहराता है: वही शिफ़्ट');
  String get repeatOnSwap => _t('Repeats every week: shifts swap', 'हर हफ़्ते दोहराता है: शिफ़्ट बदलती है');
  String get repeatAutoOn => _t('Sent to staff on its own every Thursday', 'हर गुरुवार अपने-आप स्टाफ़ को जाता है');
  String get repeatAutoOff => _t('We remind you every Thursday to send it', 'हर गुरुवार भेजने की याद दिलाएँगे');
  String get repeatNeedsPlan => _t('Comes with Growth and up', 'Growth और उससे ऊपर के प्लान में');
  String get repeatSheetTitle => _t('Repeat this week every week?', 'यह हफ़्ता हर हफ़्ते दोहराएँ?');
  String get repeatNo => _t('No, I’ll plan each week', 'नहीं, हर हफ़्ते ख़ुद तय करूँगा');
  String get repeatSame => _t('Yes, same every week', 'हाँ, हर हफ़्ते यही');
  String get repeatSameHint => _t('Next week will be like this week', 'अगला हफ़्ता इसी हफ़्ते जैसा होगा');
  String get repeatSwap => _t('Yes, swap every week', 'हाँ, हर हफ़्ते बदलें');
  String repeatSwapHint(String chain) =>
      _t('Each person moves to the next shift every week: $chain', 'हर हफ़्ते हर व्यक्ति अगली शिफ़्ट में: $chain');
  String get repeatSwapNeeds =>
      _t('To swap, use at least 2 shifts this week', 'बदलने के लिए इस हफ़्ते कम से कम 2 शिफ़्ट लगाएँ');
  String get repeatAutoSend => _t('Send to staff on its own', 'स्टाफ़ को अपने-आप भेजें');
  String get repeatAutoSendHint => _t(
    'Every Thursday, for the next week. Otherwise we remind you to check and send.',
    'हर गुरुवार, अगले हफ़्ते का। नहीं तो हम देखकर भेजने की याद दिलाएँगे।',
  );
  String get repeatTurnedOn => _t('Next week is filled in. Check it, then send.', 'अगला हफ़्ता भर गया। देखकर भेजें।');
  String get repeatTurnedOff => _t('Repeat turned off', 'दोहराना बंद किया');
  String _hrs(double h) => h == h.roundToDouble() ? '${h.round()}' : h.toStringAsFixed(1);
  String problemShortRest(String name, String day, double hours) => _t(
    '$name gets only ${_hrs(hours)} hours’ rest before $day',
    '$name को $day से पहले सिर्फ़ ${_hrs(hours)} घंटे आराम',
  );
  String problemLongWeek(String name, double hours) => _t(
    '$name works ${_hrs(hours)} hours this week (more than 48)',
    '$name इस हफ़्ते ${_hrs(hours)} घंटे काम करेंगे (48 से ज़्यादा)',
  );
  String problemShortStaff(String day, String shift, int count, int min) =>
      _t('$day $shift: $count of $min people', '$day $shift: $min में से $count लोग');
  String warningsTitle(int n) => _t('Please check ($n)', 'ज़रा देख लें ($n)');
  String get warningsHint => _t('These won’t stop sending.', 'इनसे भेजना नहीं रुकेगा।');
  String get minStaffLabel => _t('Fewest people needed on this shift', 'इस शिफ़्ट में कम से कम कितने लोग');
  String get minStaffHint => _t('We tell you before sending if fewer are on it', 'कम हुए तो भेजने से पहले बताएँगे');
  String swapRequestsTitle(int n) => _t('Swap requests ($n)', 'अदला-बदली की अर्ज़ी ($n)');
  String swapLine(String from, String to, String day) =>
      _t('$from and $to want to swap $day', '$from और $to $day की शिफ़्ट बदलना चाहते हैं');
  String swapDetail(String from, String fromNew, String to, String toNew) =>
      _t('$from takes $fromNew · $to takes $toNew', '$from: $fromNew · $to: $toNew');
  String get swapApproved => _t('Swap approved. Both have been told.', 'अदला-बदली मंज़ूर। दोनों को बता दिया।');
  String get swapRejected => _t('Swap not approved. Both have been told.', 'नामंज़ूर किया। दोनों को बता दिया।');
  String get swapADay => _t('Swap a day', 'दिन बदलें');
  String get swapPickDay => _t('Which day do you want to swap?', 'कौन सा दिन बदलना है?');
  String get swapPickPerson => _t('Swap with', 'किसके साथ बदलें');
  String get swapNobody => _t('Nobody has a different shift that day', 'उस दिन किसी की अलग शिफ़्ट नहीं');
  String swapConfirm(String name, String day) => _t('Ask $name to swap $day?', '$name से $day बदलने को कहें?');
  String swapYouGet(String label) => _t('You’d work: $label', 'आपकी: $label');
  String swapTheyGet(String name, String label) => _t('$name would work: $label', '$name की: $label');
  String get swapOwnerApproves =>
      _t('After they say yes, your owner approves it.', 'उनके हाँ कहने के बाद मालिक मंज़ूर करेंगे।');
  String get swapAsk => _t('Ask', 'पूछें');
  String swapAsked(String name) =>
      _t('Asked $name. We’ll tell you when they answer.', '$name से पूछ लिया। जवाब आने पर बताएँगे।');
  String swapIncoming(String name, String day) =>
      _t('$name wants to swap $day', '$name $day की शिफ़्ट बदलना चाहते हैं');
  String swapIncomingDetail(String you, String theirs) =>
      _t('You’d work $you; they’d take your $theirs', 'आपकी $you होगी, वे आपकी $theirs लेंगे');
  String get swapYes => _t('Yes, swap', 'हाँ, बदलें');
  String get swapNo => _t('Can’t', 'नहीं');
  String swapWaitingFor(String name) => _t('Waiting for $name', '$name के जवाब का इंतज़ार');
  String get swapWaitingOwner => _t('Waiting for the owner', 'मालिक के जवाब का इंतज़ार');
  String get swapApprovedTag => _t('Approved', 'मंज़ूर');
  String swapDeclinedTag(String name) => _t('$name said no', '$name ने मना किया');
  String get swapRejectedTag => _t('Owner said no', 'मालिक ने मना किया');
  String get swapCancelledTag => _t('Cancelled', 'रद्द');
  String swapWith(String name, String day) => _t('Swap with $name · $day', '$name के साथ अदला-बदली · $day');
  String get swapAccepted => _t('Accepted. Your owner will approve it.', 'हाँ कह दिया। मालिक मंज़ूर करेंगे।');
  String get swapDeclined => _t('Told them you can’t.', 'उन्हें बता दिया कि नहीं हो पाएगा।');
  String get myWeek => _t('My week', 'मेरा हफ़्ता');

  // ---------------------------------------------------------------- Documents check (background verification)
  String get docCheckTitle => _t('Documents check', 'दस्तावेज़ जाँच');
  String get docCheckNone => _t('Not checked yet', 'अभी जाँच नहीं हुई');
  String get docCheckNoneHint => _t(
    'Aadhaar, PAN, licence, PF and bank, against government records',
    'आधार, PAN, लाइसेंस, PF और बैंक, सरकारी रिकॉर्ड से',
  );
  String get checkNow => _t('Check now', 'अभी जाँचें');
  String docAsked(String name) => _t('Waiting for $name to agree', '$name की अनुमति का इंतज़ार');
  String docInProgress(String name) => _t('$name is doing the steps', '$name क़दम पूरे कर रहे हैं');
  String get docVerified => _t('Verified ✓', 'जाँच पूरी ✓');
  String get docNeedsLook => _t('Needs your look', 'आप एक बार देख लें');
  String get cancelCheck => _t('Cancel request', 'अर्ज़ी रद्द करें');
  String docKind(String kind) => switch (kind) {
    'aadhaar' => _t('Aadhaar', 'आधार'),
    'pan' => _t('PAN', 'PAN'),
    'dl' => _t('Driving licence', 'ड्राइविंग लाइसेंस'),
    'voter' => _t('Voter ID', 'वोटर कार्ड'),
    'uan' => _t('PF number (UAN)', 'PF नंबर (UAN)'),
    'face' => _t('Selfie', 'सेल्फ़ी'),
    _ => _t('Bank account', 'बैंक खाता'),
  };
  String docKindHint(String kind) => switch (kind) {
    'aadhaar' => _t('Name and date of birth, with an OTP', 'नाम और जन्म तारीख़, OTP से'),
    'pan' => _t('Valid PAN and the name on it', 'सही PAN और उस पर नाम'),
    'dl' => _t('Valid, the name on it and till when', 'सही है, किसका नाम है और कब तक चलेगा'),
    'voter' => _t('Valid voter ID and the name on it', 'सही वोटर कार्ड और उस पर नाम'),
    'uan' => _t('Name and past jobs, from the PF office', 'नाम और पहले की नौकरियाँ, PF दफ़्तर से'),
    'face' => _t('Matched with the photo on their ID', 'पहचान पत्र की फ़ोटो से मिलान'),
    _ => _t('₹1 test to their salary account', 'सैलरी खाते में ₹1 टेस्ट'),
  };
  String get moreChecks => _t('More checks', 'और जाँच');
  String get pastJobs => _t('Past jobs (PF record)', 'पहले की नौकरियाँ (PF रिकॉर्ड)');
  String get jobNow => _t('now', 'अभी तक');
  String get reportPdf => _t('Report (PDF)', 'रिपोर्ट (PDF)');
  String get dlLabel => _t('Licence number', 'लाइसेंस नंबर');
  String get dobLabel => _t('Date of birth', 'जन्म तारीख़');
  String get pickDob => _t('Pick date of birth', 'जन्म तारीख़ चुनें');
  String get dobHintDl => _t('As on the licence', 'जैसी लाइसेंस पर है');
  String get checkDl => _t('Check licence', 'लाइसेंस जाँचें');
  String get voterLabel => _t('Voter ID number', 'वोटर कार्ड नंबर');
  String get checkVoter => _t('Check voter ID', 'वोटर कार्ड जाँचें');
  String uanUseSaved(String last4) => _t('Use UAN ending $last4', 'आख़िरी $last4 वाला UAN');
  String get uanOther => _t('Use a different UAN', 'दूसरा UAN');
  String get checkUan => _t('Check UAN', 'UAN जाँचें');
  String checkSheetTitle(String name) => _t('Check $name’s documents', '$name के दस्तावेज़ जाँचें');
  String get checkSheetHint =>
      _t('They finish it on their phone in about 3 minutes.', 'वे अपने फ़ोन पर लगभग 3 मिनट में पूरा करेंगे।');
  String checksLeft(int left, int limit) =>
      _t('Included in your plan: $left of $limit left this month', 'आपके प्लान में: इस महीने $limit में से $left बाकी');
  String checksUsedUp(int limit, String price) => _t(
    'All $limit checks used this month. More at $price each are coming soon.',
    'इस महीने की सभी $limit जाँच हो गईं। ज़्यादा जाँच $price में जल्द आएगी।',
  );
  String sendToPerson(String name) => _t('Send to $name', '$name को भेजें');
  String docSent(String name) =>
      _t('Sent to $name. We’ll tell you when it’s done.', '$name को भेज दिया। पूरा होने पर बताएँगे।');
  String get checkNeedsPlan =>
      _t('Document checks come with Growth and up', 'दस्तावेज़ जाँच Growth और उससे ऊपर के प्लान में');
  String get resVerified => _t('Verified', 'सही');
  String resMismatch(String name) => _t('Name on record: $name', 'रिकॉर्ड में नाम: $name');
  String get resNotFound => _t('Not found', 'नहीं मिला');
  String get resFailed => _t('Couldn’t check yet', 'अभी जाँच नहीं हो पाई');
  String get resWaiting => _t('Not done yet', 'अभी बाकी');
  String get resOtpSent => _t('Waiting for the OTP', 'OTP का इंतज़ार');
  String resAccepted(String reason) => _t('You accepted: $reason', 'आपने माना: $reason');
  String get thisIsFine => _t('This is fine', 'यह ठीक है');
  String get askAgainBtn => _t('Ask again', 'फिर से माँगें');
  String get acceptTitle => _t('Why is this fine?', 'यह ठीक क्यों है?');
  String get acceptDefault => _t('Same person, name written differently', 'वही व्यक्ति, नाम अलग तरह लिखा');
  String docBorn(String dob) => _t('Born $dob', 'जन्म $dob');
  String endingIn(String last4) => _t('ending $last4', 'आख़िरी $last4');
  String get askedAgain => _t('Asked them to do it again', 'उन्हें फिर से करने को कहा');
  String get docBadgeVerified => _t('Verified', 'जाँचे गए');
  String get docBadgeLook => _t('Check docs', 'दस्तावेज़ देखें');
  // Staff side
  String get verifyCardTitle => _t('Verify your documents', 'अपने दस्तावेज़ जाँचें');
  String verifyCardHint(String business) =>
      _t('$business asked. About 3 minutes.', '$business ने कहा है। लगभग 3 मिनट।');
  String get verifyStart => _t('Start', 'शुरू करें');
  String get verifyConsentTitle => _t('Before we start', 'शुरू करने से पहले');
  String get allowStart => _t('Allow and start', 'अनुमति दें, शुरू करें');
  String stepOf(int n, int total) => _t('Step $n of $total', 'क़दम $n / $total');
  String get aadhaarLabel => _t('Aadhaar number', 'आधार नंबर');
  String get sendOtp => _t('Send OTP', 'OTP भेजें');
  String get otpSentAadhaar => _t('OTP sent to your Aadhaar mobile', 'आधार वाले मोबाइल पर OTP भेजा');
  String get otpLabel => _t('OTP', 'OTP');
  String get verifyBtn => _t('Verify', 'जाँचें');
  String get checkPan => _t('Check PAN', 'PAN जाँचें');
  String bankUseSaved(String last4, String ifsc) =>
      _t('Use account ending $last4 ($ifsc)', 'आख़िरी $last4 वाला खाता ($ifsc)');
  String get bankOther => _t('Use a different account', 'दूसरा खाता');
  String get accountLabel => _t('Account number', 'खाता नंबर');
  String get checkBank => _t('Check with ₹1', '₹1 से जाँचें');
  String staffMismatch(String name) =>
      _t('The record says $name. Your employer will look at it.', 'रिकॉर्ड में $name लिखा है। मालिक देख लेंगे।');
  String get staffNotFound =>
      _t('Not found. Check the number and try again.', 'नहीं मिला। नंबर देखकर फिर से कोशिश करें।');
  String get staffFailed => _t('Couldn’t check right now. Try again.', 'अभी जाँच नहीं हो पाई। फिर से कोशिश करें।');
  String get allDone => _t('All done. Your employer can see the results.', 'सब हो गया। मालिक नतीजे देख सकते हैं।');
  String get changedTag => _t('Changed', 'बदला');
  String faceMatch(int pct) => _t('Match $pct%', 'मिलान $pct%');
  String faceWithId(String id) => _t('photo on $id', '$id की फ़ोटो से');
  String get resMismatchFace => _t('Doesn’t look like the ID photo', 'पहचान पत्र की फ़ोटो जैसा नहीं दिखता');
  String get faceNoFaceOnId => _t('No face on the ID photo', 'पहचान पत्र की फ़ोटो में चेहरा नहीं');
  String get faceNeedsId => _t(
    'First add a photo of your Aadhaar, PAN or licence. Your selfie is matched with it.',
    'पहले आधार, PAN या लाइसेंस की फ़ोटो जोड़ें। सेल्फ़ी उसी से मिलाई जाएगी।',
  );
  String get faceNeedsIdOwner => _t(
    'First add a photo of their Aadhaar, PAN or licence. The photo is matched with it.',
    'पहले उनके आधार, PAN या लाइसेंस की फ़ोटो जोड़ें। फ़ोटो उसी से मिलाई जाएगी।',
  );
  String get addIdPhoto => _t('Add ID photo', 'पहचान पत्र की फ़ोटो जोड़ें');
  String get takeSelfie => _t('Take a selfie', 'सेल्फ़ी लें');
  String get takeTheirPhoto => _t('Take their photo', 'उनकी फ़ोटो लें');
  String get faceTheirHint => _t(
    'Take a clear photo of their face in good light. The photo is not kept.',
    'अच्छी रोशनी में उनके चेहरे की साफ़ फ़ोटो लें। फ़ोटो रखी नहीं जाती।',
  );
  String get slipAdded => _t('Slip photo added', 'पर्ची की फ़ोटो लग गई');
  String get faceSelfieHint => _t(
    'Face the camera in good light. The photo is not kept.',
    'अच्छी रोशनी में कैमरे की ओर देखें। फ़ोटो रखी नहीं जाती।',
  );
  String get staffFaceMismatch => _t(
    'Didn’t match the ID photo. Your employer will look at it.',
    'पहचान पत्र की फ़ोटो से मेल नहीं खाई। मालिक देख लेंगे।',
  );
  String get staffFaceNoFace => _t(
    'No face found on your ID photo. Add a clearer one in My documents.',
    'पहचान पत्र की फ़ोटो में चेहरा नहीं मिला। मेरे दस्तावेज़ में साफ़ फ़ोटो जोड़ें।',
  );
  String get doWithThem => _t('Do it with them', 'उनके साथ करें');
  String get doWithThemHint =>
      _t('No smartphone? Do the steps together on your phone.', 'स्मार्टफ़ोन नहीं है? आपके फ़ोन पर साथ में करें।');
  String doingFor(String name) => _t('With $name', '$name के साथ');
  String readThisTo(String name) => _t('Read this to $name', '$name को यह पढ़कर सुनाएँ');
  String theyAgreedSigned(String name) =>
      _t('$name agreed and signed a slip', '$name ने हाँ कहा और पर्ची पर साइन किया');
  String get slipPhotoNeeded => _t('Photo of the signed slip', 'साइन की हुई पर्ची की फ़ोटो');
  String get continueBtn => _t('Continue', 'आगे बढ़ें');
  String otpToTheirPhone(String name) => _t(
    'The OTP goes to $name’s Aadhaar mobile. Ask them for it.',
    'OTP $name के आधार वाले मोबाइल पर आएगा। उनसे पूछें।',
  );
  String get agreedOnPaper => _t('Agreed on paper', 'काग़ज़ पर सहमति');
  String get seeSlip => _t('See slip', 'पर्ची देखें');

  // ---------------------------------------------------------------- Staff documents
  String get documentsTitle => _t('Documents', 'दस्तावेज़');
  String get myDocuments => _t('My documents', 'मेरे दस्तावेज़');
  Bi get myDocumentsBi => _b('My documents', 'मेरे दस्तावेज़');
  String get myDocumentsHint =>
      _t('Aadhaar, PAN, licence. Only your employer sees them.', 'आधार, PAN, लाइसेंस। सिर्फ़ आपके मालिक देखते हैं।');
  String get noDocuments => _t('No documents yet', 'अभी कोई दस्तावेज़ नहीं');
  String get noDocumentsHint => _t(
    'Keep copies of Aadhaar, PAN, licence and more, safely in one place.',
    'आधार, PAN, लाइसेंस वगैरह की कॉपी एक जगह सुरक्षित रखें।',
  );
  String get addDocument => _t('Add document', 'दस्तावेज़ जोड़ें');
  String fileKind(String kind) => switch (kind) {
    'aadhaar' => _t('Aadhaar', 'आधार'),
    'pan' => _t('PAN', 'PAN'),
    'dl' => _t('Driving licence', 'ड्राइविंग लाइसेंस'),
    'voter' => _t('Voter ID', 'वोटर ID'),
    'passport' => _t('Passport', 'पासपोर्ट'),
    'bank_proof' => _t('Bank passbook', 'बैंक पासबुक'),
    'address' => _t('Address proof', 'पते का सबूत'),
    'police' => _t('Police verification', 'पुलिस जाँच पत्र'),
    'experience' => _t('Experience letter', 'अनुभव पत्र'),
    _ => _t('Other', 'दूसरा'),
  };
  String get whichDocument => _t('Which document?', 'कौन-सा दस्तावेज़?');
  String get documentName => _t('What is it?', 'यह क्या है?');
  String get documentNameHint => _t('e.g. 10th marksheet', 'जैसे 10वीं की मार्कशीट');
  String get documentNumber => _t('Number', 'नंबर');
  String get aadhaarLast4 => _t('Last 4 digits of Aadhaar', 'आधार के आख़िरी 4 अंक');
  String get maskedAadhaarNote => _t(
    'Upload the masked Aadhaar (from the UIDAI website) if you can. We keep only the last 4 digits.',
    'हो सके तो छिपे अंकों वाला आधार (आधार की सरकारी वेबसाइट से) लगाएँ। हम सिर्फ़ आख़िरी 4 अंक रखते हैं।',
  );
  String get validTill => _t('Valid till', 'कब तक मान्य');
  String get pickDate => _t('Pick date', 'तारीख़ चुनें');
  String get photosOfDocument => _t('Photos (front and back)', 'फ़ोटो (आगे और पीछे)');
  String get addPhoto => _t('Add photo', 'फ़ोटो जोड़ें');
  String get addSlipPhoto => _t('Add photo of slip', 'पर्ची की फ़ोटो जोड़ें');
  String staffAgreedTick(String name) => _t('$name agreed to me keeping a copy', '$name ने कॉपी रखने की सहमति दी है');
  String get consentSlip => _t('Photo of the signed consent slip', 'साइन की हुई सहमति पर्ची की फ़ोटो');
  String get consentSlipHint => _t(
    'Needed once, for staff who don’t use the app. They sign a slip saying you may keep copies of their documents.',
    'एक बार चाहिए, उन स्टाफ़ के लिए जो ऐप नहीं चलाते। वे पर्ची पर साइन करें कि आप उनके दस्तावेज़ों की कॉपी रख सकते हैं।',
  );
  String get onlyOwnerSees => _t(
    'Kept locked. Only the owner can open it, and each opening is noted in History.',
    'ताले में रखा जाता है। सिर्फ़ मालिक खोल सकते हैं, और हर बार खोलना इतिहास में दर्ज होता है।',
  );
  String get documentSaved => _t('Document saved', 'दस्तावेज़ सेव हुआ');
  String get documentRemoved => _t('Document removed', 'दस्तावेज़ हटाया');
  String removeDocumentQ(String name) => _t('Remove $name?', '$name हटाएँ?');
  String get removeDocumentBody => _t('The copy is deleted for good.', 'कॉपी हमेशा के लिए हट जाएगी।');
  String endingWith(String last4) => _t('ending $last4', 'आख़िरी $last4');
  String pagesCount(int n) => _t(n == 1 ? '1 page' : '$n pages', '$n पेज');
  String get addedByStaff => _t('Added by staff', 'स्टाफ़ ने जोड़ा');
  String get addedByYou => _t('Added by you', 'आपने जोड़ा');
  String validTillDate(String date) => _t('Valid till $date', '$date तक मान्य');
  String expiresSoon(String date) => _t('Expires $date', '$date को ख़त्म');
  String expiredOn(String date) => _t('Expired $date', '$date को ख़त्म हो गया');
  String get openPdf => _t('Open PDF', 'PDF खोलें');
  String get changeExpiry => _t('Change date', 'तारीख़ बदलें');
  String get signedSlip => _t('Signed consent slip', 'साइन की हुई सहमति पर्ची');
  String get couldNotLoadFile =>
      _t('Couldn’t load. Pull down to try again.', 'लोड नहीं हुआ। नीचे खींचकर फिर कोशिश करें।');

  // ---------------------------------------------------------------- Field staff location
  String get trackAskTitle => _t('Share location during work?', 'काम के दौरान लोकेशन शेयर करें?');
  String trackAskHint(String business) =>
      _t('$business asked. Only while you are checked in.', '$business ने कहा है। सिर्फ़ चेक-इन रहते हुए।');
  String get trackRead => _t('Read and agree', 'पढ़ें और हाँ कहें');
  String get trackConsentTitle => _t('Location during work', 'काम के दौरान लोकेशन');
  String get trackAgree => _t('I agree', 'मैं सहमत हूँ');
  String get trackNotNow => _t('Not now', 'अभी नहीं');
  String get trackAgreed =>
      _t('Thanks. Sharing starts when you check in.', 'धन्यवाद। चेक-इन करने पर शेयर होना शुरू होगा।');
  String get trackSharingNow => _t('Sharing location until you check out', 'चेक-आउट तक लोकेशन शेयर हो रही है');
  String trackKmToday(String km) => _t('$km km today', 'आज $km किमी');
  String get trackNotifTitle => _t('StaffMint: sharing location', 'StaffMint: लोकेशन शेयर हो रही है');
  String get trackNotifText => _t('Until you check out', 'चेक-आउट तक');
  String get trackProfileOn => _t('On while checked in', 'चेक-इन रहते हुए चालू');
  String get trackProfileAsk => _t('Your employer asked. Tap to read.', 'मालिक ने कहा है। पढ़ने के लिए दबाएँ।');
  String get trackStop => _t('Stop sharing', 'शेयर करना बंद करें');
  String get trackStopConfirm => _t(
    'Your employer will be told. You can agree again later.',
    'मालिक को बताया जाएगा। आप बाद में फिर हाँ कह सकते हैं।',
  );
  String get trackStopped => _t('Location sharing stopped', 'लोकेशन शेयर करना बंद हुआ');
  String get fieldStaff => _t('Field staff: share location during shift', 'फ़ील्ड स्टाफ़: शिफ़्ट में लोकेशन शेयर');
  String get fieldStaffOff => _t('See where they are while checked in', 'चेक-इन रहते हुए देखें वे कहाँ हैं');
  String fieldStaffWaiting(String name) => _t('Waiting for $name to agree', '$name की सहमति का इंतज़ार');
  String get fieldStaffOn => _t('On: shares while checked in', 'चालू: चेक-इन रहते हुए शेयर');
  String get fieldCheckInAnywhere => _t('Check in from anywhere', 'कहीं से भी चेक-इन करें');
  String get fieldCheckInHint => _t(
    'You are field staff. Your location is shared while you are checked in.',
    'आप फ़ील्ड स्टाफ़ हैं। चेक-इन रहते हुए आपकी लोकेशन शेयर होती है।',
  );
  String get fieldMapTitle => _t('Field staff', 'फ़ील्ड स्टाफ़');
  String fieldMapCard(int n) => _t('$n field staff · see where they are now', '$n फ़ील्ड स्टाफ़ · देखें अभी कहाँ हैं');
  String get fieldNone => _t(
    'No field staff yet. Turn it on in a staff profile: "Field staff: share location during shift".',
    'अभी कोई फ़ील्ड स्टाफ़ नहीं। स्टाफ़ प्रोफ़ाइल में चालू करें: "फ़ील्ड स्टाफ़: शिफ़्ट में लोकेशन शेयर"।',
  );
  String minAgo(int m) => m < 1 ? _t('just now', 'अभी') : _t('$m min ago', '$m मिनट पहले');
  String hoursAgo(int h) => _t('$h h ago', '$h घंटे पहले');
  String liveStatus(String status) => switch (status) {
    'waiting_consent' => _t('Hasn’t agreed yet', 'अभी सहमति नहीं दी'),
    'not_started' => _t('Not checked in', 'चेक-इन नहीं किया'),
    'ended' => _t('Checked out', 'चेक-आउट किया'),
    _ => '',
  };
  String nearPlace(String place) => _t('near $place', '$place के पास');
  String kmShort(String km) => _t('$km km', '$km किमी');
  String get myRoute => _t('My route today', 'आज मेरा रास्ता');
  String get dayKm => _t('Travelled', 'कुल चले');
  String get dayStops => _t('Stops', 'रुके');
  String stopLine(String from, String to, int minutes) =>
      _t('$from – $to · $minutes min', '$from – $to · $minutes मिनट');
  String get travelAllowance => _t('Travel allowance for field staff', 'फ़ील्ड स्टाफ़ का यात्रा भत्ता');
  String get travelOff => _t('Off', 'बंद');
  String perKm(String rs) => _t('$rs / km', '$rs / किमी');
  String travelExample(String rs, String total) => _t(
    'Raju travelled 420 km during shifts this month → $total added to their salary ($rs per km).',
    'राजू इस महीने शिफ़्ट में 420 किमी चले → सैलरी में $total जुड़ेंगे ($rs प्रति किमी)।',
  );
  String get travelOffHint => _t(
    'Only km tracked while field staff are checked in count.',
    'सिर्फ़ चेक-इन रहते हुए ट्रैक हुए किमी गिने जाते हैं।',
  );
  String stopN(int n) => _t('Stop $n', 'रुकाव $n');
  String get noRouteYet => _t('No route for this day.', 'इस दिन का कोई रास्ता नहीं।');
  String get checkedInHere => _t('Checked in', 'चेक-इन');
  String get checkedOutHere => _t('Checked out', 'चेक-आउट');
  String get locationOffEvent => _t('Turned off location', 'लोकेशन बंद की');

  // ---------------------------------------------------------------- Misc
  String get thisMonth => _t('This month', 'इस महीने');
  String get offlineNote => _t('Offline · showing saved data', 'ऑफ़लाइन · सेव डेटा दिखा रहे हैं');

  // ---------------------------------------------------------------- Money
  String money(int paise) => Money.format(paise);
}

extension StringsContext on BuildContext {
  S get s => S.of(this);
}
