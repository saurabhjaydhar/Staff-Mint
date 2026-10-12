import '../../../core/i18n/strings.dart';

/// Short answers grouped by task. Each answer names the exact screen to open.
List<(String, List<(String, String)>)> helpGroups(S s) {
  String t(String en, String hi) => s.isHindi ? hi : en;
  return [
    (
      s.helpGettingStarted,
      [
        (s.faq1q, s.faq1a),
        (
          t('Add staff from Excel or SalaryBox', 'Excel या SalaryBox से स्टाफ़ जोड़ें'),
          t(
            'On a computer, open app.staffmint.app → Import. Upload the file; StaffMint matches the columns, shows any problems, and you can undo for 24 hours.',
            'कंप्यूटर पर app.staffmint.app → Import खोलें। फ़ाइल डालें; StaffMint कॉलम मिलाता है, गड़बड़ी दिखाता है, और 24 घंटे तक वापस ले सकते हैं।',
          ),
        ),
        (
          t('My staff haven’t joined yet', 'मेरे स्टाफ़ अभी नहीं जुड़े'),
          t(
            'Home shows who hasn’t installed the app. Tap Remind to send the WhatsApp invite again. They log in with their own number — no password.',
            'होम पर दिखता है किसने ऐप इंस्टॉल नहीं किया। “याद दिलाएँ” दबाकर WhatsApp पर फिर से भेजें। वे अपने नंबर से लॉगिन करते हैं — पासवर्ड नहीं।',
          ),
        ),
        (s.faq4q, s.faq4a),
      ],
    ),
    (
      s.helpEveryDay,
      [
        (
          t('Someone forgot to check in', 'कोई चेक-इन करना भूल गया'),
          t(
            'On Home, tap their status (▾), pick what happened and press Save. A reason is optional. Undo stays for a few seconds.',
            'होम पर उनकी स्थिति (▾) दबाएँ, चुनें क्या हुआ और सेव दबाएँ। कारण ज़रूरी नहीं। कुछ सेकंड तक “वापस लें” रहता है।',
          ),
        ),
        (s.faq2q, s.faq2a),
        (
          t('What do the colours mean?', 'रंगों का क्या मतलब है?'),
          t(
            'Green ✓ present, yellow late, red ✕ absent, orange ½ half day, purple leave, grey week off or holiday. The month calendar shows this legend on top.',
            'हरा ✓ हाज़िर, पीला लेट, लाल ✕ ग़ैरहाज़िर, नारंगी ½ आधा दिन, बैंगनी छुट्टी, स्लेटी साप्ताहिक छुट्टी या त्योहार। महीने के कैलेंडर में ऊपर यही दिखता है।',
          ),
        ),
        (
          t('Someone checked in away from the shop', 'किसी ने दुकान से दूर चेक-इन किया'),
          t(
            'It waits in “Needs your OK” on Home. Tap Count it if they were really working (for example on a delivery), or Don’t count.',
            'यह होम पर “आपकी मंज़ूरी” में रुकता है। अगर वे सच में काम पर थे (जैसे डिलीवरी) तो “मान लें”, नहीं तो “न मानें” दबाएँ।',
          ),
        ),
        (
          t('How do I approve leave?', 'छुट्टी कैसे मंज़ूर करें?'),
          t(
            'Home → “Needs your OK” → Review. You see how many leaves they will have left if you say yes.',
            'होम → “आपकी मंज़ूरी” → देखें। हाँ कहने के बाद कितनी छुट्टियाँ बचेंगी, वह भी दिखता है।',
          ),
        ),
      ],
    ),
    (
      s.helpSalary,
      [
        (s.faq3q, s.faq3a),
        (
          t('How do I give an advance (udhaar)?', 'एडवांस (उधार) कैसे दें?'),
          t(
            'Salary → Advances (udhaar) → Give an advance. You see how the next salary changes before saving. Take it back all at once or every month.',
            'सैलरी → एडवांस (उधार) → एडवांस दें। सेव करने से पहले दिखता है कि अगली सैलरी कितनी होगी। एक बार में या हर महीने वापस लें।',
          ),
        ),
        (
          t('Does StaffMint send money?', 'क्या StaffMint पैसे भेजता है?'),
          t(
            'No. Step 3 “I’ve paid” only records how and when you paid. Each salary slip then shows it.',
            'नहीं। कदम 3 “दे दिया” सिर्फ़ लिखकर रखता है कि कब और कैसे दिया। फिर हर सैलरी स्लिप पर यह दिखता है।',
          ),
        ),
        (
          t('I approved salary but need to change it', 'सैलरी मंज़ूर कर दी, अब बदलनी है'),
          t(
            'Salary → Edit salary. A new version is made and the old one is kept.',
            'सैलरी → सैलरी बदलें। नया वर्ज़न बनता है और पुराना रखा जाता है।',
          ),
        ),
        (
          t('PF, ESI and Professional Tax', 'PF, ESI और प्रोफ़ेशनल टैक्स'),
          t(
            'Off for most small shops. More → Salary rules → PF, ESI & Professional Tax. The salary slip then shows Basic, HRA and each deduction.',
            'ज़्यादातर छोटी दुकानों में बंद रहते हैं। और → सैलरी के नियम → PF, ESI और प्रोफ़ेशनल टैक्स। फिर सैलरी स्लिप पर Basic, HRA और हर कटौती दिखती है।',
          ),
        ),
      ],
    ),
    (
      s.helpTeam,
      [
        (
          t('Add my CA or a partner', 'अपने CA या पार्टनर को जोड़ें'),
          t(
            'Staff tab → Team & access → Add your CA, or Add partner.',
            'स्टाफ़ टैब → टीम और अनुमति → CA जोड़ें, या पार्टनर जोड़ें।',
          ),
        ),
        (
          t('Make someone a manager', 'किसी को मैनेजर बनाएँ'),
          t(
            'Staff tab → Team & access → Make a staff member manager. They can fix attendance and approve leave, but can’t see salary.',
            'स्टाफ़ टैब → टीम और अनुमति → किसी स्टाफ़ को मैनेजर बनाएँ। वे हाज़िरी ठीक कर सकते हैं और छुट्टी मंज़ूर कर सकते हैं, पर सैलरी नहीं देख सकते।',
          ),
        ),
        (
          t('Change the late time or half-day rule', 'लेट या आधे दिन का नियम बदलें'),
          t(
            'More → Attendance rules. Each rule shows an example. Changes apply from today; past days stay as they are.',
            'और → हाज़िरी के नियम। हर नियम के साथ उदाहरण है। बदलाव आज से लागू होते हैं; पुराने दिन वैसे ही रहते हैं।',
          ),
        ),
        (
          t('Stop people marking attendance for someone else', 'कोई किसी और की हाज़िरी न लगाए'),
          t(
            'More → Check-in safety: shop area, selfie, phone lock and face check.',
            'और → चेक-इन सुरक्षा: दुकान का एरिया, सेल्फ़ी, फ़ोन लॉक और चेहरे की जाँच।',
          ),
        ),
      ],
    ),
  ];
}
