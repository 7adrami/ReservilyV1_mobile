/// Web-only settings stand-in used on non-web platforms.
///
/// `geolocator_web` (which provides `WebSettings`) cannot be imported on
/// Android/iOS because it depends on `dart:js_interop`, so this minimal
/// stub keeps the conditional import compiling everywhere.
library;

import 'package:geolocator/geolocator.dart';

class WebSettings extends LocationSettings {
  WebSettings({
    super.accuracy,
    super.distanceFilter,
    super.timeLimit,
    this.maximumAge = Duration.zero,
  });

  final Duration maximumAge;
}
