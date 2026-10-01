import 'package:flutter/material.dart';

import 'app/app_widget.dart';
import 'app/bindings/initial_binding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await InitialBinding.initServices();
  runApp(const AppWidget());
}
