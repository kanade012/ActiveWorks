import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/user_model.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  
  factory AuthService() => _instance;
  
  AuthService._internal();
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  UserModel? _currentUser;
  
  UserModel? get currentUser => _currentUser;
  
  Future<void> init() async {
    await _loadUserFromPreferences();
  }
  
  String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  Future<UserModel?> signInWithEmailAndPassword(String email, String password) async {
    try {
      // 이메일로 사용자 찾기
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      
      if (querySnapshot.docs.isEmpty) {
        throw Exception('이메일 또는 비밀번호가 올바르지 않습니다.');
      }
      
      final userDoc = querySnapshot.docs.first;
      final userData = userDoc.data();
      
      // 비밀번호 확인
      final hashedPassword = _hashPassword(password);
      if (userData['password'] != hashedPassword) {
        throw Exception('이메일 또는 비밀번호가 올바르지 않습니다.');
      }
      
      // 사용자 객체 생성
      _currentUser = UserModel.fromMap({
        'uid': userDoc.id,
        'email': userData['email'],
        'displayName': userData['displayName'],
      });
      
      // 로그인 상태 저장
      await _saveUserToPreferences(_currentUser!);
      
      return _currentUser;
    } catch (e) {
      print('로그인 오류: $e');
      rethrow;
    }
  }
  
  Future<UserModel> createUserWithEmailAndPassword(String email, String password, {String? displayName}) async {
    try {
      // 이미 존재하는 이메일인지 확인
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .get();
      
      if (querySnapshot.docs.isNotEmpty) {
        throw Exception('이미 사용 중인 이메일입니다.');
      }
      
      // 비밀번호 해시
      final hashedPassword = _hashPassword(password);
      
      // 새 사용자 생성
      final userDocRef = await _firestore.collection('users').add({
        'email': email,
        'password': hashedPassword,
        'displayName': displayName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // 사용자 객체 생성
      _currentUser = UserModel(
        uid: userDocRef.id,
        email: email,
        displayName: displayName,
      );
      
      // 로그인 상태 저장
      await _saveUserToPreferences(_currentUser!);
      
      return _currentUser!;
    } catch (e) {
      print('회원가입 오류: $e');
      rethrow;
    }
  }
  
  Future<void> signOut() async {
    _currentUser = null;
    
    // 로그인 상태 삭제
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_uid');
    await prefs.remove('user_email');
    await prefs.remove('user_displayName');
  }
  
  Future<void> _saveUserToPreferences(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_uid', user.uid);
    await prefs.setString('user_email', user.email);
    if (user.displayName != null) {
      await prefs.setString('user_displayName', user.displayName!);
    }
  }
  
  Future<void> _loadUserFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_uid');
    final email = prefs.getString('user_email');
    
    if (uid != null && email != null) {
      final displayName = prefs.getString('user_displayName');
      _currentUser = UserModel(
        uid: uid,
        email: email,
        displayName: displayName,
      );
    }
  }
} 