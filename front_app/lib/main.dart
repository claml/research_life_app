import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app/research_life_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);
  runApp(const ResearchLifeApp());
}
