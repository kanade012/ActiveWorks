import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../services/auth_service.dart';
import '../models/user_model.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({Key? key}) : super(key: key);

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController _groupNameController = TextEditingController();
  bool _isCreating = false;
  final AuthService _authService = AuthService();
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF9FAFC),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppBar(
              backgroundColor: Color(0xFFF9FAFC),
              title: Text('그룹 생성'),
              scrolledUnderElevation: 0,
              shadowColor: Colors.transparent,
              elevation: 0,
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _groupNameController,
                    decoration: InputDecoration(
                      labelText: '그룹 이름',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 20),
                  _isCreating
                      ? CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _createGroup,
                          child: Text('그룹 생성'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: Size(double.infinity, 50),
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createGroup() async {
    setState(() {
      _isCreating = true;
    });

    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹 이름을 입력하세요.')),
      );
      setState(() {
        _isCreating = false;
      });
      return;
    }

    try {
      final user = _authService.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인이 필요합니다.')),
        );
        setState(() {
          _isCreating = false;
        });
        return;
      }

      // 참여 코드 생성 (6자리 무작위 코드)
      final random = Random();
      final joinCode = List.generate(6, (_) => random.nextInt(10)).join();

      // 그룹 생성
      final groupRef = await FirebaseFirestore.instance.collection('groups').add({
        'name': groupName,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'members': [user.uid],
        'joinCode': joinCode,
      });

      // 사용자의 그룹 목록에 추가
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('groups')
          .doc(groupRef.id)
          .set({
        'groupId': groupRef.id,
        'name': groupName,
        'joinedAt': FieldValue.serverTimestamp(),
        'isCreator': true,
      });

      // 성공 메시지 및 참여 코드 표시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('그룹이 생성되었습니다. 참여 코드: $joinCode'),
          duration: Duration(seconds: 5),
        ),
      );

      // 그룹 생성 후 이전 화면으로 이동
      Future.delayed(Duration(seconds: 1), () {
        Navigator.pop(context);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹 생성에 실패했습니다: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
} 