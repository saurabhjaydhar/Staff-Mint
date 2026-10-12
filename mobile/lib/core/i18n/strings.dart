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
  Bi _b(String en, String hi) => isHindi ? Bi(hi, en) : Bi(en);

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
  String get optional => _t('optional', 'वैकल्पिक');
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
    'आपके प्लान की सीमा पूरी हो गई। More › Billing में अपग्रेड करें।',
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
  String get addressOptional => _t('Address (optional)', 'पता (वैकल्पिक)');
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
  String get switchLanguage => _t('Switch to Hindi', 'Switch to English');

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
        return _t('Not yet', 'बाकी');
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

  String leaveTypeLabel(String? t) {
    switch (t) {
      case 'paid':
        return _t('Paid leave', 'सवेतन छुट्टी');
      case 'sick':
        return _t('Sick leave', 'बीमारी की छुट्टी');
      case 'unpaid':
        return _t('Unpaid leave', 'बिना वेतन छुट्टी');
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
  String get outsidePunchApproval => _t('Punch outside shop area', 'दुकान के दायरे से बाहर पंच');
  String get lockPunchApproval => _t('Punch without phone lock', 'फ़ोन लॉक खोले बिना पंच');
  String lockTagShort(String issue) => issue == 'failed' ? _t('Lock ✗', 'लॉक ✗') : _t('No lock', 'बिना लॉक');
  String distanceAway(num m) => _t('${m.round()} m away', '${m.round()} मीटर दूर');
  String staffUsage(int count, int limit) =>
      _t('$count of $limit staff on your plan', 'आपके प्लान में $limit में से $count स्टाफ़');

  // ---------------------------------------------------------------- Staff
  String get staffTitle => _t('Staff', 'स्टाफ़');
  String get searchStaff => _t('Search by name or phone', 'नाम या फ़ोन से खोजें');
  String get noStaffYet => _t('No staff yet. Add your first staff member.', 'अभी कोई स्टाफ़ नहीं। पहला स्टाफ़ जोड़ें।');
  String get showInactive => _t('Show inactive', 'निष्क्रिय भी दिखाएँ');
  String get inactive => _t('Inactive', 'निष्क्रिय');
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
      _t('Paid: $paid left · Sick: $sick left', 'सवेतन: $paid बाक़ी · बीमारी: $sick बाक़ी');
  String get editLeaveBalance => _t('Set leave balance', 'छुट्टी बैलेंस सेट करें');
  String get paidLeaves => _t('Paid leaves (per year)', 'सवेतन छुट्टियाँ (साल में)');
  String get sickLeaves => _t('Sick leaves (per year)', 'बीमारी की छुट्टियाँ (साल में)');
  String get device => _t('Phone', 'फ़ोन');
  String get deviceBound => _t('Linked to a phone', 'एक फ़ोन से जुड़ा है');
  String get deviceNotLinked => _t('Not logged in yet', 'अभी लॉगिन नहीं किया');
  String get resetDevice => _t('Reset phone', 'फ़ोन रीसेट करें');
  String get resetDeviceConfirm =>
      _t('Staff can then log in from a new phone. Continue?', 'इसके बाद स्टाफ़ नए फ़ोन से लॉगिन कर सकेगा। आगे बढ़ें?');
  String get deviceReset => _t('Phone reset done', 'फ़ोन रीसेट हो गया');
  String get deactivate => _t('Deactivate staff', 'स्टाफ़ को निष्क्रिय करें');
  String get deactivateConfirm => _t(
    'They will not be able to check in and will not appear in salary.',
    'वे हाज़िरी नहीं लगा पाएँगे और सैलरी में नहीं दिखेंगे।',
  );
  String get deactivated => _t('Staff deactivated', 'स्टाफ़ निष्क्रिय किया गया');
  String get editStaff => _t('Edit staff', 'स्टाफ़ बदलें');
  String get effectiveFrom => _t('Salary change effective from', 'सैलरी बदलाव कब से लागू');
  String get staffSaved => _t('Staff saved', 'स्टाफ़ सेव हो गया');
  String get callStaff => _t('Call', 'कॉल करें');
  String get consentGiven => _t('Location consent given', 'लोकेशन की सहमति दी');
  String get consentPending => _t('Location consent pending', 'लोकेशन की सहमति बाक़ी');
  String get none => _t('None', 'कोई नहीं');
  String get defaultShift => _t('Default shift', 'डिफ़ॉल्ट शिफ़्ट');

  // ----------------------------------------------------------- Attendance
  String get noAttendanceRows => _t('No staff to show for this day', 'इस दिन के लिए कोई स्टाफ़ नहीं');
  String get changeStatus => _t('Change status', 'स्थिति बदलें');
  String get overrideReasonHint => _t('Why are you changing it?', 'आप इसे क्यों बदल रहे हैं?');
  String get reasonRequired => _t('Please write a reason', 'कृपया कारण लिखें');
  String get attendanceUpdated => _t('Attendance updated', 'हाज़िरी अपडेट हो गई');
  String get punches => _t('Punches', 'पंच');
  String get noPunches => _t('No punches', 'कोई पंच नहीं');
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

  String revisionLabel(int r) => _t('Revision $r', 'संशोधन $r');
  String get totalNet => _t('Total to pay', 'कुल देना है');
  String get deductions => _t('Deductions', 'कटौती');
  String employeesCount(int n) => _t('$n staff', '$n स्टाफ़');
  String get anomalies => _t('Please check', 'कृपया जाँचें');
  String get sendPayslips => _t('Send salary slips', 'सैलरी स्लिप भेजें');
  String payslipsQueued(int n) => _t('$n salary slips are being sent', '$n सैलरी स्लिप भेजी जा रही हैं');
  String get markPaid => _t('Mark as paid', 'भुगतान हुआ मार्क करें');
  String get revise => _t('Make a correction', 'सुधार करें');
  String get reviseConfirm => _t(
    'A new draft (revision) will be created from current attendance.',
    'मौजूदा हाज़िरी से नया ड्राफ़्ट (संशोधन) बनेगा।',
  );
  String payableDays(num d, num div) => _t('Payable days: $d / $div', 'भुगतान वाले दिन: $d / $div');
  String get payslips => _t('Salary slips', 'सैलरी स्लिप');
  String get advances => _t('Advances', 'एडवांस');
  String get bonusDeduction => _t('Bonus / deduction', 'बोनस / कटौती');
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
  String get billing => _t('Plan & billing', 'प्लान और बिलिंग');
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
  String get weekOffsPaid => _t('Weekly offs are paid', 'साप्ताहिक छुट्टी का वेतन मिलेगा');
  String get holidaysPaid => _t('Holidays are paid', 'त्योहार की छुट्टी का वेतन मिलेगा');
  String get sickLeavePaid => _t('Sick leave is paid', 'बीमारी की छुट्टी का वेतन मिलेगा');
  String get selfieRequired => _t('Selfie required at check-in', 'चेक-इन पर सेल्फ़ी ज़रूरी');
  String get roundToRupee => _t('Round salary to nearest rupee', 'सैलरी पूरे रुपये में करें');
  String get whatsappAlerts => _t('WhatsApp alerts', 'WhatsApp अलर्ट');
  String get shifts => _t('Shifts', 'शिफ़्ट');
  String get addShift => _t('Add shift', 'शिफ़्ट जोड़ें');
  String get shiftName => _t('Shift name', 'शिफ़्ट का नाम');
  String get startTime => _t('Start', 'शुरू');
  String get endTime => _t('End', 'ख़त्म');
  String get weeklyOff => _t('Weekly off', 'साप्ताहिक छुट्टी');
  String get useCompanyGrace =>
      _t('Grace minutes (blank = business default)', 'छूट के मिनट (ख़ाली = बिज़नेस डिफ़ॉल्ट)');
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
        return _t('Payment due', 'भुगतान बाक़ी');
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
    '$date को ख़त्म होगा। फिर आप Free पर आ जाएँगे: डेटा रहेगा, पेड फ़ीचर रुक जाएँगे।',
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
        return _t('Mint AI assistant', 'Mint AI सहायक');
      case 'branches':
        return _t('Multiple branches', 'कई ब्रांच');
      case 'reports':
        return _t('Reports', 'रिपोर्ट');
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
    'मासिक सैलरी ÷ दिन (आपकी सेटिंग) × भुगतान वाले दिन, plus बोनस, minus एडवांस और कटौती। सैलरी स्लिप की हर लाइन का कारण लिखा होता है।',
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
        '• आप कभी भी अपने नियोक्ता से अपना डेटा देखने या सुधारने को कह सकते हैं।\n\n'
        'यह सूचना भारत के डिजिटल व्यक्तिगत डेटा संरक्षण (DPDP) अधिनियम, 2023 के अनुसार है।',
  );
  String get consentAgree => _t('I agree — allow location at check-in', 'मैं सहमत हूँ — चेक-इन पर लोकेशन की अनुमति');
  String get yourEmployer => _t('Your employer', 'आपका नियोक्ता');

  String get checkIn => _t('Check in', 'हाज़िरी लगाएँ');
  String get checkOut => _t('Check out', 'चेक-आउट करें');
  String get checkInHint => _t('1 tap', 'Check in · 1 tap');
  String get checkOutHint => _t('Going home?', 'Check out');
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
  String get faceMatchPolicy => _t('Face check at check-in', 'पंच पर चेहरा पहचान');
  String get faceMatchPolicyHelp => _t(
    'Each check-in selfie is compared with the staff member\'s approved photo. If it doesn\'t clearly match, the check-in waits for you. Staff must agree before their photo is used. Growth plan and above.',
    'हर पंच की सेल्फ़ी स्टाफ़ की मंज़ूर फ़ोटो से मिलाई जाती है। साफ़ मेल न खाए तो हाज़िरी आपकी मंज़ूरी के बाद लगेगी। स्टाफ़ की सहमति के बिना फ़ोटो इस्तेमाल नहीं होती। Growth प्लान और ऊपर।',
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
  String pendingSync(int n) => _t('$n punch(es) waiting to sync', '$n पंच सिंक होने बाक़ी');
  String get syncNow => _t('Sync now', 'अभी सिंक करें');
  String syncedCount(int n) => _t('$n offline punch(es) synced', '$n ऑफ़लाइन पंच सिंक हुए');
  String syncRejected(String msg) => _t('A saved punch was rejected: $msg', 'एक सेव पंच अस्वीकार हुआ: $msg');
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
  String paidLeft(num n) => _t('Paid: $n left', 'सवेतन: $n बाक़ी');
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
  String get emailHint => _t('For reports and receipts (optional)', 'रिपोर्ट और रसीद के लिए (वैकल्पिक)');
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
  String needsYouPunch(String name) => _t('$name’s punch', '$name का पंच');
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
  String get mintSubtitle => _t('your assistant · online', 'आपका सहायक · online');
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
  Bi get salaryDayBi => _b('Salary day', 'सैलरी डे');
  Bi get stepReview => _b('Review', 'जाँचें');
  Bi get stepSend => _b('Approve & send', 'भेजें');
  Bi get stepPaid => _b('Paid', 'भुगतान');
  Bi get cashNeeded => _b('Cash needed', 'कुल देना है');
  String earnedAmount(String a) => _t('$a earned', '$a कमाई');
  String advanceRecovered(String a) => _t('−$a advance', '−$a एडवांस');
  String get isThatRight => _t('Is that right?', 'क्या यह सही है?');
  String get looksRight => _t('Looks right', 'ठीक है');
  String get change => _t('Change', 'बदलें');
  Bi othersFine(int n) => _b('$n others look fine', 'बाकी $n staff में कोई दिक्कत नहीं');
  Bi allFine(int n) => _b('All $n staff look fine', 'सभी $n staff ठीक हैं');
  String get slideApproveSend => _t('Slide to approve & send salary slips', 'स्लाइड करें · Approve & send');
  String get slideMarkPaid => _t('Slide to mark as paid', 'स्लाइड करें · Mark as paid');
  String get slideA11yHint => _t('Double-tap and hold to confirm', 'पक्का करने के लिए दबाए रखें');
  Bi get salaryApprovedBi => _b('Salary approved!', 'सैलरी मंज़ूर!');
  String payslipsSentTo(int n) => _t('Salary slips are going to $n staff', '$n staff को सैलरी स्लिप भेजी जा रही हैं');
  Bi get salaryPaidBi => _b('Marked as paid', 'भुगतान दर्ज हुआ');
  String get paidBanner => _t('Salary for this month is paid', 'इस महीने की सैलरी दे दी गई');
  String get sendAgain => _t('Send salary slips again', 'सैलरी स्लिप फिर भेजें');
  String daysOf(num p, num d) => _t('$p of $d days', '$d में से $p दिन');
  String daysOnly(num p) => _t('$p days', '$p दिन');

  // -------------------------------------------------------------- Mark as paid
  String get paidQuestion => _t('Have you paid everyone?', 'क्या सबको सैलरी दे दी?');
  String get paidNoMoneyNote => _t(
    'StaffMint doesn\'t send money. This records that you paid, so salary slips show "Paid".',
    'StaffMint पैसे नहीं भेजता। यह सिर्फ़ दर्ज करता है कि आपने सैलरी दे दी, ताकि स्लिप पर "भुगतान हो गया" दिखे।',
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
  String get notPaidYet => _t('Not paid yet', 'अभी भुगतान नहीं हुआ');
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
  String get esiTitle => _t('ESI', 'ESI (कर्मचारी राज्य बीमा)');
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
  String get employeeCodeLabel => _t('Employee ID', 'कर्मचारी ID');
  String get uanLabel => _t('PF UAN (12 digits)', 'PF UAN (12 अंक)');
  String get esicLabel => _t('ESIC number', 'ESIC नंबर');
  String get panLabel => _t('PAN', 'PAN');
  String get pfExemptLabel => _t('Not in PF', 'PF में नहीं');
  String get esiExemptLabel => _t('Not in ESI', 'ESI में नहीं');
  String get slipDetailsHint => _t(
    'Employee ID, PF UAN, ESIC, PAN. Optional — fill only what your shop uses.',
    'कर्मचारी ID, PF UAN, ESIC, PAN. ज़रूरी नहीं — जो आपकी दुकान में चलता है वही भरें।',
  );

  // -------------------------------------------------------------- Salary slip
  Bi get payslipBi => _b('Salary slip', 'सैलरी स्लिप');
  Bi get netPayBi => _b('Net pay', 'हाथ में वेतन');
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
  String get paymentId => _t('A past StaffMint payment ID', 'पिछले StaffMint भुगतान की ID');
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
    'अपने बाकी बिज़नेस का भुगतान यहीं करें। स्टाफ़ सबका जुड़कर गिना जाएगा; हर अतिरिक्त बिज़नेस $extra/महीना।',
  );
  String get onThisBill => _t('On this bill', 'इस बिल में');
  String get addToBill => _t('Add to this bill', 'इस बिल में जोड़ें');
  String get removeFromBill => _t('Remove from bill', 'बिल से हटाएँ');
  String billedWith(String name) =>
      _t('Paid together with $name. Change the plan there.', '$name के साथ भुगतान होता है। प्लान वहीं बदलें।');
  String totalStaffOnBill(int n) => _t('$n staff on this bill', 'इस बिल में $n स्टाफ़');

  // ---------------------------------------------------------------- Misc
  String get thisMonth => _t('This month', 'इस महीने');
  String get offlineNote => _t('Offline · showing saved data', 'ऑफ़लाइन · सेव डेटा दिखा रहे हैं');

  // ---------------------------------------------------------------- Money
  String money(int paise) => Money.format(paise);
}

extension StringsContext on BuildContext {
  S get s => S.of(this);
}
