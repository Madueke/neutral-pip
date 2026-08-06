class FeatureFlags {
  FeatureFlags._();

  // Temporarily disabled while the floating-window implementation is being
  // stabilized. The implementation remains behind this flag for later repair.
  static const bool floatingOverlayEnabled = false;

  // Connect Trading Accounts: the backend endpoints (POST /connect-account,
  // GET /account-status, POST /disconnect-account) do not exist yet. While
  // this is true the UI runs against in-app mock responses so the flow is
  // testable. Flip to false once the hosted backend is live.
  static const bool mockTradingAccountBackend = true;
}
