import 'package:intl/intl.dart';

class DateFormatter {
  static String formatConversationTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);

    if (itemDate == today) {
      return DateFormat('HH:mm').format(date);
    } else if (today.difference(itemDate).inDays == 1) {
      return 'Kecha';
    } else if (today.difference(itemDate).inDays < 7) {
      return DateFormat('EEEE').format(date);
    } else {
      return DateFormat('dd.MM.yyyy').format(date);
    }
  }

  static String formatMessageTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }
}
