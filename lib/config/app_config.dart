/// App-wide configuration constants.
library;

/// Default trading backend the app talks to when the user hasn't set a
/// custom URL in Settings. Baking this in means chat, analysis, watchlist,
/// Connect Trading Accounts and auth all work out of the box with no manual
/// in-app configuration. The user can still override it in Settings.
const String defaultTradingBackendUrl = 'http://16.61.239.225:3000';
