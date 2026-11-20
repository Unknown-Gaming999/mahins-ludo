const String kHostingDomain = String.fromEnvironment('HOSTING_DOMAIN', defaultValue: 'localhost');
const String kDatabaseUrl = String.fromEnvironment('DATABASE_URL');
const String kFunctionsRegion = 'us-central1';

String? bootError;

String inviteLink(String code) => 'https://$kHostingDomain/join/$code';

String inviteMessage(String code) =>
    "🎲 Join my game in Mahin's Ludo!\n"
    'Room code: $code\n'
    'Tap to join: ${inviteLink(code)}\n'
    "(No app yet? The link opens a download page.)";
