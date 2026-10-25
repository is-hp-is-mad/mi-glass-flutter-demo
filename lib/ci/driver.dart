/// What the CI capture script can do to the demo.
abstract interface class DemoDriver {
  void setMenu(bool open);
  void setDialog(bool open);
  void setDark(bool dark);

  /// Settings page: push / pop it, scroll its list, open / close the temperature unit options.
  void setSettings(bool open);
  void settingsScroll(double offset);
  void settingsOptions(bool open);
}
