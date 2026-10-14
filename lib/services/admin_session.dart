/// 관리자 웹 로그인 상태. 비밀번호는 저장하지 않고 앱이 켜져 있는 동안 메모리에만 둡니다.
/// (새로고침하면 다시 로그인해야 해요)
class AdminSession {
  static String? password;

  static bool get isLoggedIn => password != null && password!.isNotEmpty;
}
