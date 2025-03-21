import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:planner/page/main_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({Key? key}) : super(key: key);

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      try {
        if (_isLogin) {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: _emailController.text,
            password: _passwordController.text,
          );
        } else {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _emailController.text,
            password: _passwordController.text,
          );
        }
        
        // 스택을 남기지 않고 메인 페이지로 이동
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => MainPage()),
          (route) => false,
        );
      } on FirebaseAuthException catch (e) {
        setState(() {
          _errorMessage = e.message ?? '알 수 없는 오류가 발생했습니다.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 화면 너비 구하기 - 반응형 디자인을 위해
    final screenWidth = MediaQuery.of(context).size.width;
    // 버튼 너비 계산 (화면 너비의 80%, 최소 150px)
    final buttonWidth = screenWidth * 0.8 > 150 ? screenWidth * 0.8 : 150.0;
    
    return Scaffold(
      backgroundColor: Colors.white, // 배경색 검정으로 변경
      appBar: AppBar(
        backgroundColor: Colors.white, // 앱바 배경색 검정으로 변경
        title: Text(_isLogin ? '로그인' : '회원가입', style: TextStyle(color: Colors.black)),
        leading: Padding(
          padding: EdgeInsets.symmetric(horizontal: 5),
          child: Text("Active Works", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: '이메일',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.black),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.black),
                  ),
                ),
                style: TextStyle(color: Colors.black),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '이메일을 입력해주세요.';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.black),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.black),
                  ),
                ),
                style: TextStyle(color: Colors.black),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '비밀번호를 입력해주세요.';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),
              Container(
                width: buttonWidth, // 반응형 너비 적용
                child: InkWell(
                  onTap: _submit,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: Color(0xFF070707)
                    ),
                    child: Center(
                      child: Text(
                        _isLogin ? '로그인' : '회원가입',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Container(
                width: buttonWidth, // 반응형 너비 적용
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isLogin = !_isLogin;
                      _errorMessage = ''; // 에러 메시지 초기화
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(width: 1, color: Colors.black),
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.white
                    ),
                    child: Center(
                      child: Text(
                        _isLogin ? '회원가입으로 이동' : '로그인으로 이동',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}