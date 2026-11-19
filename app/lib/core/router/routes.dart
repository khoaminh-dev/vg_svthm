/// Tên đường dẫn tập trung, tránh viết chuỗi rải rác.
abstract final class Routes {
  static const login = '/login';
  static const register = '/register';
  static const completeProfile = '/complete-profile';
  static const chooseRole = '/choose-role';
  static const chooseRoleChange = '/choose-role/change';
  static const rooms = '/rooms';
  static const room = '/rooms/:id';
  static String roomPath(String id) => '/rooms/$id';
  static const measure = '/measure';
  static const entertainment = '/entertainment';
  static const player = '/entertainment/play';
  static const ocr = '/ocr';
  static const ocrEdit = '/ocr/edit';
  static const ocrDetail = '/ocr/detail';
  static const bp = '/bp';
  static const home = '/';
  static const profile = '/profile';
  static const community = '/community';
  static const camera = '/camera';
  static const liveLab = '/live-lab';
  static const healthSetup = '/health-setup';
  static const healthProfile = '/health-profile';
  static const healthHistory = '/health-history';
  static const familyJoin = '/family/join';
  static const familyInvite = '/family/invite';
  static const familyAudit = '/family/audit';
  static const familyPerson = '/family/person/:id';
  static const medsPlans = '/meds/plans/:owner';
  static const medsPlan = '/meds/plan/:owner';
  static const sos = '/sos/:id';
  static String sosFor(String id) => '/sos/$id';
  static const emergencyCard = '/emergency/:owner';
  static String emergencyCardFor(String owner) => '/emergency/$owner';
  static const medsScan = '/meds/scan/:owner';
  static String medsScanFor(String owner) => '/meds/scan/$owner';
  static String medsPlanListFor(String owner) => '/meds/plans/$owner';
  static String medsPlanFor(String owner, {String? planId}) =>
      '/meds/plan/$owner';
  static String familyPersonPath(String id) => '/family/person/$id';

  /// Bốn tab chính (có thanh điều hướng dưới). Màn "Sức khoẻ" dùng đường dẫn `/bp`.
  static const tabs = [home, rooms, bp, profile];

  /// Màn Cảnh báo của người thân.
  static const alerts = '/alerts';

  /// Bốn tab của người thân: Gia đình · Cảnh báo · Tin nhắn · Tôi (Sức khoẻ của chính mình nằm trong "Tôi").
  static const familyTabs = [home, alerts, rooms, profile];

  /// Các trang không cần đăng nhập.
  static const publicRoutes = {login, register};
}
