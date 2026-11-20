import 'package:itp_voice/helpers/group_chat.dart' show formatPhoneNumber;

/// Unqualified ten-digit contact numbers use the North American calling code.
String newContactPhone(String input) {
  final number = input.replaceAll(RegExp(r'[\s().-]'), '');
  if (RegExp(r'^\d{10}$').hasMatch(number)) return '+1$number';
  if (RegExp(r'^1\d{10}$').hasMatch(number)) return '+$number';
  return number;
}

String displayNewContactPhone(String input) {
  final number = newContactPhone(input);
  return RegExp(r'^\+1\d{10}$').hasMatch(number)
      ? formatPhoneNumber(number)
      : input;
}
