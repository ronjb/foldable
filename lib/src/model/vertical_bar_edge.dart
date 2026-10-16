/// The edge of the window where iOS places the vertical bar.
///
/// On iPhone Duo, apps built against the iOS 27.1 SDK get a vertical bar along
/// one side of the window. The status bar turns vertical and moves into it,
/// and native apps move their toolbar and tab bar items into it too. Flutter
/// sees only the safe area inset the system adds on that side, as
/// `MediaQuery.viewPadding`; this says which side it is.
///
/// Mirrors `UITraitCollection.verticalBarEdge`.
enum VerticalBarEdge {
  /// The leading edge: the left in a left-to-right locale.
  leading('leading'),

  /// The trailing edge: the right in a left-to-right locale.
  trailing('trailing'),

  /// No vertical bar is used here: other hardware, an SDK before iOS 27.1, or
  /// a size class or orientation without one.
  unspecified('unspecified');

  const VerticalBarEdge(this.wireName);

  /// The identifier used on the platform channel.
  final String wireName;

  /// Decodes a wire value, falling back to [unspecified].
  static VerticalBarEdge fromWire(Object? value) => switch (value) {
    'leading' => VerticalBarEdge.leading,
    'trailing' => VerticalBarEdge.trailing,
    _ => VerticalBarEdge.unspecified,
  };
}
