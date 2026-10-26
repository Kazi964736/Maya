/// Popular apps in India: spoken names -> Android package.
/// Opening any other app falls back to a Play Store search.
const knownApps = <String, List<String>>{
  'com.whatsapp': ['whatsapp', 'হোয়াটসঅ্যাপ', 'হোয়াটসঅ্যাপ', 'व्हाट्सएप', 'व्हाट्सऐप'],
  'com.google.android.youtube': ['youtube', 'ইউটিউব', 'यूट्यूब'],
  'com.phonepe.app': ['phonepe', 'phone pe', 'ফোনপে', 'फोनपे'],
  'com.google.android.apps.nbu.paisa.user': ['gpay', 'google pay', 'জিপে', 'गूगल पे', 'जीपे'],
  'net.one97.paytm': ['paytm', 'পেটিএম', 'पेटीएम'],
  'com.instagram.android': ['instagram', 'insta', 'ইনস্টাগ্রাম', 'इंस्टाग्राम'],
  'com.facebook.katana': ['facebook', 'fb', 'ফেসবুক', 'फेसबुक'],
  'com.android.chrome': ['chrome', 'browser', 'ক্রোম', 'क्रोम'],
  'com.google.android.apps.maps': ['maps', 'google maps', 'map', 'ম্যাপ', 'मैप'],
  'com.google.android.gm': ['gmail', 'mail', 'email', 'জিমেইল', 'जीमेल'],
  'com.google.android.apps.photos': ['photos', 'gallery', 'গ্যালারি', 'गैलरी', 'फोटो'],
  'com.spotify.music': ['spotify', 'স্পটিফাই', 'स्पॉटिफाई'],
  'com.jio.media.jiobeats': ['jiosaavn', 'saavn', 'জিও সাভন'],
  'in.startv.hotstar': ['hotstar', 'jiohotstar', 'হটস্টার', 'हॉटस्टार'],
  'com.netflix.mediaclient': ['netflix', 'নেটফ্লিক্স', 'नेटफ्लिक्स'],
  'in.amazon.mShop.android.shopping': ['amazon', 'আমাজন', 'अमेज़न'],
  'com.flipkart.android': ['flipkart', 'ফ্লিপকার্ট', 'फ्लिपकार्ट'],
  'com.meesho.supply': ['meesho', 'মিশো', 'मीशो'],
  'com.application.zomato': ['zomato', 'জোমাটো', 'ज़ोमैटो'],
  'in.swiggy.android': ['swiggy', 'সুইগি', 'स्विगी'],
  'org.telegram.messenger': ['telegram', 'টেলিগ্রাম', 'टेलीग्राम'],
  'com.truecaller': ['truecaller', 'ট্রুকলার', 'ट्रूकॉलर'],
  'com.google.android.calendar': ['calendar', 'ক্যালেন্ডার', 'कैलेंडर'],
  'com.google.android.deskclock': ['clock', 'alarm clock', 'ঘড়ি', 'घड़ी'],
  'com.google.android.calculator': ['calculator', 'ক্যালকুলেটর', 'कैलकुलेटर'],
  'com.android.vending': ['play store', 'playstore', 'প্লে স্টোর', 'प्ले स्टोर'],
  'com.irctc.rail.connect': ['irctc', 'train', 'রেল', 'रेल'],
};

/// Returns the package for a spoken app name, or null if unknown.
String? packageForApp(String spoken) {
  final s = spoken.toLowerCase().replaceAll(RegExp(r'\s*(app|অ্যাপ|ऐप)$'), '').trim();
  for (final entry in knownApps.entries) {
    if (entry.value.contains(s)) {
      return entry.key;
    }
  }
  for (final entry in knownApps.entries) {
    if (entry.value.any((name) => name.length >= 4 && (s.contains(name) || name.contains(s) && s.length >= 4))) {
      return entry.key;
    }
  }
  return null;
}
