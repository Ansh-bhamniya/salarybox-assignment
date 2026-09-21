import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:iconsax/iconsax.dart';

/// Every icon the app uses, by role. Iconsax (linear) is the main set; Fluent
/// System Icons cover filled status glyphs and a few Iconsax doesn't have.
/// Screens use `AppIcons.x`, never `Icons.x`, so swapping an icon is one line.
class AppIcons {
  AppIcons._();

  // Navigation & actions
  static const IconData back = Iconsax.arrow_left_2;
  static const IconData add = Iconsax.add;
  static const IconData addStaff = Iconsax.user_add;
  static const IconData logout = Iconsax.logout;
  static const IconData refresh = Iconsax.refresh;
  static const IconData delete = Iconsax.trash;
  static const IconData camera = Iconsax.camera;
  static const IconData clock = Iconsax.clock;

  // Theme
  static const IconData darkMode = Iconsax.moon;
  static const IconData lightMode = Iconsax.sun_1;

  // Forms
  static const IconData person = Iconsax.user;
  static const IconData lock = Iconsax.lock;
  static const IconData visible = Iconsax.eye;
  static const IconData hidden = Iconsax.eye_slash;
  static const IconData idBadge = Iconsax.personalcard;
  static const IconData adminAccess = Iconsax.security_user;

  // Content
  static const IconData people = Iconsax.people;
  static const IconData place = Iconsax.location;
  static const IconData face = FluentIcons.emoji_sparkle_24_regular;
  static const IconData noEvents = FluentIcons.calendar_cancel_24_regular;
  static const IconData brokenImage = FluentIcons.image_off_24_regular;

  // Status
  static const IconData checkFilled = FluentIcons.checkmark_circle_24_filled;
  static const IconData success = Iconsax.tick_circle;
  static const IconData warning = FluentIcons.warning_24_regular;
  static const IconData error = FluentIcons.error_circle_24_regular;
  static const IconData cameraOff = FluentIcons.camera_off_24_regular;
  static const IconData faceOff = FluentIcons.person_prohibited_24_regular;
}
