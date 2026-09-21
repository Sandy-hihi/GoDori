bool hasValidImage(dynamic url) {
  if (url == null) return false;
  final s = url.toString();
  return s.isNotEmpty;
}
