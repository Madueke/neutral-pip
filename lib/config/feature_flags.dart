class FeatureFlags {
  FeatureFlags._();

  // Temporarily disabled while the floating-window implementation is being
  // stabilized. The implementation remains behind this flag for later repair.
  static const bool floatingOverlayEnabled = false;

  // Connect Trading Accounts: the backend endpoints (POST /connect-account,
  // GET /account-status, POST /disconnect-account) are live and auth-gated
  // (Bearer session token). Mock responses are no longer used.
  static const bool mockTradingAccountBackend = false;
}
