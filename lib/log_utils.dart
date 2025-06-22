import 'package:logger/logger.dart';

const String _TAG = "loggerTag";
bool showLog = true;

final _logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
  ),
);

LogD(String msg, {String tag = _TAG}) {
  _logger.d("$tag :: $msg");
}

LogE(String msg, {String tag = _TAG}) {
  _logger.e("$tag :: $msg");
}