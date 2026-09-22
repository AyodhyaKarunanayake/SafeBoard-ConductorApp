/// The boarding code a conductor reads out to a passenger after collecting
/// their cash fare, so the passenger can start their journey in the app.
///
/// This is a fixed pilot value, not generated or looked up: the passenger
/// app's `TicketsProvider.startJourney` checks the OTP a passenger types
/// against one hardcoded value ("1234"), so showing the conductor anything
/// else would simply fail to start the passenger's journey. If a real,
/// per-passenger code is ever wanted, both apps need to change together.
const String kBoardingOtp = '1234';
