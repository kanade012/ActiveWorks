import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';

class JoinGroupPage extends StatefulWidget {
  const JoinGroupPage({Key? key}) : super(key: key);

  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends State<JoinGroupPage> {
  final TextEditingController _joinCodeController = TextEditingController();
  bool _isJoining = false;
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF9FAFC),
      appBar: AppBar(
        backgroundColor: Color(0xFFF9FAFC),
        title: Text('그룹 참가'),
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        elevation: 0,
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
                    controller: _joinCodeController,
                    decoration: InputDecoration(
                      labelText: '참여 코드',
                      hintText: '6자리 참여 코드를 입력하세요',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 20),
                  _isJoining
                      ? CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _joinGroup,
                          child: Text('그룹 참가'),
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

  Future<void> _joinGroup() async {
    setState(() {
      _isJoining = true;
    });

    final joinCode = _joinCodeController.text.trim();
    if (joinCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('참여 코드를 입력하세요.')),
      );
      setState(() {
        _isJoining = false;
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
          _isJoining = false;
        });
        return;
      }

      // 참여 코드로 그룹 찾기
      final querySnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .where('joinCode', isEqualTo: joinCode)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('유효하지 않은 참여 코드입니다.')),
        );
        setState(() {
          _isJoining = false;
        });
        return;
      }

      final groupDoc = querySnapshot.docs.first;
      final groupId = groupDoc.id;
      final groupData = groupDoc.data();
      final List<dynamic> members = List.from(groupData['members'] ?? []);

      // 이미 그룹에 속해 있는지 확인
      if (members.contains(user.uid)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미 가입된 그룹입니다.')),
        );
        setState(() {
          _isJoining = false;
        });
        return;
      }

      // 그룹에 멤버 추가
      members.add(user.uid);
      await FirebaseFirestore.instance.collection('groups').doc(groupId).update({
        'members': members,
      });

      // 사용자의 그룹 목록에 추가
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('groups')
          .doc(groupId)
          .set({
        'groupId': groupId,
        'name': groupData['name'],
        'joinedAt': FieldValue.serverTimestamp(),
        'isCreator': false,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${groupData['name']} 그룹에 참가했습니다.')),
      );

      // 참가 완료 후 이전 화면으로 이동
      Future.delayed(Duration(seconds: 1), () {
        Navigator.pop(context);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('그룹 참가에 실패했습니다: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }
} 