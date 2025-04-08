import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:planner/page/login_page.dart';
import 'package:planner/page/main_page.dart';
import 'package:window_manager/window_manager.dart';
import 'services/auth_service.dart';

void main() async {
  // Flutter 바인딩 초기화
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase 초기화
  await Firebase.initializeApp();
  
  // window_manager 초기화 - 이 부분이 중요합니다
  await windowManager.ensureInitialized();
  
  // 윈도우 설정
  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
  );
  
  // window_manager 설정 적용
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // AuthService 초기화
  final authService = AuthService();
  await authService.init();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Planner App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: _authService.currentUser != null ? '/main' : '/login',
      routes: {
        '/login': (context) => AuthPage(),
        '/main': (context) => MainPage(),
      },
    );
  }
}
