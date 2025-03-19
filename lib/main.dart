import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:planner/page/login_page.dart';
import 'package:window_manager/window_manager.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await Firebase.initializeApp();
  windowManager.setAlwaysOnTop(true);
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'activeworks',
      home: AuthPage()));
}
