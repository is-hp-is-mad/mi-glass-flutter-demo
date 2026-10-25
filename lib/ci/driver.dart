/// What the CI capture script can do to the demo.
abstract interface class DemoDriver {
  void setMenu(bool open);
  void setDialog(bool open);
  void setDark(bool dark);
}
