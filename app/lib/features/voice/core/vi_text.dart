const _from = 'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
const _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Viết thường, bỏ dấu tiếng Việt, bỏ ký tự lạ, gộp khoảng trắng (để so tên không phân biệt dấu).
String viNorm(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = _from.indexOf(ch);
    b.write(i >= 0 ? _to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Người dùng chào tạm biệt (câu ngắn). Cùng luật với `isGoodbye` ở máy chủ: "nhắn cho Lan là tạm biệt" không tính.
bool isGoodbyeText(String text) {
  final t = viNorm(text);
  if (t.isEmpty || t.split(' ').length > 6) return false;
  return RegExp(
    r'^(vy |co vy |em vy )?(cam on )?(vy |con |em )?(chao )?(tam biet|bye|bye bye|hen gap lai|chao nhe|chao nha|tat vy di|dong vy lai|ket thuc di|vy nghi di|thoi nghi di)( vy| con| em| nhe| nha| a| nghen| nhi| nhoe)*$',
  ).hasMatch(t);
}
