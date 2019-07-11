/// A version of moor that runs on the web by using [sql.js](https://github.com/kripken/sql.js)
/// You manually need to include that library into your website to use the
/// web version of moor.
@experimental
library moor_web;

import 'dart:async';
import 'dart:html';

import 'package:meta/meta.dart';
import 'package:meta/dart2js.dart';
import 'package:synchronized/synchronized.dart';

import 'moor.dart';
import 'src/web/binary_string_conversion.dart';
import 'src/web/sql_js.dart';

export 'moor.dart';

part 'src/web/web_db.dart';
