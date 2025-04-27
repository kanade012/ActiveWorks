import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:window_manager/window_manager.dart';

class AuthPage extends StatefulWidget {
  @override
  _AuthPageState createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isLogin = true;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  bool _isLoading = false;
  final AuthService _authService = AuthService();
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppBar(
              backgroundColor: Colors.black,
              title: Text(_isLogin ? '로그인' : '회원가입', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextFormField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: '이메일',
                labelStyle: TextStyle(color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
              style: TextStyle(color: Colors.white),
            ),
            SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: '비밀번호',
                labelStyle: TextStyle(color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
              obscureText: true,
              style: TextStyle(color: Colors.white),
            ),
            if (!_isLogin) ...[
              SizedBox(height: 16),
              TextFormField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: '이름 (선택사항)',
                  labelStyle: TextStyle(color: Colors.white),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
                style: TextStyle(color: Colors.white),
              ),
            ],
            SizedBox(height: 24),
            _isLoading
                ? CircularProgressIndicator(color: Colors.white)
                : Column(
                    children: [
                      _buildButton(
                        text: _isLogin ? '로그인' : '회원가입',
                        onPressed: _handleSubmit,
                      ),
                      SizedBox(height: 16),
                      _buildButton(
                        text: _isLogin ? '회원가입으로 이동' : '로그인으로 이동',
                        onPressed: _toggleAuthMode,
                      ),
                      SizedBox(height: 24),
                      _buildButton(
                        text: '종료',
                        onPressed: _exitApp,
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({required String text, required VoidCallback onPressed}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonWidth = screenWidth * 0.8 > 150 ? screenWidth * 0.8 : 150.0;
    
    return Container(
      width: buttonWidth,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey[800],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  void _toggleAuthMode() {
    setState(() {
      _isLogin = !_isLogin;
    });
  }
  
  void _exitApp() async {
    await windowManager.destroy();
  }

  Future<void> _handleSubmit() async {
    setState(() {
      _isLoading = true;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    
    try {
      if (_isLogin) {
        // 로그인
        await _authService.signInWithEmailAndPassword(email, password);
      } else {
        // 회원가입
        final displayName = _displayNameController.text.trim();
        await _authService.createUserWithEmailAndPassword(
          email, 
          password,
          displayName: displayName.isNotEmpty ? displayName : null
        );
      }
      
      // 메인 페이지로 이동
      Navigator.of(context).pushReplacementNamed('/main');
    } catch (e) {
      String errorMessage = '오류가 발생했습니다. 다시 시도해주세요.';
      if (e is Exception) {
        errorMessage = e.toString().replaceAll('Exception: ', '');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}