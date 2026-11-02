import 'package:flutter/material.dart';

import 'logic/roast_controller.dart';
import 'services/roast_storage.dart';
import 'services/settings.dart';
import 'ui/artisan_colors.dart';
import 'ui/roast_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final storage = await RoastStorage.init();
  final controller = RoastController(settings, storage);
  await controller.init();
  runApp(ArtisanApp(controller: controller));
}

class ArtisanApp extends StatelessWidget {
  const ArtisanApp({super.key, required this.controller});

  final RoastController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Artisan Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: AC.buttonMajor,
        scaffoldBackgroundColor: AC.window,
      ),
      home: RoastScreen(c: controller),
    );
  }
}
